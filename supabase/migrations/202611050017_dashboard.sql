create function public.dashboard_summary(p_organization_id uuid,p_from date,p_to date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare limited boolean;sales numeric;collections numeric;outstanding numeric;low_count bigint;
begin
 if not private.has_role(p_organization_id,array['owner','manager','cashier','accountant']) then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'INVALID_DATE_RANGE';end if;
 limited:=not private.has_role(p_organization_id,array['owner','manager','accountant']);
 select coalesce(sum(i.grand_total),0) into sales from public.sales_invoices i
 where i.organization_id=p_organization_id and i.invoice_date between p_from and p_to and (not limited or i.created_by=auth.uid());
 select coalesce(sum(p.amount),0) into collections from public.payments p
 where p.organization_id=p_organization_id and p.payment_date between p_from and p_to and (not limited or p.created_by=auth.uid());
 select coalesce(sum(i.grand_total-coalesce((select sum(a.amount) from public.payment_allocations a
 where a.organization_id=p_organization_id and a.invoice_id=i.id),0)),0) into outstanding
 from public.sales_invoices i where i.organization_id=p_organization_id and (not limited or i.created_by=auth.uid());
 select count(*) into low_count from public.products p
 join public.outlets o on o.organization_id=p.organization_id and o.active
 left join public.stock_balances b on b.organization_id=p.organization_id and b.product_id=p.id and b.outlet_id=o.id
 where p.organization_id=p_organization_id and p.active and p.type='product'
 and coalesce(b.quantity_on_hand-b.reserved_qty,0)<=p.reorder_level;
 return jsonb_build_object('sales',sales,'collections',collections,'outstanding',outstanding,
 'low_stock',low_count,'from',p_from,'to',p_to,'cashier_scope',limited,'refreshed_at',now());
end $$;
revoke all on function public.dashboard_summary(uuid,date,date) from public,anon;
grant execute on function public.dashboard_summary(uuid,date,date) to authenticated;
