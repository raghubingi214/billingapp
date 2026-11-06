create function public.customer_ledger(p_organization_id uuid,p_customer_id uuid,p_from date,p_to date,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare customer public.customers%rowtype;opening numeric;closing numeric;events jsonb;
begin
 if not private.has_role(p_organization_id,array['owner','manager','accountant']) then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
 if p_from is null or p_to is null or p_to<p_from then raise exception 'INVALID_DATE_RANGE';end if;
 select * into customer from public.customers where id=p_customer_id and organization_id=p_organization_id;
 if not found then raise exception 'CUSTOMER_NOT_FOUND';end if;
 with entries as (
 select i.invoice_date as date,i.grand_total as delta from public.sales_invoices i where i.organization_id=p_organization_id and i.customer_id=p_customer_id
 union all select p.payment_date,-p.amount from public.payments p where p.organization_id=p_organization_id and p.customer_id=p_customer_id)
 select coalesce(sum(delta) filter(where date<p_from),0),coalesce(sum(delta) filter(where date<=p_to),0)
 into opening,closing from entries;
 with entries as (
 select i.id,i.invoice_date as date,i.issued_at as created_at,'invoice'::text as type,i.invoice_number as reference,
 i.grand_total as debit,0::numeric as credit,i.grand_total as delta
 from public.sales_invoices i where i.organization_id=p_organization_id and i.customer_id=p_customer_id
 union all
 select p.id,p.payment_date,p.created_at,'receipt',coalesce(p.reference,p.method),0,p.amount,-p.amount
 from public.payments p where p.organization_id=p_organization_id and p.customer_id=p_customer_id),
 running as (
 select *,sum(delta) over(order by date,created_at,id rows unbounded preceding) as balance from entries where date<=p_to),
 page as (
 select * from running where date>=p_from order by date,created_at,id limit 50 offset greatest(0,least(coalesce(p_offset,0),1000000)))
 select coalesce(jsonb_agg(to_jsonb(page) order by date,created_at,id),'[]'::jsonb) into events from page;
 return jsonb_build_object('customer_name',customer.name,'from',p_from,'to',p_to,'opening_balance',opening,
 'closing_balance',closing,'entries',events,'generated_at',now());
end $$;
revoke all on function public.customer_ledger(uuid,uuid,date,date,integer) from public,anon;
grant execute on function public.customer_ledger(uuid,uuid,date,date,integer) to authenticated;
