-- Fix ambiguous firebase_uid references in PL/pgSQL account functions.

create or replace function app_private.ensure_account(
  p_firebase_uid text,
  p_email text default null,
  p_display_name text default null,
  p_photo_url text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns table (
  account_id uuid,
  firebase_uid text,
  status text,
  email text,
  display_name text,
  posted_balance numeric,
  reserved_balance numeric,
  available_balance numeric,
  updated_at timestamptz
)
language plpgsql
as $$
declare
  v_account app_private.accounts%rowtype;
begin
  if p_firebase_uid is null or btrim(p_firebase_uid) = '' then
    raise exception 'INVALID_FIREBASE_UID';
  end if;

  insert into app_private.accounts (
    firebase_uid,
    email,
    display_name,
    photo_url,
    metadata
  )
  values (
    btrim(p_firebase_uid),
    nullif(btrim(coalesce(p_email, '')), ''),
    nullif(btrim(coalesce(p_display_name, '')), ''),
    nullif(btrim(coalesce(p_photo_url, '')), ''),
    coalesce(p_metadata, '{}'::jsonb)
  )
  on conflict on constraint accounts_firebase_uid_key do update
    set email = coalesce(excluded.email, app_private.accounts.email),
        display_name = coalesce(excluded.display_name, app_private.accounts.display_name),
        photo_url = coalesce(excluded.photo_url, app_private.accounts.photo_url),
        metadata = case
          when excluded.metadata = '{}'::jsonb then app_private.accounts.metadata
          else excluded.metadata
        end,
        updated_at = timezone('utc', now())
  returning app_private.accounts.* into v_account;

  perform app_private.expire_holds(v_account.id);

  return query
  select
    v_account.id,
    v_account.firebase_uid,
    v_account.status,
    v_account.email,
    v_account.display_name,
    app_private.account_posted_balance(v_account.id),
    app_private.account_reserved_balance(v_account.id),
    app_private.account_available_balance(v_account.id),
    v_account.updated_at;
end;
$$;

create or replace function app_private.account_state(
  p_firebase_uid text
)
returns table (
  account_id uuid,
  firebase_uid text,
  status text,
  email text,
  display_name text,
  suspended_reason text,
  suspended_at timestamptz,
  deleted_at timestamptz,
  posted_balance numeric,
  reserved_balance numeric,
  available_balance numeric,
  updated_at timestamptz
)
language plpgsql
as $$
declare
  v_account app_private.accounts%rowtype;
begin
  select a.*
  into v_account
  from app_private.accounts a
  where a.firebase_uid = btrim(coalesce(p_firebase_uid, ''))
  limit 1;

  if v_account.id is null then
    raise exception 'ACCOUNT_NOT_FOUND';
  end if;

  perform app_private.expire_holds(v_account.id);

  return query
  select
    v_account.id,
    v_account.firebase_uid,
    v_account.status,
    v_account.email,
    v_account.display_name,
    v_account.suspended_reason,
    v_account.suspended_at,
    v_account.deleted_at,
    app_private.account_posted_balance(v_account.id),
    app_private.account_reserved_balance(v_account.id),
    app_private.account_available_balance(v_account.id),
    v_account.updated_at;
end;
$$;

create or replace function app_private.set_account_status(
  p_firebase_uid text,
  p_status text,
  p_reason text default null
)
returns table (
  account_id uuid,
  firebase_uid text,
  status text,
  suspended_reason text,
  suspended_at timestamptz,
  deleted_at timestamptz,
  available_balance numeric,
  updated_at timestamptz
)
language plpgsql
as $$
declare
  v_normalized_status text;
  v_account app_private.accounts%rowtype;
begin
  v_normalized_status := lower(btrim(coalesce(p_status, '')));
  if v_normalized_status not in ('active', 'suspended', 'deleted') then
    raise exception 'INVALID_ACCOUNT_STATUS';
  end if;

  perform app_private.ensure_account(p_firebase_uid);

  update app_private.accounts a
  set status = v_normalized_status,
      suspended_reason = case when v_normalized_status = 'suspended' then nullif(btrim(coalesce(p_reason, '')), '') else null end,
      suspended_at = case when v_normalized_status = 'suspended' then timezone('utc', now()) else null end,
      deleted_at = case when v_normalized_status = 'deleted' then timezone('utc', now()) else null end,
      updated_at = timezone('utc', now())
  where a.firebase_uid = btrim(p_firebase_uid)
  returning a.* into v_account;

  return query
  select
    v_account.id,
    v_account.firebase_uid,
    v_account.status,
    v_account.suspended_reason,
    v_account.suspended_at,
    v_account.deleted_at,
    app_private.account_available_balance(v_account.id),
    v_account.updated_at;
end;
$$;
