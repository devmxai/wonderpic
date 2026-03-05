-- Elements catalog foundation for editor + admin panel uploads.

create extension if not exists pgcrypto;

-- Public catalog tables
create table if not exists public.elements_categories (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (char_length(btrim(slug)) > 0),
  check (char_length(btrim(name)) > 0)
);

create table if not exists public.elements_assets (
  id uuid primary key default gen_random_uuid(),
  category_slug text not null references public.elements_categories(slug) on update cascade on delete restrict,
  title text,
  file_path text not null unique,
  file_url text not null,
  mime_type text not null,
  width integer,
  height integer,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (char_length(btrim(file_path)) > 0),
  check (char_length(btrim(file_url)) > 0),
  check (mime_type in ('image/png', 'image/jpeg', 'image/jpg', 'image/webp'))
);

create index if not exists elements_categories_active_sort_idx
  on public.elements_categories (is_active, sort_order, name);

create index if not exists elements_assets_category_active_sort_idx
  on public.elements_assets (category_slug, is_active, sort_order, created_at desc);

create or replace function public.touch_row_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists trg_elements_categories_touch_updated_at on public.elements_categories;
create trigger trg_elements_categories_touch_updated_at
before update on public.elements_categories
for each row
execute function public.touch_row_updated_at();

drop trigger if exists trg_elements_assets_touch_updated_at on public.elements_assets;
create trigger trg_elements_assets_touch_updated_at
before update on public.elements_assets
for each row
execute function public.touch_row_updated_at();

alter table public.elements_categories enable row level security;
alter table public.elements_assets enable row level security;

drop policy if exists elements_categories_public_read on public.elements_categories;
create policy elements_categories_public_read
on public.elements_categories
for select
to public
using (is_active = true);

drop policy if exists elements_assets_public_read on public.elements_assets;
create policy elements_assets_public_read
on public.elements_assets
for select
to public
using (is_active = true);

drop policy if exists elements_categories_service_role_write on public.elements_categories;
create policy elements_categories_service_role_write
on public.elements_categories
for all
to service_role
using (true)
with check (true);

drop policy if exists elements_assets_service_role_write on public.elements_assets;
create policy elements_assets_service_role_write
on public.elements_assets
for all
to service_role
using (true)
with check (true);

-- Seed default Canva-like shape categories
insert into public.elements_categories (slug, name, sort_order, is_active)
values
  ('basic-shapes', 'Basic', 10, true),
  ('arrows-lines', 'Arrows', 20, true),
  ('badges-labels', 'Badges', 30, true),
  ('bubbles-cards', 'Bubbles', 40, true),
  ('decorative', 'Decorative', 50, true),
  ('symbols-icons', 'Symbols', 60, true)
on conflict (slug) do update
set
  name = excluded.name,
  sort_order = excluded.sort_order,
  is_active = excluded.is_active;

-- Storage bucket for uploaded elements
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'elements',
  'elements',
  true,
  10485760,
  array['image/png', 'image/jpeg', 'image/jpg', 'image/webp']
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists elements_bucket_public_read on storage.objects;
create policy elements_bucket_public_read
on storage.objects
for select
to public
using (bucket_id = 'elements');

drop policy if exists elements_bucket_service_role_write on storage.objects;
create policy elements_bucket_service_role_write
on storage.objects
for all
to service_role
using (bucket_id = 'elements')
with check (bucket_id = 'elements');
