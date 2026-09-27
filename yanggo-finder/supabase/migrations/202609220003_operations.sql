begin;
create function public.yg_year() returns integer language sql stable set search_path=public as $$select year from school_years where is_current$$;
create function public.yg_verified(a uuid) returns boolean language sql stable set search_path=public as $$select exists(select 1 from student_verifications where user_id=a and school_year=yg_year() and status='VERIFIED')$$;
create function public.yg_role(a uuid) returns text language sql stable set search_path=public as $$select coalesce((select role::text from council_roles where user_id=a and school_year=yg_year() and revoked_at is null and starts_at<=now() and ends_at>now() and yg_verified(a) limit 1),'STUDENT')$$;
create function public.yg_manager(a uuid) returns boolean language sql stable set search_path=public as $$select yg_role(a) in ('WELFARE_MANAGER','PRESIDENT_TEAM','SUPER_ADMIN')$$;
create function public.yg_verifier(a uuid) returns boolean language sql stable set search_path=public as $$select yg_verified(a) and (yg_role(a)='PRESIDENT_TEAM' or exists(select 1 from council_roles where user_id=a and school_year=yg_year() and role='WELFARE_MANAGER' and is_head and revoked_at is null and starts_at<=now() and ends_at>now()))$$;
create function public.yg_deliverer(a uuid) returns boolean language sql stable set search_path=public as $$select yg_verified(a) and exists(select 1 from council_roles where user_id=a and school_year=yg_year() and revoked_at is null and starts_at<=now() and ends_at>now() and (can_deliver or is_head or role='PRESIDENT_TEAM'))$$;
create function public.yg_notify(a uuid,k text,msg text,ref uuid default null) returns void language sql set search_path=public as $$insert into notifications(recipient_id,school_year,type,message,reference_id) values(a,yg_year(),k,msg,ref)$$;
create function public.yg_log(a uuid,k text,ref uuid default null) returns void language sql set search_path=public as $$insert into audit_logs(actor_id,school_year,action,entity_type,entity_id,request_id) values(a,yg_year(),k,'operation',ref,gen_random_uuid())$$;
create function public.yg_rate_limit(p_key text,p_max integer) returns boolean language plpgsql set search_path=public as $$declare n integer;begin
 insert into login_limits values(p_key,1,now()) on conflict(key) do update set attempts=case when login_limits.window_start<now()-interval '15 minutes' then 1 else login_limits.attempts+1 end,window_start=case when login_limits.window_start<now()-interval '15 minutes' then now() else login_limits.window_start end returning attempts into n;return n<=p_max;end$$;
create function public.yg_signup(p_name text,p_number text,p_hash text,p_path text,p_actor uuid default null) returns uuid language plpgsql set search_path=public as $$declare a uuid;v uuid;y integer;begin
 select year into y from school_years where is_current for share;
 if y is null or char_length(trim(p_name)) not between 2 and 40 or p_number !~ '^[0-9]{5}$' then raise exception '가입 정보를 확인해주세요.';end if;
 if not exists(select 1 from upload_jobs where object_path=p_path and bucket='student-verifications' and owner_id is not distinct from p_actor and not linked and expires_at>now()) then raise exception '학생증 파일을 다시 올려주세요.';end if;
 if p_actor is null then
  if p_hash not like 'scrypt$%' then raise exception '비밀번호 처리 오류';end if;
  insert into users(display_name) values(trim(p_name)) returning id into a;
  insert into pin_credentials values(a,p_hash);
 else a:=p_actor;
  if not exists(select 1 from users where id=a) or yg_verified(a) then raise exception '재인증 대상을 확인해주세요.';end if;
  if exists(select 1 from student_verifications where user_id=a and school_year=y and status='ACCOUNT_PENDING') then raise exception '이미 확인 중인 신청이 있어요.';end if;
 end if;
 insert into student_verifications(user_id,school_year,student_number) values(a,y,p_number) returning id into v;
 insert into verification_uploads(verification_id,object_path,expires_at) values(v,p_path,now()+interval '72 hours');
 update upload_jobs set linked=true where object_path=p_path;
 return a;end$$;
