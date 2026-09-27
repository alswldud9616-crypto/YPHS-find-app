-- 양고 찾기: FRESH Supabase project only. Generated; edit ordered migrations instead.
-- Run once in Supabase SQL Editor as the project database operator.
-- Requires Supabase-managed auth/storage schemas and built-in roles.
-- Do NOT run on a project already containing Yanggo tables.
-- Applies all migrations atomically. No fake users/items/admin candidates are inserted.
begin;
do $$begin if to_regclass('public.users') is not null then raise exception 'Existing users table found. Apply only pending ordered migrations; do not run this fresh-install bundle.';end if;end$$;
-- SOURCE 202609170001_initial_schema.sql
-- SHA256 5d35f1f717eff404be2b802751497b072cca8de0812a00d65a02d62358659348
-- Phase 0 schema baseline, NOT the finished production backend.
-- All app tables are closed to anon/authenticated until Phase 2 policies exist.
-- Apply only to a new development Supabase project after review.
begin;
create type public.item_status as enum ('PENDING_DROP_OFF','PENDING_REVIEW','STORED','CLAIM_PENDING','READY_FOR_PICKUP','RESERVED','RETURNED');
create type public.app_role as enum ('STUDENT','COUNCIL_MEMBER','WELFARE_MANAGER','PRESIDENT_TEAM','SUPER_ADMIN');
create table public.school_years(year integer primary key check(year between 2026 and 2200),starts_on date not null,ends_on date not null,is_current boolean not null default false,check(ends_on>starts_on));
create unique index one_current_school_year on public.school_years(is_current) where is_current;
create table public.users(id uuid primary key references auth.users(id),display_name text not null,created_at timestamptz not null default now());
create table public.student_verifications(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.users,school_year integer not null references public.school_years,student_number text not null check(student_number ~ '^[0-9]{5}$'),status text not null default 'ACCOUNT_PENDING' check(status in ('ACCOUNT_PENDING','VERIFIED','REJECTED','EXPIRED')),verified_at timestamptz,reviewed_by uuid references public.users,created_at timestamptz not null default now());
create unique index verified_student_number on public.student_verifications(school_year,student_number) where status='VERIFIED';
create unique index one_verified_identity on public.student_verifications(user_id,school_year) where status='VERIFIED';
create unique index one_pending_verification on public.student_verifications(user_id,school_year) where status='ACCOUNT_PENDING';
create table public.verification_uploads(id uuid primary key default gen_random_uuid(),verification_id uuid not null references public.student_verifications,object_path text unique,expires_at timestamptz not null,delete_status text not null default 'PENDING' check(delete_status in ('PENDING','DELETION_PENDING','DELETED')),deleted_at timestamptz,retry_count integer not null default 0);
create table public.council_roles(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.users,school_year integer not null references public.school_years,role public.app_role not null,can_deliver boolean not null default false,starts_at timestamptz not null,ends_at timestamptz not null,revoked_at timestamptz,granted_by uuid not null references public.users,check(ends_at>starts_at));
create table public.categories(id uuid primary key default gen_random_uuid(),name text not null unique);
create table public.locations(id uuid primary key default gen_random_uuid(),name text not null unique);
create table public.item_submission_requests(id uuid primary key default gen_random_uuid(),submitter_id uuid not null references public.users,school_year integer not null references public.school_years,name text not null,category_id uuid not null references public.categories,found_location text not null,found_date date not null,found_time time,color text,brand text,public_description text,private_notes text,photo_path text not null,status public.item_status not null default 'PENDING_DROP_OFF',resolution text check(resolution in ('APPROVED','DUPLICATE','REJECTED','CANCELLED')),received_by uuid references public.users,received_at timestamptz,reviewed_by uuid references public.users,reviewed_at timestamptz,created_at timestamptz not null default now(),check(status in ('PENDING_DROP_OFF','PENDING_REVIEW','STORED')));
create table public.items(id uuid primary key default gen_random_uuid(),submission_id uuid not null unique references public.item_submission_requests,origin_year integer not null references public.school_years,current_year integer not null references public.school_years,name text not null,category_id uuid not null references public.categories,location_id uuid references public.locations,found_location text not null,found_date date not null,color text,brand text,public_description text,status public.item_status not null default 'STORED',approved_by uuid not null references public.users,approved_at timestamptz not null default now(),returned_at timestamptz,created_at timestamptz not null default now(),check(status not in ('PENDING_DROP_OFF','PENDING_REVIEW')));
create table public.item_private_details(item_id uuid primary key references public.items,storage_number text not null,storage_location text not null default '본관 중앙 현관 분실물함',identity_notes text,slot_released_at timestamptz);
create unique index occupied_storage_number on public.item_private_details(storage_number) where slot_released_at is null;
create table public.item_images(id uuid primary key default gen_random_uuid(),item_id uuid not null references public.items,object_path text not null unique,is_approved_public boolean not null default false,created_at timestamptz not null default now());
create table public.item_history(id uuid primary key default gen_random_uuid(),item_id uuid not null references public.items,school_year integer not null references public.school_years,actor_id uuid not null references public.users,event text not null,from_status public.item_status,to_status public.item_status,created_at timestamptz not null default now());
create table public.claim_requests(id uuid primary key default gen_random_uuid(),item_id uuid not null references public.items,claimant_id uuid not null references public.users,school_year integer not null references public.school_years,private_answer text not null,status text not null default 'PENDING' check(status in ('PENDING','MORE_INFO','APPROVED','REJECTED','WITHDRAWN','EXPIRED','RETURNED')),reviewed_by uuid references public.users,reviewed_at timestamptz,pickup_code_hash text,pickup_code_ciphertext text,pickup_code_expires_at timestamptz,created_at timestamptz not null default now());
create unique index one_approved_claim_per_item on public.claim_requests(item_id) where status='APPROVED';
create unique index one_open_claim_per_student on public.claim_requests(item_id,claimant_id) where status in ('PENDING','MORE_INFO','APPROVED');
create table public.staff_availability(id uuid primary key default gen_random_uuid(),staff_id uuid not null references public.users,school_year integer not null references public.school_years,starts_at timestamptz not null,ends_at timestamptz not null,cancelled_at timestamptz,check(ends_at>starts_at));
create table public.pickup_slots(id uuid primary key default gen_random_uuid(),availability_id uuid not null references public.staff_availability,staff_id uuid not null references public.users,school_year integer not null references public.school_years,starts_at timestamptz not null,ends_at timestamptz not null,unique(staff_id,starts_at),check(ends_at=starts_at+interval '10 minutes'));
create table public.pickup_schedules(id uuid primary key default gen_random_uuid(),claim_id uuid not null references public.claim_requests,slot_id uuid not null references public.pickup_slots,status text not null default 'RESERVED' check(status in ('RESERVED','CANCELLED','NO_SHOW','COMPLETED')),completed_by uuid references public.users,completed_at timestamptz,cancelled_at timestamptz,created_at timestamptz not null default now());
create unique index one_active_slot_reservation on public.pickup_schedules(slot_id) where status in ('RESERVED','COMPLETED');
create unique index one_active_claim_reservation on public.pickup_schedules(claim_id) where status in ('RESERVED','COMPLETED');
create table public.notifications(id uuid primary key default gen_random_uuid(),recipient_id uuid not null references public.users,school_year integer not null references public.school_years,type text not null,message text not null,reference_id uuid,read_at timestamptz,created_at timestamptz not null default now());
create index notifications_recipient on public.notifications(recipient_id,created_at desc);
create table public.audit_logs(id uuid primary key default gen_random_uuid(),actor_id uuid not null references public.users,school_year integer not null references public.school_years,action text not null,entity_type text not null,entity_id uuid,request_id uuid not null unique,created_at timestamptz not null default now());
create table public.year_transfers(id uuid primary key default gen_random_uuid(),item_id uuid not null references public.items,from_year integer not null references public.school_years,to_year integer not null references public.school_years,actor_id uuid not null references public.users,created_at timestamptz not null default now(),unique(item_id,from_year,to_year),check(to_year>from_year));
create table public.notification_outbox(id uuid primary key default gen_random_uuid(),notification_id uuid not null unique references public.notifications,delivered_at timestamptz,attempts integer not null default 0,next_attempt_at timestamptz not null default now());
-- RLS is deliberately closed. No operational policies or grants yet.
do $$
declare t text;
begin
 foreach t in array array['school_years','users','student_verifications','verification_uploads','council_roles','categories','locations','item_submission_requests','items','item_private_details','item_images','item_history','claim_requests','staff_availability','pickup_slots','pickup_schedules','notifications','audit_logs','year_transfers','notification_outbox'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on table public.%I from anon, authenticated',t);
 end loop;
end $$;
commit;
-- Phase 2 must add tested SELECT policies, server-only transition functions,
-- role bootstrap, private Storage buckets, image cleanup jobs, outbox workers,
-- availability overlap constraints, cross-year validation and atomic RPCs.


-- SOURCE 202609220002_operations_schema.sql
-- SHA256 e7d2437150fa018105498576820e4cf7ca249dd73e744b8062516478c777f72d
-- Extend the original schema in place. Existing records are retained.
alter table public.users drop constraint users_id_fkey;
alter table public.users alter column id set default gen_random_uuid();
create table public.pin_credentials(user_id uuid primary key references public.users,pin_hash text not null);
create table public.app_sessions(token_hash text primary key,user_id uuid not null references public.users,expires_at timestamptz not null);
create table public.login_limits(key text primary key,attempts integer not null,window_start timestamptz not null);
create table public.upload_jobs(id uuid primary key default gen_random_uuid(),bucket text not null,object_path text not null unique,owner_id uuid references public.users,linked boolean not null default false,expires_at timestamptz not null default now()+interval '1 hour');
alter table public.council_roles add column is_head boolean not null default false;
alter table public.council_roles add constraint head_is_welfare check(not is_head or role='WELFARE_MANAGER');
alter table public.item_submission_requests add column place_detail text not null default '';
alter table public.item_submission_requests add column feedback text not null default '';
alter table public.items add column place_detail text not null default '';
alter table public.claim_requests add column feedback text not null default '';
alter table public.pickup_schedules add column pickup_place text not null default '본관 중앙 현관' check(pickup_place in ('본관 중앙 현관','안전생활부실 앞'));
alter table public.pickup_schedules add column reminded_at timestamptz;
alter table public.student_verifications add column feedback text not null default '';
alter table public.categories add column active boolean not null default true;
alter table public.locations add column active boolean not null default true;
update public.categories set active=false where name not in ('전자기기','지갑·카드','학용품','의류','액세서리','우산','물병·텀블러','책·교재','열쇠','기타');
insert into public.categories(name) select unnest(array['전자기기','지갑·카드','학용품','의류','액세서리','우산','물병·텀블러','책·교재','열쇠','기타']) on conflict(name) do update set active=true;
update public.locations set active=false where name not in ('본관 1층','본관 2층','본관 3층','별관 1층','별관 2층','급식실','기숙사','운동장','야외 농구장','체육관','E센터 1층','E센터 2층','E센터 3층','도서관','대극장','자판기 주변','기타');
insert into public.locations(name) select unnest(array['본관 1층','본관 2층','본관 3층','별관 1층','별관 2층','급식실','기숙사','운동장','야외 농구장','체육관','E센터 1층','E센터 2층','E센터 3층','도서관','대극장','자판기 주변','기타']) on conflict(name) do update set active=true;
-- Preserve old free-text locations as explicit Other details, never add defaults.
update public.item_submission_requests set place_detail=concat_ws(' · ',found_location,nullif(place_detail,'')),found_location='기타' where found_location not in(select name from public.locations where active);
update public.items set place_detail=concat_ws(' · ',found_location,nullif(place_detail,'')),found_location='기타' where found_location not in(select name from public.locations where active);
update public.item_submission_requests set category_id=(select id from public.categories where name='기타') where category_id in(select id from public.categories where not active);
update public.items set category_id=(select id from public.categories where name='기타') where category_id in(select id from public.categories where not active);
-- Names/numbers remain year-specific, never permanent user IDs.
create unique index one_active_number_per_year on public.student_verifications(school_year,student_number) where status in ('ACCOUNT_PENDING','VERIFIED');
create unique index one_current_role_per_user on public.council_roles(user_id,school_year) where revoked_at is null;
create unique index one_awaiting_upload on public.verification_uploads(verification_id) where delete_status<>'DELETED';
create index claim_owner on public.claim_requests(claimant_id,school_year);
create index item_current on public.items(current_year,approved_at desc);
create index assigned_slot on public.pickup_slots(staff_id,starts_at);
-- The browser uses opaque custom sessions, not a Supabase JWT. Direct DB access
-- is DENIED. Server-only functions authenticate the actor and scope every read.
do $$ declare t text; begin
 foreach t in array array['pin_credentials','app_sessions','login_limits','upload_jobs'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 end loop;
end $$;
grant usage on schema public to service_role;
grant all on all tables in schema public to service_role;

-- SOURCE 202609220003_operations.sql
-- SHA256 18dc51a8d2d70bef228b1bbe9bf8969b2d1062556d115219608d18ce57fb70a7
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

-- SOURCE 202609220004_reads.sql
-- SHA256 a225b5b06b7096e61c8c51bfaee6c016d0d0b5f0ec880673afa11f9c36a3353d
create function public.yg_state(p_actor uuid,p_year integer default null) returns jsonb language plpgsql set search_path=public as $$
declare y integer:=yg_year();yr integer;v boolean:=yg_verified(p_actor);m boolean:=yg_manager(p_actor);result jsonb;
begin
 yr:=coalesce(p_year,y);if yr<>y and not m then raise exception '이전 학년도 조회 권한이 없어요.';end if;
 result:=jsonb_build_object('year',y,'role',yg_role(p_actor),'verified',v,'canVerify',yg_verifier(p_actor),'canDeliver',yg_deliverer(p_actor),'years',coalesce((select jsonb_agg(year order by year desc) from school_years where year=y or m),'[]'::jsonb),'user',(select jsonb_build_object('id',u.id,'name',u.display_name,'number',coalesce((select student_number from student_verifications where user_id=u.id order by school_year desc,created_at desc limit 1),''),'verification',coalesce((select status from student_verifications where user_id=u.id and school_year=y order by created_at desc limit 1),'REVERIFY')) from users u where u.id=p_actor));
 if not v then return result;end if;
 result:=result||jsonb_build_object(
 'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'name',i.name,'category',k.name,'place',i.found_location,'detail',i.place_detail,'date',i.found_date,'color',i.color,'brand',i.brand,'description',i.public_description,'status',i.status,'year',i.current_year,'originYear',i.origin_year,'approvedAt',i.approved_at,'longOverdue',i.approved_at<=now()-interval '14 days' and i.status in ('STORED','CLAIM_PENDING'),'photo','/api/image?kind=item&id='||i.id,'storage','본관 중앙 현관 분실물함') order by i.approved_at desc) from items i join categories k on k.id=i.category_id where i.current_year=yr or (m and (i.origin_year=yr or exists(select 1 from year_transfers t where t.item_id=i.id and t.from_year=yr)))),'[]'::jsonb),
 'submissions',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'name',r.name,'category',k.name,'place',r.found_location,'detail',r.place_detail,'date',r.found_date,'description',r.public_description,'status',r.status,'resolution',r.resolution,'feedback',r.feedback,'photo','/api/image?kind=submission&id='||r.id,'student',u.display_name,'mine',r.submitter_id=p_actor) order by r.created_at desc) from item_submission_requests r join categories k on k.id=r.category_id join users u on u.id=r.submitter_id where r.school_year=yr and (r.submitter_id=p_actor or m)),'[]'::jsonb),
 'claims',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'itemId',c.item_id,'name',i.name,'student',u.display_name,'answer',c.private_answer,'status',c.status,'feedback',c.feedback,'codeEncrypted',case when c.claimant_id=p_actor then c.pickup_code_ciphertext end,'mine',c.claimant_id=p_actor,'reservation',(select jsonb_build_object('id',r.id,'starts',s.starts_at,'ends',s.ends_at,'place',r.pickup_place,'staff',d.display_name,'status',r.status) from pickup_schedules r join pickup_slots s on s.id=r.slot_id join users d on d.id=s.staff_id where r.claim_id=c.id and r.status='RESERVED'),'history',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'starts',s.starts_at,'ends',s.ends_at,'place',r.pickup_place,'staff',d.display_name,'status',r.status) order by r.created_at desc) from pickup_schedules r join pickup_slots s on s.id=r.slot_id join users d on d.id=s.staff_id where r.claim_id=c.id),'[]'::jsonb)) order by c.created_at desc) from claim_requests c join items i on i.id=c.item_id join users u on u.id=c.claimant_id where c.school_year=yr and (c.claimant_id=p_actor or m)),'[]'::jsonb),
 'slots',coalesce((select jsonb_agg(t.starts_at order by t.starts_at) from (select distinct s.starts_at from pickup_slots s join staff_availability a on a.id=s.availability_id where s.school_year=y and a.cancelled_at is null and s.starts_at>now() and yg_deliverer(s.staff_id) and not exists(select 1 from pickup_schedules r where r.slot_id=s.id and r.status in ('RESERVED','COMPLETED'))) t),'[]'::jsonb),
 'availability',coalesce((select jsonb_agg(jsonb_build_object('id',id,'starts',starts_at,'ends',ends_at) order by starts_at) from staff_availability where staff_id=p_actor and school_year=y and ends_at>now() and cancelled_at is null and yg_deliverer(p_actor)),'[]'::jsonb),
 'assignments',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'starts',s.starts_at,'ends',s.ends_at,'place',r.pickup_place,'staff',d.display_name,'status',r.status,'name',i.name,'photo','/api/image?kind=assigned&id='||r.id,'storageNumber',pr.storage_number,'student',u.display_name,'studentNumber',(select student_number from student_verifications where user_id=u.id and school_year=y and status='VERIFIED' limit 1),'codeEncrypted',c.pickup_code_ciphertext) order by s.starts_at) from pickup_schedules r join pickup_slots s on s.id=r.slot_id join claim_requests c on c.id=r.claim_id join items i on i.id=c.item_id join item_private_details pr on pr.item_id=i.id join users u on u.id=c.claimant_id join users d on d.id=s.staff_id where s.staff_id=p_actor and s.school_year=y and r.status='RESERVED' and yg_deliverer(p_actor)),'[]'::jsonb),
 'verifications',coalesce((select jsonb_agg(jsonb_build_object('id',sv.id,'name',u.display_name,'number',sv.student_number,'status',sv.status,'created',sv.created_at,'deletion',(select delete_status from verification_uploads where verification_id=sv.id order by expires_at desc limit 1)) order by sv.created_at) from student_verifications sv join users u on u.id=sv.user_id where sv.school_year=y and yg_verifier(p_actor) and (sv.status='ACCOUNT_PENDING' or exists(select 1 from verification_uploads where verification_id=sv.id and delete_status='DELETION_PENDING'))),'[]'::jsonb),
 'members',coalesce((select jsonb_agg(jsonb_build_object('id',u.id,'name',u.display_name,'number',sv.student_number,'role',yg_role(u.id),'head',coalesce(cr.is_head,false),'deliver',coalesce(cr.can_deliver,false))) from users u join student_verifications sv on sv.user_id=u.id and sv.school_year=y and sv.status='VERIFIED' left join council_roles cr on cr.user_id=u.id and cr.school_year=y and cr.revoked_at is null where yg_role(p_actor)='SUPER_ADMIN'),'[]'::jsonb),
 'audit',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'text',u.display_name||' · '||l.action,'created',l.created_at) order by l.created_at desc) from audit_logs l join users u on u.id=l.actor_id where l.school_year=yr and m),'[]'::jsonb));
 return result;
