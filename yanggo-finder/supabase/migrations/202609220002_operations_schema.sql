begin;
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
commit;
