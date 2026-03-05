-- WonderPic backend foundation (Phase 1)
-- Firebase Auth identity + Supabase credits/account lifecycle.

create extension if not exists pgcrypto;

create schema if not exists app_private;
revoke all on schema app_private from public, anon, authenticated;
grant usage on schema app_private to service_role;

create table if not exists app_private.accounts (
  id uuid primary key default gen_random_uuid(),
  firebase_uid text not null unique,
  email text,
  display_name text,
  photo_url text,
  status text not null default 'active' check (status in ('active', 'suspended', 'deleted')),
  suspended_reason text,
  suspended_at timestamptz,
  deleted_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists app_private.credit_holds (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references app_private.accounts(id) on delete cascade,
  idempotency_key text not null,
  operation_key text not null,
  amount numeric(18, 4) not null check (amount > 0),
  status text not null default 'reserved' check (status in ('reserved', 'committed', 'refunded', 'released', 'expired')),
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  expires_at timestamptz not null,
  committed_at timestamptz,
  refunded_at timestamptz,
  released_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (account_id, idempotency_key),
  unique (account_id, operation_key)
);

create table if not exists app_private.credit_ledger (
  id bigserial primary key,
  account_id uuid not null references app_private.accounts(id) on delete cascade,
  hold_id uuid references app_private.credit_holds(id) on delete set null,
  idempotency_key text not null,
  entry_type text not null check (entry_type in ('grant', 'commit', 'refund', 'adjustment')),
  delta_credits numeric(18, 4) not null check (delta_credits <> 0),
  balance_after numeric(18, 4) not null,
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  unique (account_id, idempotency_key)
);

create unique index if not exists credit_ledger_one_commit_per_hold_idx
  on app_private.credit_ledger (hold_id)
  where entry_type = 'commit';

create unique index if not exists credit_ledger_one_refund_per_hold_idx
  on app_private.credit_ledger (hold_id)
  where entry_type = 'refund';

create index if not exists credit_holds_account_status_expires_idx
  on app_private.credit_holds (account_id, status, expires_at);

create index if not exists credit_ledger_account_created_idx
  on app_private.credit_ledger (account_id, created_at desc);

create or replace function app_private.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists trg_accounts_touch_updated_at on app_private.accounts;
create trigger trg_accounts_touch_updated_at
before update on app_private.accounts
for each row
execute function app_private.touch_updated_at();

drop trigger if exists trg_credit_holds_touch_updated_at on app_private.credit_holds;
create trigger trg_credit_holds_touch_updated_at
before update on app_private.credit_holds
for each row
execute function app_private.touch_updated_at();

alter table app_private.accounts enable row level security;
alter table app_private.credit_holds enable row level security;
alter table app_private.credit_ledger enable row level security;

create or replace function app_private.account_posted_balance(p_account_id uuid)
returns numeric
language sql
stable
as $$
  select coalesce(sum(delta_credits), 0)::numeric(18, 4)
  from app_private.credit_ledger
  where account_id = p_account_id;
$$;

create or replace function app_private.account_reserved_balance(p_account_id uuid)
returns numeric
language sql
stable
as $$
  select coalesce(sum(amount), 0)::numeric(18, 4)
  from app_private.credit_holds
  where account_id = p_account_id
    and status = 'reserved'
    and expires_at > timezone('utc', now());
$$;

create or replace function app_private.account_available_balance(p_account_id uuid)
returns numeric
language sql
stable
as $$
  select (
    app_private.account_posted_balance(p_account_id)
    - app_private.account_reserved_balance(p_account_id)
  )::numeric(18, 4);
$$;

create or replace function app_private.expire_holds(p_account_id uuid)
returns integer
language plpgsql
as $$
declare
  v_count integer := 0;
begin
  update app_private.credit_holds
  set status = 'expired',
      released_at = coalesce(released_at, timezone('utc', now())),
      updated_at = timezone('utc', now())
  where account_id = p_account_id
    and status = 'reserved'
    and expires_at <= timezone('utc', now());

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

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
  on conflict (firebase_uid) do update
    set email = coalesce(excluded.email, app_private.accounts.email),
        display_name = coalesce(excluded.display_name, app_private.accounts.display_name),
        photo_url = coalesce(excluded.photo_url, app_private.accounts.photo_url),
        metadata = case
          when excluded.metadata = '{}'::jsonb then app_private.accounts.metadata
          else excluded.metadata
        end,
        updated_at = timezone('utc', now())
  returning * into v_account;

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
  select *
  into v_account
  from app_private.accounts
  where firebase_uid = btrim(coalesce(p_firebase_uid, ''))
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

create or replace function app_private.reserve_credits(
  p_firebase_uid text,
  p_amount numeric,
  p_idempotency_key text,
  p_operation_key text,
  p_reason text default null,
  p_ttl_seconds integer default 900,
  p_metadata jsonb default '{}'::jsonb
)
returns table (
  hold_id uuid,
  hold_status text,
  amount numeric,
  expires_at timestamptz,
  posted_balance numeric,
  reserved_balance numeric,
  available_balance numeric,
  account_status text
)
language plpgsql
as $$
declare
  v_account_id uuid;
  v_account_status text;
  v_hold app_private.credit_holds%rowtype;
  v_effective_operation_key text;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'INVALID_AMOUNT';
  end if;

  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    raise exception 'IDEMPOTENCY_KEY_REQUIRED';
  end if;

  v_effective_operation_key := nullif(btrim(coalesce(p_operation_key, '')), '');
  if v_effective_operation_key is null then
    v_effective_operation_key := btrim(p_idempotency_key);
  end if;

  select a.account_id, a.status
  into v_account_id, v_account_status
  from app_private.ensure_account(p_firebase_uid) a;

  if v_account_status <> 'active' then
    raise exception 'ACCOUNT_NOT_ACTIVE';
  end if;

  perform pg_advisory_xact_lock(hashtext(v_account_id::text));
  perform app_private.expire_holds(v_account_id);

  select *
  into v_hold
  from app_private.credit_holds
  where account_id = v_account_id
    and idempotency_key = btrim(p_idempotency_key)
  limit 1;

  if v_hold.id is not null then
    return query
    select
      v_hold.id,
      v_hold.status,
      v_hold.amount,
      v_hold.expires_at,
      app_private.account_posted_balance(v_account_id),
      app_private.account_reserved_balance(v_account_id),
      app_private.account_available_balance(v_account_id),
      v_account_status;
    return;
  end if;

  if app_private.account_available_balance(v_account_id) < p_amount then
    raise exception 'INSUFFICIENT_CREDITS';
  end if;

  insert into app_private.credit_holds (
    account_id,
    idempotency_key,
    operation_key,
    amount,
    reason,
    metadata,
    expires_at
  )
  values (
    v_account_id,
    btrim(p_idempotency_key),
    v_effective_operation_key,
    p_amount,
    nullif(btrim(coalesce(p_reason, '')), ''),
    coalesce(p_metadata, '{}'::jsonb),
    timezone('utc', now()) + make_interval(secs => greatest(coalesce(p_ttl_seconds, 900), 30))
  )
  returning * into v_hold;

  return query
  select
    v_hold.id,
    v_hold.status,
    v_hold.amount,
    v_hold.expires_at,
    app_private.account_posted_balance(v_account_id),
    app_private.account_reserved_balance(v_account_id),
    app_private.account_available_balance(v_account_id),
    v_account_status;
end;
$$;

create or replace function app_private.commit_credits(
  p_firebase_uid text,
  p_hold_id uuid,
  p_idempotency_key text,
  p_reason text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns table (
  hold_id uuid,
  hold_status text,
  amount numeric,
  ledger_id bigint,
  delta_credits numeric,
  balance_after numeric,
  available_balance numeric,
  account_status text
)
language plpgsql
as $$
declare
  v_account_id uuid;
  v_account_status text;
  v_hold app_private.credit_holds%rowtype;
  v_existing_commit app_private.credit_ledger%rowtype;
  v_ledger app_private.credit_ledger%rowtype;
  v_posted_before numeric(18,4);
begin
  if p_hold_id is null then
    raise exception 'HOLD_ID_REQUIRED';
  end if;

  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    raise exception 'IDEMPOTENCY_KEY_REQUIRED';
  end if;

  select a.account_id, a.status
  into v_account_id, v_account_status
  from app_private.ensure_account(p_firebase_uid) a;

  if v_account_status = 'deleted' then
    raise exception 'ACCOUNT_DELETED';
  end if;

  perform pg_advisory_xact_lock(hashtext(v_account_id::text));
  perform app_private.expire_holds(v_account_id);

  select *
  into v_hold
  from app_private.credit_holds
  where id = p_hold_id
    and account_id = v_account_id
  for update;

  if v_hold.id is null then
    raise exception 'HOLD_NOT_FOUND';
  end if;

  select *
  into v_existing_commit
  from app_private.credit_ledger
  where hold_id = v_hold.id
    and entry_type = 'commit'
  limit 1;

  if v_existing_commit.id is not null then
    update app_private.credit_holds
    set status = 'committed',
        committed_at = coalesce(committed_at, timezone('utc', now()))
    where id = v_hold.id
      and status <> 'committed';

    return query
    select
      v_hold.id,
      'committed'::text,
      v_hold.amount,
      v_existing_commit.id,
      v_existing_commit.delta_credits,
      v_existing_commit.balance_after,
      app_private.account_available_balance(v_account_id),
      v_account_status;
    return;
  end if;

  if v_hold.status <> 'reserved' then
    raise exception 'HOLD_NOT_RESERVABLE';
  end if;

  if v_hold.expires_at <= timezone('utc', now()) then
    update app_private.credit_holds
    set status = 'expired',
        released_at = coalesce(released_at, timezone('utc', now()))
    where id = v_hold.id;
    raise exception 'HOLD_EXPIRED';
  end if;

  v_posted_before := app_private.account_posted_balance(v_account_id);

  begin
    insert into app_private.credit_ledger (
      account_id,
      hold_id,
      idempotency_key,
      entry_type,
      delta_credits,
      balance_after,
      reason,
      metadata
    )
    values (
      v_account_id,
      v_hold.id,
      btrim(p_idempotency_key),
      'commit',
      -v_hold.amount,
      (v_posted_before - v_hold.amount)::numeric(18, 4),
      nullif(btrim(coalesce(p_reason, '')), ''),
      coalesce(p_metadata, '{}'::jsonb)
    )
    on conflict (account_id, idempotency_key) do update
      set metadata = app_private.credit_ledger.metadata || excluded.metadata
    returning * into v_ledger;
  exception
    when unique_violation then
      select *
      into v_ledger
      from app_private.credit_ledger
      where hold_id = v_hold.id
        and entry_type = 'commit'
      limit 1;
  end;

  update app_private.credit_holds
  set status = 'committed',
      committed_at = coalesce(committed_at, timezone('utc', now()))
  where id = v_hold.id;

  return query
  select
    v_hold.id,
    'committed'::text,
    v_hold.amount,
    v_ledger.id,
    v_ledger.delta_credits,
    v_ledger.balance_after,
    app_private.account_available_balance(v_account_id),
    v_account_status;
end;
$$;

create or replace function app_private.refund_credits(
  p_firebase_uid text,
  p_hold_id uuid,
  p_idempotency_key text,
  p_reason text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns table (
  hold_id uuid,
  hold_status text,
  amount numeric,
  ledger_id bigint,
  delta_credits numeric,
  balance_after numeric,
  available_balance numeric,
  account_status text
)
language plpgsql
as $$
declare
  v_account_id uuid;
  v_account_status text;
  v_hold app_private.credit_holds%rowtype;
  v_existing_refund app_private.credit_ledger%rowtype;
  v_ledger app_private.credit_ledger%rowtype;
  v_posted_before numeric(18,4);
begin
  if p_hold_id is null then
    raise exception 'HOLD_ID_REQUIRED';
  end if;

  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    raise exception 'IDEMPOTENCY_KEY_REQUIRED';
  end if;

  select a.account_id, a.status
  into v_account_id, v_account_status
  from app_private.ensure_account(p_firebase_uid) a;

  if v_account_status = 'deleted' then
    raise exception 'ACCOUNT_DELETED';
  end if;

  perform pg_advisory_xact_lock(hashtext(v_account_id::text));

  select *
  into v_hold
  from app_private.credit_holds
  where id = p_hold_id
    and account_id = v_account_id
  for update;

  if v_hold.id is null then
    raise exception 'HOLD_NOT_FOUND';
  end if;

  if v_hold.status not in ('committed', 'refunded') then
    raise exception 'HOLD_NOT_REFUNDABLE';
  end if;

  select *
  into v_existing_refund
  from app_private.credit_ledger
  where hold_id = v_hold.id
    and entry_type = 'refund'
  limit 1;

  if v_existing_refund.id is not null then
    update app_private.credit_holds
    set status = 'refunded',
        refunded_at = coalesce(refunded_at, timezone('utc', now()))
    where id = v_hold.id
      and status <> 'refunded';

    return query
    select
      v_hold.id,
      'refunded'::text,
      v_hold.amount,
      v_existing_refund.id,
      v_existing_refund.delta_credits,
      v_existing_refund.balance_after,
      app_private.account_available_balance(v_account_id),
      v_account_status;
    return;
  end if;

  v_posted_before := app_private.account_posted_balance(v_account_id);

  insert into app_private.credit_ledger (
    account_id,
    hold_id,
    idempotency_key,
    entry_type,
    delta_credits,
    balance_after,
    reason,
    metadata
  )
  values (
    v_account_id,
    v_hold.id,
    btrim(p_idempotency_key),
    'refund',
    v_hold.amount,
    (v_posted_before + v_hold.amount)::numeric(18, 4),
    nullif(btrim(coalesce(p_reason, '')), ''),
    coalesce(p_metadata, '{}'::jsonb)
  )
  on conflict (account_id, idempotency_key) do update
    set metadata = app_private.credit_ledger.metadata || excluded.metadata
  returning * into v_ledger;

  update app_private.credit_holds
  set status = 'refunded',
      refunded_at = coalesce(refunded_at, timezone('utc', now()))
  where id = v_hold.id;

  return query
  select
    v_hold.id,
    'refunded'::text,
    v_hold.amount,
    v_ledger.id,
    v_ledger.delta_credits,
    v_ledger.balance_after,
    app_private.account_available_balance(v_account_id),
    v_account_status;
end;
$$;

create or replace function app_private.grant_credits(
  p_firebase_uid text,
  p_amount numeric,
  p_idempotency_key text,
  p_reason text default 'grant',
  p_metadata jsonb default '{}'::jsonb
)
returns table (
  account_id uuid,
  account_status text,
  ledger_id bigint,
  delta_credits numeric,
  balance_after numeric,
  available_balance numeric
)
language plpgsql
as $$
declare
  v_account_id uuid;
  v_account_status text;
  v_ledger app_private.credit_ledger%rowtype;
  v_posted_before numeric(18,4);
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'INVALID_AMOUNT';
  end if;

  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    raise exception 'IDEMPOTENCY_KEY_REQUIRED';
  end if;

  select a.account_id, a.status
  into v_account_id, v_account_status
  from app_private.ensure_account(p_firebase_uid) a;

  if v_account_status = 'deleted' then
    raise exception 'ACCOUNT_DELETED';
  end if;

  perform pg_advisory_xact_lock(hashtext(v_account_id::text));
  v_posted_before := app_private.account_posted_balance(v_account_id);

  insert into app_private.credit_ledger (
    account_id,
    idempotency_key,
    entry_type,
    delta_credits,
    balance_after,
    reason,
    metadata
  )
  values (
    v_account_id,
    btrim(p_idempotency_key),
    'grant',
    p_amount,
    (v_posted_before + p_amount)::numeric(18, 4),
    nullif(btrim(coalesce(p_reason, '')), ''),
    coalesce(p_metadata, '{}'::jsonb)
  )
  on conflict (account_id, idempotency_key) do update
    set metadata = app_private.credit_ledger.metadata || excluded.metadata
  returning * into v_ledger;

  return query
  select
    v_account_id,
    v_account_status,
    v_ledger.id,
    v_ledger.delta_credits,
    v_ledger.balance_after,
    app_private.account_available_balance(v_account_id);
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

  update app_private.accounts
  set status = v_normalized_status,
      suspended_reason = case when v_normalized_status = 'suspended' then nullif(btrim(coalesce(p_reason, '')), '') else null end,
      suspended_at = case when v_normalized_status = 'suspended' then timezone('utc', now()) else null end,
      deleted_at = case when v_normalized_status = 'deleted' then timezone('utc', now()) else null end,
      updated_at = timezone('utc', now())
  where firebase_uid = btrim(p_firebase_uid)
  returning * into v_account;

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

-- Public wrappers exposed for service-key RPC access.

create or replace function public.app_ensure_account(
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
language sql
security definer
set search_path = app_private, public
as $$
  select * from app_private.ensure_account(
    p_firebase_uid,
    p_email,
    p_display_name,
    p_photo_url,
    p_metadata
  );
$$;

create or replace function public.app_account_state(
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
language sql
security definer
set search_path = app_private, public
as $$
  select * from app_private.account_state(p_firebase_uid);
$$;

create or replace function public.app_reserve_credits(
  p_firebase_uid text,
  p_amount numeric,
  p_idempotency_key text,
  p_operation_key text,
  p_reason text default null,
  p_ttl_seconds integer default 900,
  p_metadata jsonb default '{}'::jsonb
)
returns table (
  hold_id uuid,
  hold_status text,
  amount numeric,
  expires_at timestamptz,
  posted_balance numeric,
  reserved_balance numeric,
  available_balance numeric,
  account_status text
)
language sql
security definer
set search_path = app_private, public
as $$
  select * from app_private.reserve_credits(
    p_firebase_uid,
    p_amount,
    p_idempotency_key,
    p_operation_key,
    p_reason,
    p_ttl_seconds,
    p_metadata
  );
$$;

create or replace function public.app_commit_credits(
  p_firebase_uid text,
  p_hold_id uuid,
  p_idempotency_key text,
  p_reason text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns table (
  hold_id uuid,
  hold_status text,
  amount numeric,
  ledger_id bigint,
  delta_credits numeric,
  balance_after numeric,
  available_balance numeric,
  account_status text
)
language sql
security definer
set search_path = app_private, public
as $$
  select * from app_private.commit_credits(
    p_firebase_uid,
    p_hold_id,
    p_idempotency_key,
    p_reason,
    p_metadata
  );
$$;

create or replace function public.app_refund_credits(
  p_firebase_uid text,
  p_hold_id uuid,
  p_idempotency_key text,
  p_reason text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns table (
  hold_id uuid,
  hold_status text,
  amount numeric,
  ledger_id bigint,
  delta_credits numeric,
  balance_after numeric,
  available_balance numeric,
  account_status text
)
language sql
security definer
set search_path = app_private, public
as $$
  select * from app_private.refund_credits(
    p_firebase_uid,
    p_hold_id,
    p_idempotency_key,
    p_reason,
    p_metadata
  );
$$;

create or replace function public.app_grant_credits(
  p_firebase_uid text,
  p_amount numeric,
  p_idempotency_key text,
  p_reason text default 'grant',
  p_metadata jsonb default '{}'::jsonb
)
returns table (
  account_id uuid,
  account_status text,
  ledger_id bigint,
  delta_credits numeric,
  balance_after numeric,
  available_balance numeric
)
language sql
security definer
set search_path = app_private, public
as $$
  select * from app_private.grant_credits(
    p_firebase_uid,
    p_amount,
    p_idempotency_key,
    p_reason,
    p_metadata
  );
$$;

create or replace function public.app_set_account_status(
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
language sql
security definer
set search_path = app_private, public
as $$
  select * from app_private.set_account_status(
    p_firebase_uid,
    p_status,
    p_reason
  );
$$;

revoke all on all tables in schema app_private from public, anon, authenticated;
revoke all on all sequences in schema app_private from public, anon, authenticated;

revoke all on function public.app_ensure_account(text, text, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.app_account_state(text) from public, anon, authenticated;
revoke all on function public.app_reserve_credits(text, numeric, text, text, text, integer, jsonb) from public, anon, authenticated;
revoke all on function public.app_commit_credits(text, uuid, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.app_refund_credits(text, uuid, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.app_grant_credits(text, numeric, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.app_set_account_status(text, text, text) from public, anon, authenticated;

grant execute on function public.app_ensure_account(text, text, text, text, jsonb) to service_role;
grant execute on function public.app_account_state(text) to service_role;
grant execute on function public.app_reserve_credits(text, numeric, text, text, text, integer, jsonb) to service_role;
grant execute on function public.app_commit_credits(text, uuid, text, text, jsonb) to service_role;
grant execute on function public.app_refund_credits(text, uuid, text, text, jsonb) to service_role;
grant execute on function public.app_grant_credits(text, numeric, text, text, jsonb) to service_role;
grant execute on function public.app_set_account_status(text, text, text) to service_role;
