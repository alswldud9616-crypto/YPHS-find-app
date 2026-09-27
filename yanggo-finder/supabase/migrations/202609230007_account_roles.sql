begin;
create table public.admin_allowlist(
 id uuid primary key default gen_random_uuid(),student_name text not null check(char_length(trim(student_name)) between 2 and 40),
 student_number text not null check(student_number ~ '^[0-9]{5}$'),target_role app_role not null check(target_role in ('COUNCIL_MEMBER','WELFARE_MANAGER','PRESIDENT_TEAM')),
 school_year integer not null references school_years,claimed_user_id uuid references users,activated_at timestamptz,is_active boolean not null default true,
 is_head boolean not null default false,can_deliver boolean not null default true,created_by uuid references users,created_at timestamptz not null default now(),
 check(not is_head or target_role='WELFARE_MANAGER'),check((claimed_user_id is null)=(activated_at is null))
);
create unique index admin_candidate_identity on admin_allowlist(school_year,student_number) where is_active;
alter table admin_allowlist enable row level security;
revoke all on admin_allowlist from public,anon,authenticated;
grant all on admin_allowlist to service_role;
alter table audit_logs add column details jsonb not null default '{}';
alter table items add column found_time time;

create function yg_admin_access(a uuid) returns boolean language sql stable set search_path=public as $$select yg_verified(a) and yg_role(a)<>'STUDENT'$$;
create function yg_role_scope(a uuid,prior_role text,new_role text) returns boolean language sql stable set search_path=public as $$
 select case yg_role(a)
 when 'SUPER_ADMIN' then prior_role<>'SUPER_ADMIN' and new_role in ('STUDENT','COUNCIL_MEMBER','WELFARE_MANAGER','PRESIDENT_TEAM')
 when 'PRESIDENT_TEAM' then prior_role in ('STUDENT','COUNCIL_MEMBER','WELFARE_MANAGER') and new_role in ('STUDENT','COUNCIL_MEMBER','WELFARE_MANAGER')
 when 'WELFARE_MANAGER' then prior_role in ('STUDENT','COUNCIL_MEMBER') and new_role in ('STUDENT','COUNCIL_MEMBER') else false end
$$;
-- Called only after authorization; immutable role rows preserve previous terms.
create function yg_apply_role(a uuid,t uuid,r text,h boolean,d boolean,reason text) returns void language plpgsql set search_path=public as $$declare old text;begin
 old:=yg_role(t);
 update council_roles set revoked_at=now() where user_id=t and school_year=yg_year() and revoked_at is null;
 if r<>'STUDENT' then insert into council_roles(user_id,school_year,role,is_head,can_deliver,starts_at,ends_at,granted_by)
 values(t,yg_year(),r::app_role,h,d,now(),make_date(yg_year()+1,3,1)::timestamp at time zone 'Asia/Seoul',a);end if;
 insert into audit_logs(actor_id,school_year,action,entity_type,entity_id,request_id,details)
 values(a,yg_year(),reason,'council_role',t,gen_random_uuid(),jsonb_build_object('from',old,'to',r,'head',h,'deliver',d));
 perform yg_notify(t,'ROLE_CHANGED',case when r='STUDENT' then '관리 권한이 해제됐어요. 학생 기능은 계속 이용할 수 있어요.' else '관리 권한이 추가되거나 변경됐어요.' end,t);
end$$;

-- Do not activate on name/number alone, or on a manual VERIFIED row without a photo.
create function yg_claim_admin_candidate() returns trigger language plpgsql set search_path=public as $$declare c admin_allowlist;begin
 if new.status<>'VERIFIED' or old.status<>'ACCOUNT_PENDING' or new.school_year<>yg_year() then return new;end if;
 if new.reviewed_by is null or new.verified_at is null or not exists(select 1 from verification_uploads where verification_id=new.id and object_path is not null and delete_status='PENDING' and expires_at>now()) then return new;end if;
 perform pg_advisory_xact_lock(7201,new.school_year);
 select al.* into c from admin_allowlist al join users u on u.id=new.user_id
 where al.student_name=u.display_name and al.student_number=new.student_number and al.school_year=new.school_year and al.is_active and al.claimed_user_id is null for update of al;
 if c.id is not null and yg_role(new.user_id)='STUDENT' then
  perform yg_apply_role(new.reviewed_by,new.user_id,c.target_role::text,c.is_head,c.can_deliver,'학생증 승인 후 관리자 후보 활성화');
  update admin_allowlist set claimed_user_id=new.user_id,activated_at=now() where id=c.id;
 end if;return new;
end$$;
create trigger activate_admin_candidate after update of status on student_verifications for each row execute function yg_claim_admin_candidate();

