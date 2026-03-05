-- Fix ambiguous hold_id references in commit/refund functions.

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

  select h.*
  into v_hold
  from app_private.credit_holds h
  where h.id = p_hold_id
    and h.account_id = v_account_id
  for update;

  if v_hold.id is null then
    raise exception 'HOLD_NOT_FOUND';
  end if;

  select l.*
  into v_existing_commit
  from app_private.credit_ledger l
  where l.hold_id = v_hold.id
    and l.entry_type = 'commit'
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
    on conflict on constraint credit_ledger_account_id_idempotency_key_key do update
      set metadata = app_private.credit_ledger.metadata || excluded.metadata
    returning app_private.credit_ledger.* into v_ledger;
  exception
    when unique_violation then
      select l.*
      into v_ledger
      from app_private.credit_ledger l
      where l.hold_id = v_hold.id
        and l.entry_type = 'commit'
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

  select h.*
  into v_hold
  from app_private.credit_holds h
  where h.id = p_hold_id
    and h.account_id = v_account_id
  for update;

  if v_hold.id is null then
    raise exception 'HOLD_NOT_FOUND';
  end if;

  if v_hold.status not in ('committed', 'refunded') then
    raise exception 'HOLD_NOT_REFUNDABLE';
  end if;

  select l.*
  into v_existing_refund
  from app_private.credit_ledger l
  where l.hold_id = v_hold.id
    and l.entry_type = 'refund'
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
  on conflict on constraint credit_ledger_account_id_idempotency_key_key do update
    set metadata = app_private.credit_ledger.metadata || excluded.metadata
  returning app_private.credit_ledger.* into v_ledger;

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