end$$;
create function public.yg_image(p_actor uuid,p_kind text,p_id uuid) returns jsonb language plpgsql set search_path=public as $$declare path text;begin
 if p_kind='verification' then
  if not yg_verifier(p_actor) then raise exception '학생증 열람 권한이 없어요.';end if;
  select vu.object_path into path from verification_uploads vu join student_verifications sv on sv.id=vu.verification_id where sv.id=p_id and sv.school_year=yg_year() and sv.status='ACCOUNT_PENDING' and vu.delete_status='PENDING' and vu.expires_at>now();
  if path is not null then perform yg_log(p_actor,'학생증 열람',p_id);end if;
  return jsonb_build_object('bucket','student-verifications','path',path);
 end if;
 if not yg_verified(p_actor) then raise exception '재학생 인증이 필요해요.';end if;
 if p_kind='item' then
  select im.object_path into path from item_images im join items i on i.id=im.item_id where i.id=p_id and im.is_approved_public and (i.current_year=yg_year() or yg_manager(p_actor)) limit 1;
 elsif p_kind='submission' then
  select photo_path into path from item_submission_requests where id=p_id and (submitter_id=p_actor or yg_manager(p_actor));
 elsif p_kind='assigned' then
  select im.object_path into path from pickup_schedules r join pickup_slots s on s.id=r.slot_id join claim_requests c on c.id=r.claim_id join item_images im on im.item_id=c.item_id where r.id=p_id and r.status='RESERVED' and s.staff_id=p_actor and yg_deliverer(p_actor) limit 1;
 end if;
 return jsonb_build_object('bucket','item-photos','path',path);end$$;
