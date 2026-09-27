begin;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('student-verifications','student-verifications',false,5242880,array['image/webp']),
 ('item-photos','item-photos',false,5242880,array['image/webp'])
on conflict(id) do update set public=false,file_size_limit=5242880,allowed_mime_types=array['image/webp'];
-- No client Storage policy: uploads and streamed image reads are server-only.
-- Existing project-wide Storage policies must not grant access to these buckets.
commit;
