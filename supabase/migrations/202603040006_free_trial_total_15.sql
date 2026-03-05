-- Set free trial total to 15 globally (existing + new accounts).

alter table app_private.free_trial_buckets
  alter column total_actions set default 15,
  alter column remaining_actions set default 15;

-- Keep currently consumed usage, but cap to new total.
update app_private.free_trial_buckets
set total_actions = 15,
    remaining_actions = least(greatest(remaining_actions, 0), 15),
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
    15,
    15
  )
  on conflict (account_id) do update
    set total_actions = 15,
        remaining_actions = least(greatest(app_private.free_trial_buckets.remaining_actions, 0), 15),
        updated_at = timezone('utc', now())
  returning * into v_bucket;

  return v_bucket;
end;
$$;