create function public.yg_maintenance() returns void language plpgsql set search_path=public as $$declare r record;begin
 for r in select sv.* from student_verifications sv where sv.status='ACCOUNT_PENDING' and exists(select 1 from verification_uploads u where u.verification_id=sv.id and u.expires_at<=now() and u.delete_status<>'DELETED') for update loop
  update student_verifications set status='REJECTED',feedback='인증 사진 보관기간이 만료됐어요. 다시 제출해주세요.' where id=r.id;
  perform yg_notify(r.user_id,'ACCOUNT_REJECTED','인증 사진이 만료됐어요. 다시 제출해주세요.',r.id);
 end loop;
 update verification_uploads set delete_status='DELETION_PENDING' where delete_status='PENDING' and expires_at<=now();
 for r in select p.id,c.claimant_id from pickup_schedules p join pickup_slots s on s.id=p.slot_id join claim_requests c on c.id=p.claim_id where p.status='RESERVED' and p.reminded_at is null and s.starts_at>now() and s.starts_at<=now()+interval '30 minutes' for update of p skip locked loop
  perform yg_notify(r.claimant_id,'PICKUP_REMINDER','수령 예약 시간이 가까워졌어요.',r.id);
  update pickup_schedules set reminded_at=now() where id=r.id;
 end loop;
 delete from app_sessions where expires_at<now();
 delete from login_limits where window_start<now()-interval '1 day';