create function public.yg_action(p_actor uuid,p_action text,p jsonb) returns jsonb language plpgsql set search_path=public as $$
declare y integer;submission_row item_submission_requests;it items;c claim_requests;v student_verifications;sl pickup_slots;rs pickup_schedules;obj uuid;start_time timestamptz;end_time timestamptz;n integer;target uuid;newyear integer;old_status item_status;
begin
 select year into y from school_years where is_current for share;
 if y is null or not exists(select 1 from users where id=p_actor) then raise exception '운영 설정과 로그인을 확인해주세요.';end if;
 if p_action='READ' then update notifications set read_at=now() where recipient_id=p_actor and read_at is null;return '{}'::jsonb;end if;
 if not yg_verified(p_actor) then raise exception '현재 학년도 재학생 인증이 필요해요.';end if;
 if p_action in ('RECEIVE','PUBLISH','CLOSE','SUPPLEMENT','DECIDE','EDIT') and not yg_manager(p_actor) then raise exception '관리 권한이 없어요.';end if;
 if p_action='VERIFY' then
  if not yg_verifier(p_actor) then raise exception '학생증 확인 권한이 없어요.';end if;
  select * into v from student_verifications where id=(p->>'id')::uuid and school_year=y for update;
  if v.id is null or v.status<>'ACCOUNT_PENDING' or v.user_id=p_actor then raise exception '처리할 수 없는 인증 요청이에요.';end if;
  if coalesce(p->>'decision','') not in ('VERIFIED','REJECTED') then raise exception '인증 상태 오류';end if;
  if not exists(select 1 from verification_uploads where verification_id=v.id and delete_status='PENDING' and expires_at>now()) then raise exception '사진이 만료됐어요. 재제출이 필요해요.';end if;
  update student_verifications set status=p->>'decision',reviewed_by=p_actor,verified_at=case when p->>'decision'='VERIFIED' then now() end,feedback=left(coalesce(p->>'feedback',''),500) where id=v.id;
  update verification_uploads set delete_status='DELETION_PENDING' where verification_id=v.id and delete_status<>'DELETED';
  perform yg_notify(v.user_id,case when p->>'decision'='VERIFIED' then 'ACCOUNT_APPROVED' else 'ACCOUNT_REJECTED' end,case when p->>'decision'='VERIFIED' then '가입이 승인됐어요.' else '가입이 승인되지 않았어요. 인증 정보를 확인해주세요.' end,v.id);
  perform yg_log(p_actor,'학생증 인증 처리',v.id);return jsonb_build_object('verificationId',v.id);
 elsif p_action='SUBMIT' then
  if not exists(select 1 from categories where name=p->>'category' and active) or not exists(select 1 from locations where name=p->>'place' and active) then raise exception '종류와 발견 장소를 확인해주세요.';end if;
  if char_length(trim(p->>'name')) not between 1 and 80 or (p->>'date')::date>(now() at time zone 'Asia/Seoul')::date or (p->>'place'='기타' and char_length(trim(p->>'detail'))=0) then raise exception '발견 정보를 확인해주세요.';end if;
  if not exists(select 1 from upload_jobs where object_path=p->>'path' and bucket='item-photos' and owner_id=p_actor and not linked and expires_at>now()) then raise exception '물품 사진을 다시 올려주세요.';end if;
  insert into item_submission_requests(submitter_id,school_year,name,category_id,found_location,place_detail,found_date,color,brand,public_description,photo_path) values(p_actor,y,left(trim(p->>'name'),80),(select id from categories where name=p->>'category'),p->>'place',left(coalesce(p->>'detail',''),150),(p->>'date')::date,left(p->>'color',40),left(p->>'brand',60),left(p->>'description',1000),p->>'path') returning id into obj;
  update upload_jobs set linked=true where object_path=p->>'path';return jsonb_build_object('id',obj);
 elsif p_action in ('RECEIVE','PUBLISH','CLOSE','SUPPLEMENT','EDIT') then
  select * into submission_row from item_submission_requests where id=(p->>'id')::uuid and school_year=y for update;
  if submission_row.id is null or submission_row.resolution is not null then raise exception '처리할 수 없는 등록 요청이에요.';end if;
  if p_action='RECEIVE' then
   if submission_row.status<>'PENDING_DROP_OFF' then raise exception '실물 전달 상태를 확인해주세요.';end if;
   update item_submission_requests set status='PENDING_REVIEW',received_by=p_actor,received_at=now() where id=submission_row.id;
  elsif p_action='SUPPLEMENT' then
   update item_submission_requests set feedback=left(p->>'feedback',500) where id=submission_row.id;
   perform yg_notify(submission_row.submitter_id,'ITEM_MORE_INFO','등록 정보를 보완해주세요.',submission_row.id);
  elsif p_action='EDIT' then
   if char_length(trim(p->>'name')) not between 1 and 80 then raise exception '물품명을 확인해주세요.';end if;
   update item_submission_requests set name=trim(p->>'name'),public_description=left(p->>'description',1000),feedback='' where id=submission_row.id;
  elsif p_action='CLOSE' then
   if coalesce(p->>'decision','') not in ('DUPLICATE','REJECTED') then raise exception '처리 상태 오류';end if;
   update item_submission_requests set resolution=p->>'decision',reviewed_by=p_actor,reviewed_at=now(),feedback=left(p->>'feedback',500) where id=submission_row.id;
   perform yg_notify(submission_row.submitter_id,'ITEM_REJECTED','등록 요청이 종료됐어요. 내 요청에서 확인해주세요.',submission_row.id);
  else
   if submission_row.status<>'PENDING_REVIEW' or submission_row.received_at is null or char_length(trim(p->>'storage')) not between 1 and 20 then raise exception '실물 확인과 보관번호 입력이 필요해요.';end if;
   if p->>'photoChecked' is distinct from 'true' then raise exception '사진의 개인정보 공개 여부를 확인해주세요.';end if;
   insert into items(submission_id,origin_year,current_year,name,category_id,found_location,place_detail,found_date,color,brand,public_description,approved_by) values(submission_row.id,y,y,submission_row.name,submission_row.category_id,submission_row.found_location,submission_row.place_detail,submission_row.found_date,submission_row.color,submission_row.brand,submission_row.public_description,p_actor) returning * into it;
   insert into item_private_details(item_id,storage_number) values(it.id,trim(p->>'storage'));
   insert into item_images(item_id,object_path,is_approved_public) values(it.id,submission_row.photo_path,true);
   update item_submission_requests set resolution='APPROVED',status='STORED',reviewed_by=p_actor,reviewed_at=now() where id=submission_row.id;
   insert into item_history(item_id,school_year,actor_id,event,to_status) values(it.id,y,p_actor,'실물 확인 및 등록 승인','STORED');
   perform yg_notify(submission_row.submitter_id,'ITEM_APPROVED','등록이 승인됐어요.',it.id);
  end if;perform yg_log(p_actor,p_action,submission_row.id);
 elsif p_action='RESUBMIT' then
  update item_submission_requests set public_description=left(p->>'description',1000),feedback='' where id=(p->>'id')::uuid and submitter_id=p_actor and school_year=y and resolution is null;
  if not found then raise exception '수정할 수 없는 요청이에요.';end if;
 elsif p_action='CLAIM' then
  select * into it from items where id=(p->>'itemId')::uuid and current_year=y for update;
  if it.id is null or it.status not in ('STORED','CLAIM_PENDING') then raise exception '지금은 찾아가기 요청을 할 수 없어요.';end if;
  if char_length(trim(p->>'answer')) not between 5 and 1000 then raise exception '특징을 5자 이상 입력해주세요.';end if;
  insert into claim_requests(item_id,claimant_id,school_year,private_answer) values(it.id,p_actor,y,p->>'answer');
  update items set status='CLAIM_PENDING' where id=it.id;
 elsif p_action='ANSWER' then
  if char_length(trim(p->>'answer')) not between 5 and 1000 then raise exception '특징을 5자 이상 입력해주세요.';end if;
  update claim_requests set private_answer=p->>'answer',status='PENDING' where id=(p->>'id')::uuid and claimant_id=p_actor and school_year=y and status='MORE_INFO';
  if not found then raise exception '수정할 수 없는 요청이에요.';end if;
 elsif p_action='DECIDE' then
  select item_id into obj from claim_requests where id=(p->>'id')::uuid;
  select * into it from items where id=obj and current_year=y for update;
  select * into c from claim_requests where id=(p->>'id')::uuid and school_year=y for update;
  if it.id is null or c.status not in ('PENDING','MORE_INFO') or it.status<>'CLAIM_PENDING' then raise exception '이미 처리된 요청이에요.';end if;
  if coalesce(p->>'decision','') not in ('APPROVED','REJECTED','MORE_INFO') then raise exception '처리 상태 오류';end if;
  update claim_requests set status=p->>'decision',feedback=left(coalesce(p->>'feedback',''),500),reviewed_by=p_actor,reviewed_at=now(),pickup_code_hash=case when p->>'decision'='APPROVED' then p->>'codeHash' end,pickup_code_ciphertext=case when p->>'decision'='APPROVED' then p->>'codeEncrypted' end where id=c.id;
  if p->>'decision'='APPROVED' then
   if p->>'codeHash' is null or p->>'codeEncrypted' is null then raise exception '수령번호가 필요해요.';end if;
   update items set status='READY_FOR_PICKUP' where id=it.id;
   for target in select claimant_id from claim_requests where item_id=it.id and id<>c.id and status in ('PENDING','MORE_INFO') loop perform yg_notify(target,'CLAIM_REJECTED','입력한 정보만으로는 확인이 어려워요.',it.id);end loop;
   update claim_requests set status='REJECTED',feedback='다른 수령 요청이 승인됐어요.' where item_id=it.id and id<>c.id and status in ('PENDING','MORE_INFO');
  elsif not exists(select 1 from claim_requests where item_id=it.id and status in ('PENDING','MORE_INFO')) then update items set status='STORED' where id=it.id;
  end if;
  perform yg_notify(c.claimant_id,'CLAIM_'||(p->>'decision'),case p->>'decision' when 'APPROVED' then '확인이 완료됐어요. 받을 시간을 선택해주세요.' when 'MORE_INFO' then '확인을 위해 정보가 조금 더 필요해요.' else '입력한 정보만으로는 확인이 어려워요.' end,it.id);
  perform yg_log(p_actor,'소유 확인 처리',c.id);
 elsif p_action='AVAILABILITY' then
  if not yg_deliverer(p_actor) then raise exception '전달 일정 등록 권한이 없어요.';end if;
  perform pg_advisory_xact_lock(hashtext(p_actor::text));
  start_time:=(p->>'starts')::timestamptz;end_time:=(p->>'ends')::timestamptz;
  if start_time<=now() or end_time<=start_time or end_time-start_time>interval '4 hours' or extract(epoch from start_time)::bigint%600<>0 or extract(epoch from end_time)::bigint%600<>0 then raise exception '미래 시간을 10분 단위로 입력해주세요. 한 번에 최대 4시간이에요.';end if;
  if exists(select 1 from staff_availability where staff_id=p_actor and cancelled_at is null and starts_at<end_time and ends_at>start_time) then raise exception '이미 등록된 시간과 겹쳐요.';end if;
  insert into staff_availability(staff_id,school_year,starts_at,ends_at) values(p_actor,y,start_time,end_time) returning id into obj;
  insert into pickup_slots(availability_id,staff_id,school_year,starts_at,ends_at) select obj,p_actor,y,t,t+interval '10 minutes' from generate_series(start_time,end_time-interval '10 minutes',interval '10 minutes') t;
  perform yg_log(p_actor,'가능 시간 등록',obj);
 elsif p_action='REMOVE_AVAILABILITY' then
  perform pg_advisory_xact_lock(hashtext(p_actor::text));
  perform 1 from pickup_slots where availability_id=(p->>'id')::uuid order by id for update;
  if exists(select 1 from pickup_schedules booking join pickup_slots s on s.id=booking.slot_id where s.availability_id=(p->>'id')::uuid and booking.status='RESERVED') then raise exception '예약된 일정이 있어요. 먼저 예약을 변경해주세요.';end if;
  update staff_availability set cancelled_at=now() where id=(p->>'id')::uuid and staff_id=p_actor;
 elsif p_action='RESERVE' then
  select * into c from claim_requests where id=(p->>'id')::uuid and claimant_id=p_actor and school_year=y for update;
  if c.id is null or c.status<>'APPROVED' or exists(select 1 from pickup_schedules where claim_id=c.id and status in ('RESERVED','COMPLETED')) then raise exception '예약할 수 없는 요청이에요.';end if;
  if coalesce(p->>'place','') not in ('본관 중앙 현관','안전생활부실 앞') then raise exception '수령 장소를 선택해주세요.';end if;
  select s.* into sl from pickup_slots s join staff_availability a on a.id=s.availability_id where s.school_year=y and s.starts_at=(p->>'starts')::timestamptz and s.starts_at>now() and a.cancelled_at is null and yg_deliverer(s.staff_id) and not exists(select 1 from pickup_schedules booking where booking.slot_id=s.id and booking.status in ('RESERVED','COMPLETED')) order by (yg_role(s.staff_id)='WELFARE_MANAGER') desc,s.id for update of s skip locked limit 1;
  if sl.id is null then raise exception '다른 학생이 먼저 예약했어요. 시간을 다시 선택해주세요.';end if;
  insert into pickup_schedules(claim_id,slot_id,pickup_place) values(c.id,sl.id,p->>'place') returning id into obj;
  update items set status='RESERVED' where id=c.item_id;
  perform yg_notify(p_actor,'PICKUP_RESERVED','수령 예약이 확정됐어요.',obj);
  perform yg_notify(sl.staff_id,'PICKUP_ASSIGNED','담당 수령 일정이 배정됐어요.',obj);
  perform yg_log(p_actor,'수령 예약',obj);
 elsif p_action in ('CANCEL','COMPLETE','NO_SHOW') then
  select claim_id into obj from pickup_schedules where id=(p->>'id')::uuid;
  select * into c from claim_requests where id=obj and school_year=y for update;
  select * into rs from pickup_schedules where id=(p->>'id')::uuid for update;
  select * into sl from pickup_slots where id=rs.slot_id for update;
  if c.id is null or rs.id is null or rs.status<>'RESERVED' or c.status<>'APPROVED' then raise exception '이미 처리된 예약이에요.';end if;
  if p_action='CANCEL' then
   if c.claimant_id<>p_actor and not yg_manager(p_actor) then raise exception '예약 변경 권한이 없어요.';end if;
   update pickup_schedules set status='CANCELLED',cancelled_at=now() where id=rs.id;
   update items set status='READY_FOR_PICKUP' where id=c.item_id;
   perform yg_notify(c.claimant_id,'PICKUP_CHANGED','수령 일정이 취소됐어요. 받을 시간을 다시 선택해주세요.',rs.id);
   perform yg_notify(sl.staff_id,'PICKUP_CHANGED','담당 수령 일정이 취소됐어요.',rs.id);
  else
   if sl.staff_id<>p_actor or not yg_deliverer(p_actor) then raise exception '본인에게 배정된 일정만 처리할 수 있어요.';end if;
   if p_action='NO_SHOW' then
    if now()<sl.ends_at then raise exception '예약 시간이 끝난 후 미수령 처리해주세요.';end if;
    update pickup_schedules set status='NO_SHOW',completed_by=p_actor,completed_at=now() where id=rs.id;
    update items set status='READY_FOR_PICKUP' where id=c.item_id;
    perform yg_notify(c.claimant_id,'PICKUP_NO_SHOW','예약 시간에 수령하지 않았어요. 다시 예약해주세요.',rs.id);
   else
    if p->>'codeHash' is distinct from c.pickup_code_hash or p->>'handed' is distinct from 'true' then raise exception '수령번호와 실제 전달 여부를 확인해주세요.';end if;
    update pickup_schedules set status='COMPLETED',completed_by=p_actor,completed_at=now() where id=rs.id;
    update claim_requests set status='RETURNED',pickup_code_hash=null,pickup_code_ciphertext=null,pickup_code_expires_at=null where id=c.id;
    update items set status='RETURNED',returned_at=now() where id=c.item_id;
    update item_private_details set slot_released_at=now() where item_id=c.item_id;
    perform yg_notify(c.claimant_id,'ITEM_RETURNED','수령이 완료됐어요.',c.item_id);
   end if;
  end if;
  insert into item_history(item_id,school_year,actor_id,event,from_status,to_status) values(c.item_id,y,p_actor,p_action,'RESERVED',case when p_action='COMPLETE' then 'RETURNED'::item_status else 'READY_FOR_PICKUP'::item_status end);
  perform yg_log(p_actor,p_action,rs.id);
 elsif p_action='ROLE' then
  if yg_role(p_actor)<>'SUPER_ADMIN' then raise exception '권한 설정 권한이 없어요.';end if;
  target:=(p->>'userId')::uuid;
  if target=p_actor or not yg_verified(target) then raise exception '다른 재학생 인증 계정을 선택해주세요.';end if;
  if coalesce(p->>'role','') not in ('STUDENT','COUNCIL_MEMBER','WELFARE_MANAGER','PRESIDENT_TEAM','SUPER_ADMIN') then raise exception '역할을 확인해주세요.';end if;
  if exists(select 1 from pickup_schedules booking join pickup_slots s on s.id=booking.slot_id where s.staff_id=target and booking.status='RESERVED') then raise exception '배정된 예약을 먼저 변경해주세요.';end if;
  update council_roles set revoked_at=now() where user_id=target and school_year=y and revoked_at is null;
  if p->>'role'<>'STUDENT' then insert into council_roles(user_id,school_year,role,can_deliver,is_head,starts_at,ends_at,granted_by) values(target,y,(p->>'role')::app_role,coalesce((p->>'deliver')::boolean,false),p->>'role'='WELFARE_MANAGER' and coalesce((p->>'head')::boolean,false),now(),(select (ends_on+1)::timestamp at time zone 'Asia/Seoul' from school_years where year=y),p_actor);end if;
  perform yg_log(p_actor,'임원 권한 변경',target);
 elsif p_action='YEAR' then
  if yg_role(p_actor)<>'SUPER_ADMIN' then raise exception '학년도 전환 권한이 없어요.';end if;
  newyear:=(p->>'year')::integer;
  if newyear<>y+1 then raise exception '다음 학년도를 확인해주세요.';end if;
  if exists(select 1 from claim_requests where school_year=y and status in ('PENDING','MORE_INFO','APPROVED')) or exists(select 1 from item_submission_requests where school_year=y and resolution is null) then raise exception '진행 중인 등록·수령 요청을 먼저 마무리해주세요.';end if;
  insert into school_years(year,starts_on,ends_on) values(newyear,make_date(newyear,3,1),make_date(newyear+1,3,1)-1);
  insert into year_transfers(item_id,from_year,to_year,actor_id) select id,y,newyear,p_actor from items where current_year=y and status<>'RETURNED';
  insert into item_history(item_id,school_year,actor_id,event) select id,newyear,p_actor,'미수령 물품 인계' from items where current_year=y and status<>'RETURNED';
  update items set current_year=newyear where current_year=y and status<>'RETURNED';
  update council_roles set revoked_at=now() where school_year=y and revoked_at is null;
  update app_sessions set expires_at=now();
  perform yg_log(p_actor,'학년도 전환',null);
  update school_years set is_current=false where year=y;
  update school_years set is_current=true where year=newyear;
 else raise exception '지원하지 않는 요청이에요.';
 end if;
 return '{}'::jsonb;
end$$;
-- No custom-auth function is callable by a browser/public JWT.
do $$declare f record;begin
 for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'yg_%' loop
 execute format('revoke all on function %s from public,anon,authenticated',f.sig);
 execute format('grant execute on function %s to service_role',f.sig);
 end loop;
end$$;
commit;
