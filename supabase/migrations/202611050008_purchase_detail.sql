create function public.purchase_detail(p_organization_id uuid,p_purchase_id uuid)
returns jsonb language sql stable security invoker set search_path='' as $$
 select to_jsonb(p)||jsonb_build_object(
 'paid_total',(select coalesce(sum(a.amount),0) from public.supplier_payment_allocations a where a.purchase_id=p.id and a.organization_id=p.organization_id),
 'balance_due',p.grand_total-(select coalesce(sum(a.amount),0) from public.supplier_payment_allocations a where a.purchase_id=p.id and a.organization_id=p.organization_id),
 'items',coalesce((select jsonb_agg(to_jsonb(i) order by i.id) from public.purchase_items i where i.purchase_id=p.id and i.organization_id=p.organization_id),'[]'::jsonb),
 'payments',coalesce((select jsonb_agg(jsonb_build_object('amount',a.amount,'method',r.method,'date',r.payment_date,'reference',r.reference) order by r.created_at)
 from public.supplier_payment_allocations a join public.supplier_payments r on r.id=a.payment_id and r.organization_id=a.organization_id
 where a.purchase_id=p.id and a.organization_id=p.organization_id),'[]'::jsonb))
 from public.purchases p where p.id=p_purchase_id and p.organization_id=p_organization_id;
$$;
revoke all on function public.purchase_detail(uuid,uuid) from public,anon;
grant execute on function public.purchase_detail(uuid,uuid) to authenticated;