alter function yg_action(uuid,text,jsonb) rename to yg_action_v2;
create function yg_action(p_actor uuid,p_action text,p jsonb) returns jsonb language plpgsql set search_path=public as $$
declare y integer:=yg_year();t uuid;r text;old text;h boolean;d boolean;c admin_allowlist;result jsonb;sid uuid;begin
 if p_action in ('VERIFY','ROLE','ALLOWLIST_ADD','ALLOWLIST_DISABLE','YEAR','LOCATION_SET') then perform pg_advisory_xact_lock(7201,y);end if;
 if not yg_verified(p_actor) and p_action<>'READ' then raise exception '현재 학년도 재학생 인증이 필요해요.';end if;
 if p_action='ROLE' then
  t:=(p->>'userId')::uuid;r:=p->>'role';h:=coalesce((p->>'head')::boolean,false);d:=coalesce((p->>'deliver')::boolean,false);
  if t is null or t=p_actor or not yg_verified(t) or r is null then raise exception '현재 학년도 인증을 마친 다른 학생을 선택해주세요.';end if;
  old:=yg_role(t);
  if not yg_role_scope(p_actor,old,r) then raise exception '이 역할을 부여하거나 해제할 권한이 없어요.';end if;
  if h and r<>'WELFARE_MANAGER' then raise exception '부장 권한은 학생복지부에만 지정할 수 있어요.';end if;
  if exists(select 1 from pickup_schedules ps join pickup_slots sl on sl.id=ps.slot_id where sl.staff_id=t and ps.status='RESERVED') then raise exception '배정된 수령 일정을 먼저 마무리하거나 취소해주세요.';end if;
  perform yg_apply_role(p_actor,t,r,h,case when r='STUDENT' then false else d end,'관리자 역할 변경');
  -- Revocation/change must not be undone by an old unclaimed candidate.
  update admin_allowlist set is_active=false where school_year=y and is_active and (claimed_user_id=t or student_number=(select student_number from student_verifications where user_id=t and school_year=y and status='VERIFIED'));
  return '{}'::jsonb;
 elsif p_action='ALLOWLIST_ADD' then
  r:=p->>'role';h:=coalesce((p->>'head')::boolean,false);d:=coalesce((p->>'deliver')::boolean,true);
  if not yg_role_scope(p_actor,'STUDENT',r) or r='STUDENT' or (h and r<>'WELFARE_MANAGER') then raise exception '관리자 후보 등록 권한이 없어요.';end if;
  if exists(select 1 from student_verifications where student_number=p->>'number' and school_year=y and status='VERIFIED') then raise exception '이미 인증된 학생은 계정 목록에서 권한을 지정해주세요.';end if;
  insert into admin_allowlist(student_name,student_number,target_role,school_year,is_head,can_deliver,created_by) values(trim(p->>'name'),p->>'number',r::app_role,y,h,d,p_actor) returning id into t;
  perform yg_log(p_actor,'관리자 후보 사전 등록',t);return '{}'::jsonb;
 elsif p_action='ALLOWLIST_DISABLE' then
  select * into c from admin_allowlist where id=(p->>'id')::uuid and school_year=y for update;
  if c.id is null or not yg_role_scope(p_actor,'STUDENT',c.target_role::text) then raise exception '관리자 후보 변경 권한이 없어요.';end if;
  if c.claimed_user_id is not null then raise exception '활성화된 권한은 계정 목록에서 해제해주세요.';end if;
  update admin_allowlist set is_active=false where id=c.id;perform yg_log(p_actor,'관리자 후보 취소',c.id);return '{}'::jsonb;
 elsif p_action='DIRECT_REGISTER' then
  if not yg_manager(p_actor) then raise exception '분실물 직접 등록 권한이 없어요.';end if;
  if p->>'received' is distinct from 'true' or p->>'photoChecked' is distinct from 'true' then raise exception '실물과 공개 사진을 확인해주세요.';end if;
  if coalesce(trim(p->>'name'),'')='' or coalesce(p->>'date','')='' or (p->>'place'='기타' and coalesce(trim(p->>'detail'),'')='') then raise exception '필수 발견 정보를 입력해주세요.';end if;
  result:=yg_action_v2(p_actor,'SUBMIT',p);sid:=(result->>'id')::uuid;
  update item_submission_requests set found_time=nullif(p->>'time','')::time where id=sid;
  perform yg_action_v2(p_actor,'RECEIVE',jsonb_build_object('id',sid));
  perform yg_action_v2(p_actor,'PUBLISH',jsonb_build_object('id',sid,'storage',p->>'storage','photoChecked',true));
  update items set found_time=nullif(p->>'time','')::time where submission_id=sid returning id into t;
  perform yg_log(p_actor,'분실물 직접 등록',t);return jsonb_build_object('itemId',t);
 elsif p_action='LOCATION_SET' then
  if yg_role(p_actor) not in ('PRESIDENT_TEAM','SUPER_ADMIN') then raise exception '장소 설정 권한이 없어요.';end if;
  if p->>'name' not in ('본관 1층','본관 2층','본관 3층','별관 1층','별관 2층','급식실','기숙사','운동장','야외 농구장','체육관','E센터 1층','E센터 2층','E센터 3층','도서관','대극장','자판기 주변') or p->>'active' is null then raise exception '지정된 학교 장소만 설정할 수 있어요. 기타는 항상 유지해요.';end if;
  update locations set active=(p->>'active')::boolean where name=p->>'name' returning id into t;
  perform yg_log(p_actor,'장소 선택 설정 변경',t);return '{}'::jsonb;
 end if;
 result:=yg_action_v2(p_actor,p_action,p);
 if p_action='YEAR' then update admin_allowlist set is_active=false where school_year=y and is_active;end if;
 return result;
