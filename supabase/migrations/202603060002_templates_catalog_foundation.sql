-- Templates catalog foundation (SVG-only) for editor templates tab + admin uploads.

create extension if not exists pgcrypto;

create table if not exists public.templates_catalog (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  file_path text not null unique,
  file_url text not null,
  mime_type text not null,
  width integer,
  height integer,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (char_length(btrim(title)) > 0),
  check (char_length(btrim(file_path)) > 0),
  check (char_length(btrim(file_url)) > 0),
  check (mime_type in ('image/svg+xml', 'text/xml', 'application/xml'))
);

create index if not exists templates_catalog_active_sort_idx
  on public.templates_catalog (is_active, sort_order, created_at desc);

create or replace function public.touch_row_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists trg_templates_catalog_touch_updated_at on public.templates_catalog;
create trigger trg_templates_catalog_touch_updated_at
before update on public.templates_catalog
for each row
execute function public.touch_row_updated_at();

alter table public.templates_catalog enable row level security;

drop policy if exists templates_catalog_public_read on public.templates_catalog;
create policy templates_catalog_public_read
on public.templates_catalog
for select
to public
using (is_active = true);

drop policy if exists templates_catalog_service_role_write on public.templates_catalog;
create policy templates_catalog_service_role_write
on public.templates_catalog
for all
to service_role
using (true)
with check (true);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'templates',
  'templates',
  true,
  15728640,
  array['image/svg+xml', 'text/xml', 'application/xml']
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists templates_bucket_public_read on storage.objects;
create policy templates_bucket_public_read
on storage.objects
for select
to public
using (bucket_id = 'templates');

drop policy if exists templates_bucket_service_role_write on storage.objects;
create policy templates_bucket_service_role_write
on storage.objects
for all
to service_role
using (bucket_id = 'templates')
with check (bucket_id = 'templates');