end$$;
revoke all on function public.yg_state(uuid,integer),public.yg_image(uuid,text,uuid),public.yg_maintenance() from public,anon,authenticated;
grant execute on function public.yg_state(uuid,integer),public.yg_image(uuid,text,uuid),public.yg_maintenance() to service_role;

-- SOURCE 202609220005_storage.sql
-- SHA256 f2e92294999dda695f95fba47f8ec7e67900827a8823e1bc5c7525c669249988
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('student-verifications','student-verifications',false,5242880,array['image/webp']),
 ('item-photos','item-photos',false,5242880,array['image/webp'])
on conflict(id) do update set public=false,file_size_limit=5242880,allowed_mime_types=array['image/webp'];
-- No client Storage policy: uploads and streamed image reads are server-only.
-- Existing project-wide Storage policies must not grant access to these buckets.

-- SOURCE 202609220006_operator_bootstrap.sql
-- SHA256 27432a5f792851f14b5aba0b241952b4895190dd6cba3cf0bd712e9244488f0c
-- Trusted school operator only, with a service credential. Never called by a
-- web route. Used for the first identities and recovery after annual expiry.
create function public.yg_operator_bootstrap(p_name text,p_number text,p_hash text,p_year integer,p_role text,p_head boolean default false,p_user uuid default null) returns uuid language plpgsql set search_path=public as $$declare a uuid;begin
 if p_role not in ('SUPER_ADMIN','PRESIDENT_TEAM','WELFARE_MANAGER') or (p_head and p_role<>'WELFARE_MANAGER') or p_number !~ '^[0-9]{5}$' or char_length(trim(p_name)) not between 2 and 40 or p_hash not like 'scrypt$%' then raise exception '초기 관리자 정보를 확인해주세요.';end if;
 if yg_year() is null then insert into school_years values(p_year,make_date(p_year,3,1),make_date(p_year+1,3,1)-1,true);end if;
 if yg_year()<>p_year then raise exception '현재 학년도와 일치해야 해요.';end if;
 if p_user is null then insert into users(display_name) values(trim(p_name)) returning id into a;
 else a:=p_user;if not exists(select 1 from users where id=a and display_name=trim(p_name)) then raise exception '기존 계정을 확인해주세요.';end if;end if;
 insert into pin_credentials values(a,p_hash) on conflict(user_id) do update set pin_hash=excluded.pin_hash;
 delete from app_sessions where user_id=a;
 update student_verifications set status='EXPIRED' where user_id=a and school_year=p_year and status in ('ACCOUNT_PENDING','VERIFIED');
 update verification_uploads set delete_status='DELETION_PENDING' where verification_id in(select id from student_verifications where user_id=a) and delete_status<>'DELETED';
 insert into student_verifications(user_id,school_year,student_number,status,verified_at,reviewed_by,feedback) values(a,p_year,p_number,'VERIFIED',now(),a,'학교 운영 담당자의 초기 신원 확인');
 update council_roles set revoked_at=now() where user_id=a and school_year=p_year and revoked_at is null;
 insert into council_roles(user_id,school_year,role,is_head,can_deliver,starts_at,ends_at,granted_by) values(a,p_year,p_role::app_role,p_head,p_role<>'SUPER_ADMIN',now(),make_date(p_year+1,3,1)::timestamp at time zone 'Asia/Seoul',a);
 perform yg_log(a,'운영 담당자 초기 관리자 설정',a);return a;
