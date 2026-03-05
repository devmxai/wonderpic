-- Server-side Free Trial state (per Firebase UID/account).
-- Prevents local reset abuse by storing trial counters in DB.

create table if not exists app_private.free_trial_buckets (
  account_id uuid primary key references app_private.accounts(id) on delete cascade,
  total_actions integer not null default 20 check (total_actions >= 0),
  remaining_actions integer not null default 20 check (remaining_actions >= 0),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint free_trial_remaining_le_total check (remaining_actions <= total_actions)
);

create table if not exists app_private.free_trial_events (
  id bigserial primary key,
  account_id uuid not null references app_private.accounts(id) on delete cascade,
  idempotency_key text not null,
  operation_type text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  unique (account_id, idempotency_key)
);

drop trigger if exists trg_free_trial_buckets_touch_updated_at on app_private.free_trial_buckets;
create trigger trg_free_trial_buckets_touch_updated_at
before update on app_private.free_trial_buckets
for each row
execute function app_private.touch_updated_at();

alter table app_private.free_trial_buckets enable row level security;
alter table app_private.free_trial_events enable row level security;

-- Force development rule requested by product:
-- total free trial = 20 for every account.
insert into app_private.free_trial_buckets (
  account_id,
  total_actions,
  remaining_actions
)
select
  a.id,
  20,
  20
from app_private.accounts a
on conflict (account_id) do update
set total_actions = 20,
    remaining_actions = least(greatest(app_private.free_trial_buckets.remaining_actions, 0), 20),
    updated_at = timezone('utc', now());

create or replace function app_private.ensure_free_trial_bucket(
  p_account_id uuid
)
returns app_private.free_trial_buckets
language plpgsql
as $$
declare
  v_bucket app_private.free_trial_buckets%rowtype;
begin
  if p_account_id is null then
    raise exception 'ACCOUNT_ID_REQUIRED';
  end if;

  insert into app_private.free_trial_buckets (
    account_id,
    total_actions,
    remaining_actions
  )
  values (
    p_account_id,
    20,
    20
  )
  on conflict (account_id) do update
    set total_actions = 20,
        remaining_actions = least(greatest(app_private.free_trial_buckets.remaining_actions, 0), 20),
        updated_at = timezone('utc', now())
  returning * into v_bucket;

  return v_bucket;
end;
$$;

create or replace function app_private.free_trial_state(
  p_firebase_uid text
)
returns table (
  account_id uuid,
  account_status text,
  free_trial_total integer,
  free_trial_remaining integer,
  available_balance numeric
)
language plpgsql
as $$
declare
  v_account_id uuid;
  v_account_status text;
  v_bucket app_private.free_trial_buckets%rowtype;
begin
  select a.account_id, a.status
  into v_account_id, v_account_status
  from app_private.ensure_account(p_firebase_uid) a;

  v_bucket := app_private.ensure_free_trial_bucket(v_account_id);

  return query
  select
    v_account_id,
    v_account_status,
    v_bucket.total_actions,
    v_bucket.remaining_actions,
    app_private.account_available_balance(v_account_id);
end;
$$;

create or replace function app_private.consume_free_trial_action(
  p_firebase_uid text,
  p_idempotency_key text,
  p_operation_type text default 'operation',
  p_metadata jsonb default '{}'::jsonb
)
returns table (
  account_id uuid,
  account_status text,
  free_trial_total integer,
  free_trial_remaining integer,
  available_balance numeric,
  consumed boolean
)
language plpgsql
as $$
declare
  v_account_id uuid;
  v_account_status text;
  v_bucket app_private.free_trial_buckets%rowtype;
  v_idem text;
  v_op text;
begin
  v_idem := btrim(coalesce(p_idempotency_key, ''));
  if v_idem = '' then
    raise exception 'IDEMPOTENCY_KEY_REQUIRED';
  end if;

  v_op := nullif(btrim(coalesce(p_operation_type, '')), '');
  if v_op is null then
    v_op := 'operation';
  end if;

  select a.account_id, a.status
  into v_account_id, v_account_status
  from app_private.ensure_account(p_firebase_uid) a;

  if v_account_status <> 'active' then
    raise exception 'ACCOUNT_NOT_ACTIVE';
  end if;

  perform pg_advisory_xact_lock(hashtext(v_account_id::text));
  v_bucket := app_private.ensure_free_trial_bucket(v_account_id);

  if exists (
    select 1
    from app_private.free_trial_events e
    where e.account_id = v_account_id
      and e.idempotency_key = v_idem
  ) then
    select b.*
    into v_bucket
    from app_private.free_trial_buckets b
    where b.account_id = v_account_id
    for update;

    return query
    select
      v_account_id,
      v_account_status,
      v_bucket.total_actions,
      v_bucket.remaining_actions,
      app_private.account_available_balance(v_account_id),
      false;
    return;
  end if;

  select b.*
  into v_bucket
  from app_private.free_trial_buckets b
  where b.account_id = v_account_id
  for update;

  if v_bucket.remaining_actions <= 0 then
    raise exception 'FREE_TRIAL_EXHAUSTED';
  end if;

  update app_private.free_trial_buckets
  set remaining_actions = remaining_actions - 1
  where account_id = v_account_id
  returning * into v_bucket;

  insert into app_private.free_trial_events (
    account_id,
    idempotency_key,
    operation_type,
    metadata
  )
  values (
    v_account_id,
    v_idem,
    v_op,
    coalesce(p_metadata, '{}'::jsonb)
  )
  on conflict (account_id, idempotency_key) do nothing;

  return query
  select
    v_account_id,
    v_account_status,
    v_bucket.total_actions,
    v_bucket.remaining_actions,
    app_private.account_available_balance(v_account_id),
    true;
end;
$$;

create or replace function public.app_free_trial_state(
  p_firebase_uid text
)
returns table (
  account_id uuid,
  account_status text,
  free_trial_total integer,
  free_trial_remaining integer,
  available_balance numeric
)
language sql
security definer
set search_path = app_private, public
as $$
  select * from app_private.free_trial_state(p_firebase_uid);
$$;

create or replace function public.app_consume_free_trial_action(
  p_firebase_uid text,
  p_idempotency_key text,
  p_operation_type text default 'operation',
  p_metadata jsonb default '{}'::jsonb
)
returns table (
  account_id uuid,
  account_status text,
  free_trial_total integer,
  free_trial_remaining integer,
  available_balance numeric,
  consumed boolean
)
language sql
security definer
set search_path = app_private, public
as $$
  select * from app_private.consume_free_trial_action(
    p_firebase_uid,
    p_idempotency_key,
    p_operation_type,
    p_metadata
  );
$$;

revoke all on function public.app_free_trial_state(text) from public, anon, authenticated;
revoke all on function public.app_consume_free_trial_action(text, text, text, jsonb)
  from public, anon, authenticated;

grant execute on function public.app_free_trial_state(text) to service_role;
grant execute on function public.app_consume_free_trial_action(text, text, text, jsonb)
  to service_role;
