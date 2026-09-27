begin;
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