end$$;
revoke all on function public.yg_operator_bootstrap(text,text,text,integer,text,boolean,uuid) from public,anon,authenticated;
grant execute on function public.yg_operator_bootstrap(text,text,text,integer,text,boolean,uuid) to service_role;

-- SOURCE 202609230007_account_roles.sql
-- SHA256 8a898979f60b4d229c0a2acbdd4e34193b1ac16156defdbfbc7c4abf656cf7e1
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

-- SOURCE 202609230008_explicit_rls.sql
-- SHA256 dbba59ba80275f6e2fdc0f4078fca216b5a742b87c6dec7a04f6993d38990341
-- Custom HttpOnly sessions are verified by Next.js, not by Supabase Auth JWTs.
-- Therefore browsers get NO direct app-table access, even after a Supabase login.
-- Each server RPC independently checks actor/year/role/ownership. service_role
-- bypasses RLS; these checks must never be replaced with client-supplied IDs.
do $$declare t text;begin
 foreach t in array array['school_years','users','student_verifications','verification_uploads','council_roles','categories','locations','item_submission_requests','items','item_private_details','item_images','item_history','claim_requests','staff_availability','pickup_slots','pickup_schedules','notifications','audit_logs','year_transfers','notification_outbox','pin_credentials','app_sessions','login_limits','upload_jobs','admin_allowlist'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('alter table public.%I force row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant all on public.%I to service_role',t);
  execute format('create policy yg_server_only on public.%I as restrictive for all to anon,authenticated using (false) with check (false)',t);
 end loop;
end$$;
-- A broad permissive Storage policy elsewhere cannot open these two buckets.
-- Storage API does actual object deletion; never DELETE FROM storage.objects.
create policy yg_private_server_only on storage.objects as restrictive for all to anon,authenticated
 using (bucket_id not in ('student-verifications','item-photos'))
 with check (bucket_id not in ('student-verifications','item-photos'));

create function public.yg_connection_health() returns jsonb language sql stable set search_path=public,pg_catalog as $$
 with required(name) as (select unnest(array['school_years','users','student_verifications','verification_uploads','council_roles','categories','locations','item_submission_requests','items','item_private_details','item_images','item_history','claim_requests','staff_availability','pickup_slots','pickup_schedules','notifications','audit_logs','year_transfers','notification_outbox','pin_credentials','app_sessions','login_limits','upload_jobs','admin_allowlist']))
 select jsonb_build_object('version',8,'year',yg_year(),
 'rlsReady',not exists(select 1 from required r left join pg_class c on c.oid=to_regclass('public.'||r.name) where c.oid is null or not c.relrowsecurity or not c.relforcerowsecurity or not exists(select 1 from pg_policy p where p.polrelid=c.oid and p.polname='yg_server_only' and not p.polpermissive and p.polcmd='*' and pg_get_expr(p.polqual,p.polrelid)='false' and pg_get_expr(p.polwithcheck,p.polrelid)='false')),
 'storageReady',(select count(*)=2 from storage.buckets where id in ('student-verifications','item-photos') and not public and file_size_limit=5242880 and allowed_mime_types=array['image/webp']) and exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid where p.polrelid='storage.objects'::regclass and c.relrowsecurity and p.polname='yg_private_server_only' and not p.polpermissive));
$$;
revoke all on function public.yg_connection_health() from public,anon,authenticated;
grant execute on function public.yg_connection_health() to service_role;
commit;
