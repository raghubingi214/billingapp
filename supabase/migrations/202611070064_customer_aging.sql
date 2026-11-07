create function public.customer_aging(p_organization_id uuid, p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  as_of date := (now() at time zone 'Asia/Kolkata')::date;
  report jsonb;
begin
  if not private.has_role(p_organization_id,array['owner','manager','accountant']) then
    raise exception using errcode='42501', message='ACCESS_DENIED';
  end if;
  if p_offset is null or p_offset < 0 or p_offset > 100000 then
    raise exception 'INVALID_OFFSET';
  end if;
  with balances as materialized (
    select i.customer_id, as_of-i.due_date as overdue_days,
      private.invoice_outstanding(i.organization_id,i.id) as amount
    from public.sales_invoices i
    where i.organization_id=p_organization_id and i.customer_id is not null
  ), customers as (
    select customer_id,
      coalesce(sum(amount) filter (where overdue_days<=0),0) as current_due,
      coalesce(sum(amount) filter (where overdue_days between 1 and 30),0) as days_1_30,
      coalesce(sum(amount) filter (where overdue_days between 31 and 60),0) as days_31_60,
      coalesce(sum(amount) filter (where overdue_days between 61 and 90),0) as days_61_90,
      coalesce(sum(amount) filter (where overdue_days>90),0) as days_91_plus,
      sum(amount) as total
    from balances where amount>0 group by customer_id
  ), page as (
    select a.*,c.name
    from customers a join public.customers c
      on c.id=a.customer_id and c.organization_id=p_organization_id
    order by a.total desc,a.customer_id
    limit 50 offset p_offset
  )
  select jsonb_build_object(
    'as_of',as_of,'count',count(*),
    'current_due',coalesce(sum(current_due),0),
    'days_1_30',coalesce(sum(days_1_30),0),
    'days_31_60',coalesce(sum(days_31_60),0),
    'days_61_90',coalesce(sum(days_61_90),0),
    'days_91_plus',coalesce(sum(days_91_plus),0),
    'total',coalesce(sum(total),0),
    'rows',(select coalesce(jsonb_agg(to_jsonb(page) order by total desc,customer_id),'[]'::jsonb) from page)
  ) into report from customers;
  return report;
end $$;

revoke all on function public.customer_aging(uuid,integer) from public,anon;
grant execute on function public.customer_aging(uuid,integer) to authenticated;