end$$;

alter function yg_state(uuid,integer) rename to yg_state_v2;
create function yg_state(p_actor uuid,p_year integer default null) returns jsonb language plpgsql set search_path=public as $$declare result jsonb;y integer:=yg_year();begin
 result:=yg_state_v2(p_actor,p_year);
 result:=result||jsonb_build_object('canManage',yg_admin_access(p_actor),'canManageRoles',yg_manager(p_actor),'roleOptions',case yg_role(p_actor) when 'SUPER_ADMIN' then '["COUNCIL_MEMBER","WELFARE_MANAGER","PRESIDENT_TEAM"]'::jsonb when 'PRESIDENT_TEAM' then '["COUNCIL_MEMBER","WELFARE_MANAGER"]'::jsonb when 'WELFARE_MANAGER' then '["COUNCIL_MEMBER"]'::jsonb else '[]'::jsonb end);
 if not yg_verified(p_actor) then return result;end if;
 result:=result||jsonb_build_object('places',coalesce((select jsonb_agg(name order by name) from locations where active),'[]'::jsonb));
 if yg_manager(p_actor) then
  result:=result||jsonb_build_object('members',coalesce((select jsonb_agg(jsonb_build_object('id',u.id,'name',u.display_name,'number',sv.student_number,'role',yg_role(u.id),'head',coalesce(cr.is_head,false),'deliver',coalesce(cr.can_deliver,false))) from users u join student_verifications sv on sv.user_id=u.id and sv.school_year=y and sv.status='VERIFIED' left join council_roles cr on cr.user_id=u.id and cr.school_year=y and cr.revoked_at is null and cr.starts_at<=now() and cr.ends_at>now() where u.id<>p_actor and yg_role_scope(p_actor,yg_role(u.id),'STUDENT')),'[]'::jsonb),
  'candidates',coalesce((select jsonb_agg(jsonb_build_object('id',al.id,'name',al.student_name,'number',al.student_number,'role',al.target_role,'head',al.is_head,'year',al.school_year,'active',al.is_active,'claimed',al.claimed_user_id is not null,'activatedAt',al.activated_at) order by al.created_at desc) from admin_allowlist al where al.school_year=coalesce(p_year,y) and yg_role_scope(p_actor,'STUDENT',al.target_role::text)),'[]'::jsonb),
  'roleHistory',coalesce((select jsonb_agg(jsonb_build_object('id',cr.id,'name',u.display_name,'role',cr.role,'head',cr.is_head,'starts',cr.starts_at,'ends',cr.ends_at,'revoked',cr.revoked_at) order by cr.starts_at desc) from council_roles cr join users u on u.id=cr.user_id where cr.school_year=coalesce(p_year,y) and yg_role_scope(p_actor,cr.role::text,'STUDENT')),'[]'::jsonb));
 end if;
 if yg_role(p_actor) in ('PRESIDENT_TEAM','SUPER_ADMIN') then
  result:=result||jsonb_build_object('locationSettings',coalesce((select jsonb_agg(jsonb_build_object('name',name,'active',active) order by name) from locations where name in ('본관 1층','본관 2층','본관 3층','별관 1층','별관 2층','급식실','기숙사','운동장','야외 농구장','체육관','E센터 1층','E센터 2층','E센터 3층','도서관','대극장','자판기 주변','기타')),'[]'::jsonb));
 end if;
 result:=jsonb_set(result,'{items}',coalesce((select jsonb_agg(e.value||jsonb_build_object('time',i.found_time) order by e.idx) from jsonb_array_elements(coalesce(result->'items','[]')) with ordinality e(value,idx) join items i on i.id=(e.value->>'id')::uuid),'[]'));
 return result;
end$$;

-- Initialize an empty school year before common signup. No account is created.
create function yg_initialize_year(p_year integer) returns void language plpgsql set search_path=public as $$begin
 perform pg_advisory_xact_lock(7201,p_year);
 if yg_year() is not null then raise exception '이미 학년도가 설정되어 있어요.';end if;
 insert into school_years values(p_year,make_date(p_year,3,1),make_date(p_year+1,3,1)-1,true);
