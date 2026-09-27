// SQL model of Supabase-managed metadata for local policy tests, NOT a Storage server.
export const storageFixture=`create schema storage;
create table storage.buckets(id text primary key,name text,public boolean default false,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text references storage.buckets,name text);
alter table storage.objects enable row level security;
grant usage on schema storage to service_role,anon,authenticated;
grant all on all tables in schema storage to service_role;
`;
