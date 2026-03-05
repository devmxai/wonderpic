-- Admin users list RPC for panel-level user management.

create or replace function public.app_admin_list_accounts(
  p_limit integer default 200,
  p_offset integer default 0
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
  free_trial_total integer,
  free_trial_remaining integer,
  updated_at timestamptz
)
language sql
security definer
set search_path = app_private, public
as $$
  with scoped_accounts as (
    select a.*
    from app_private.accounts a
    order by a.updated_at desc
    limit greatest(1, least(coalesce(p_limit, 200), 500))
    offset greatest(coalesce(p_offset, 0), 0)
  )
  select
    a.id as account_id,
    a.firebase_uid,
    a.status,
    a.email,
    a.display_name,
    app_private.account_posted_balance(a.id) as posted_balance,
    app_private.account_reserved_balance(a.id) as reserved_balance,
    app_private.account_available_balance(a.id) as available_balance,
    ft.total_actions as free_trial_total,
    ft.remaining_actions as free_trial_remaining,
    a.updated_at
  from scoped_accounts a
  left join app_private.free_trial_buckets ft on ft.account_id = a.id
  order by a.updated_at desc;
$$;

revoke all on function public.app_admin_list_accounts(integer, integer) from public, anon, authenticated;
grant execute on function public.app_admin_list_accounts(integer, integer) to service_role;
