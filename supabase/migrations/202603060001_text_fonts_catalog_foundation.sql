-- Global text fonts catalog managed by admin panel.

create extension if not exists pgcrypto;

create table if not exists public.text_fonts_catalog (
  id uuid primary key default gen_random_uuid(),
  family text not null unique,
  label text not null,
  locale text not null default 'english',
  preview text not null default 'Aa',
  file_path text not null unique,
  file_url text not null,
  mime_type text not null,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (char_length(btrim(family)) > 0),
  check (char_length(btrim(label)) > 0),
  check (locale in ('english', 'arabic')),
  check (char_length(btrim(file_path)) > 0),
  check (char_length(btrim(file_url)) > 0),
  check (char_length(btrim(mime_type)) > 0)
);

create index if not exists text_fonts_catalog_locale_active_sort_idx
  on public.text_fonts_catalog (locale, is_active, sort_order, created_at desc);

create index if not exists text_fonts_catalog_active_sort_idx
  on public.text_fonts_catalog (is_active, sort_order, created_at desc);

create or replace function public.touch_row_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists trg_text_fonts_catalog_touch_updated_at on public.text_fonts_catalog;
create trigger trg_text_fonts_catalog_touch_updated_at
before update on public.text_fonts_catalog
for each row
execute function public.touch_row_updated_at();

alter table public.text_fonts_catalog enable row level security;

drop policy if exists text_fonts_catalog_public_read on public.text_fonts_catalog;
create policy text_fonts_catalog_public_read
on public.text_fonts_catalog
for select
to public
using (is_active = true);

drop policy if exists text_fonts_catalog_service_role_write on public.text_fonts_catalog;
create policy text_fonts_catalog_service_role_write
on public.text_fonts_catalog
for all
to service_role
using (true)
with check (true);

-- Storage bucket for uploaded text fonts.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'text-fonts',
  'text-fonts',
  true,
  15728640,
  array[
    'font/ttf',
    'font/otf',
    'font/collection',
    'application/x-font-ttf',
    'application/x-font-opentype',
    'application/font-sfnt',
    'application/octet-stream'
  ]
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists text_fonts_bucket_public_read on storage.objects;
create policy text_fonts_bucket_public_read
on storage.objects
for select
to public
using (bucket_id = 'text-fonts');

drop policy if exists text_fonts_bucket_service_role_write on storage.objects;
create policy text_fonts_bucket_service_role_write
on storage.objects
for all
to service_role
using (bucket_id = 'text-fonts')
with check (bucket_id = 'text-fonts');