end$$;
-- Retire the old bootstrap path that minted separate pre-approved accounts.
drop function yg_operator_bootstrap(text,text,text,integer,text,boolean,uuid);
create function yg_bootstrap_super(p_user uuid,p_identity_reviewed boolean) returns void language plpgsql set search_path=public as $$declare v student_verifications;begin
 perform pg_advisory_xact_lock(7201,yg_year());
 if p_identity_reviewed is distinct from true or exists(select 1 from council_roles where school_year=yg_year() and role='SUPER_ADMIN' and revoked_at is null) then raise exception '최초 관리자 설정 조건을 확인해주세요.';end if;
 select * into v from student_verifications where user_id=p_user and school_year=yg_year() and status in ('ACCOUNT_PENDING','VERIFIED') order by created_at desc limit 1 for update;
 if v.id is null or not exists(select 1 from verification_uploads where verification_id=v.id and object_path is not null) then raise exception '공통 가입 화면에서 학생증을 제출한 계정이 필요해요.';end if;
 if v.status='ACCOUNT_PENDING' then
  if not exists(select 1 from verification_uploads where verification_id=v.id and delete_status='PENDING' and expires_at>now()) then raise exception '사진을 다시 제출해주세요.';end if;
  -- Bootstrap is the sole documented out-of-band identity check exception.
  update student_verifications set status='VERIFIED',verified_at=now(),reviewed_by=p_user,feedback='최초 운영: 학교 담당자 대면 신원 확인' where id=v.id;
 end if;
 perform yg_apply_role(p_user,p_user,'SUPER_ADMIN',false,false,'서버에서 최초 SUPER_ADMIN 활성화');
 update verification_uploads set delete_status='DELETION_PENDING' where verification_id=v.id and delete_status<>'DELETED';
end$$;
create function yg_bootstrap_first_verifier(p_super uuid,p_verification uuid,p_identity_reviewed boolean) returns void language plpgsql set search_path=public as $$declare v student_verifications;begin
 perform pg_advisory_xact_lock(7201,yg_year());
 if p_identity_reviewed is distinct from true or yg_role(p_super)<>'SUPER_ADMIN' or exists(select 1 from users where yg_verifier(id)) then raise exception '최초 인증 담당자 설정 조건을 확인해주세요.';end if;
 select * into v from student_verifications where id=p_verification and school_year=yg_year() and status='ACCOUNT_PENDING' for update;
 if v.id is null or not exists(select 1 from verification_uploads where verification_id=v.id and delete_status='PENDING' and expires_at>now()) then raise exception '유효한 학생증 제출이 필요해요.';end if;
 if not exists(select 1 from admin_allowlist al join users u on u.id=v.user_id where al.school_year=v.school_year and al.student_number=v.student_number and al.student_name=u.display_name and al.is_active and al.claimed_user_id is null and (al.target_role='PRESIDENT_TEAM' or (al.target_role='WELFARE_MANAGER' and al.is_head))) then raise exception '부장 또는 회장단 후보와 일치해야 해요.';end if;
 update student_verifications set status='VERIFIED',verified_at=now(),reviewed_by=p_super,feedback='최초 운영: 학교 담당자 대면 신원 확인' where id=v.id;
 update verification_uploads set delete_status='DELETION_PENDING' where verification_id=v.id and delete_status<>'DELETED';
 perform yg_log(p_super,'서버에서 최초 학생증 인증 담당자 승인',v.user_id);
end$$;
-- SUPER_ADMIN grants/revocations are intentionally unavailable to the web UI.
create function yg_operator_super_role(p_actor uuid,p_target uuid,p_grant boolean) returns void language plpgsql set search_path=public as $$begin
 perform pg_advisory_xact_lock(7201,yg_year());
 if yg_role(p_actor)<>'SUPER_ADMIN' or not yg_verified(p_target) or p_target=p_actor then raise exception '최고 관리자와 인증된 다른 학생 계정이 필요해요.';end if;
 if exists(select 1 from pickup_schedules ps join pickup_slots sl on sl.id=ps.slot_id where sl.staff_id=p_target and ps.status='RESERVED') then raise exception '배정된 수령 일정을 먼저 마무리해주세요.';end if;
 perform yg_apply_role(p_actor,p_target,case when p_grant then 'SUPER_ADMIN' else 'STUDENT' end,false,false,'서버에서 SUPER_ADMIN 권한 변경');
end$$;
do $$declare f record;begin
 for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'yg_%' loop
 execute format('revoke all on function %s from public,anon,authenticated',f.sig);execute format('grant execute on function %s to service_role',f.sig);
 end loop;
end$$;
commit;
