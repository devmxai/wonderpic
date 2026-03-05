-- Fix ambiguous account_id reference in grant_credits function.

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
  on conflict on constraint credit_ledger_account_id_idempotency_key_key do update
    set metadata = app_private.credit_ledger.metadata || excluded.metadata
  returning app_private.credit_ledger.* into v_ledger;

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
