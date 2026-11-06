create function public.sales_customer_choices(p_organization_id uuid,p_query text default '',p_offset integer default 0)
returns table(id uuid,name text,state_code text) language plpgsql stable security definer set search_path='' as $$
begin
 if not private.has_role(p_organization_id,array['owner','manager','cashier']) then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
 return query select c.id,c.name,c.state_code from public.customers c
 where c.organization_id=p_organization_id and c.active and position(lower(coalesce(p_query,'')) in lower(c.name))>0
 order by c.name,c.id limit 50 offset greatest(0,least(coalesce(p_offset,0),1000000));
end $$;
revoke all on function public.sales_customer_choices(uuid,text,integer) from public,anon;
grant execute on function public.sales_customer_choices(uuid,text,integer) to authenticated;
create function public.sales_invoice_detail(p_organization_id uuid,p_invoice_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare invoice public.sales_invoices%rowtype;paid numeric;result jsonb;
begin
 if not private.has_role(p_organization_id,array['owner','manager','cashier','accountant']) then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
 select * into invoice from public.sales_invoices where id=p_invoice_id and organization_id=p_organization_id;
 if not found or (not private.has_role(p_organization_id,array['owner','manager','accountant']) and invoice.created_by<>auth.uid()) then raise exception using errcode='42501',message='INVOICE_NOT_FOUND';end if;
 select coalesce(sum(a.amount),0) into paid from public.payment_allocations a where a.organization_id=p_organization_id and a.invoice_id=p_invoice_id;
 result:=to_jsonb(invoice)||jsonb_build_object('paid_total',paid,'balance_due',invoice.grand_total-paid,
 'items',coalesce((select jsonb_agg(to_jsonb(i) order by i.id) from public.sales_invoice_items i
 where i.organization_id=p_organization_id and i.invoice_id=p_invoice_id),'[]'::jsonb),
 'payments',coalesce((select jsonb_agg(jsonb_build_object('amount',a.amount,'method',p.method,'date',p.payment_date) order by p.created_at)
 from public.payment_allocations a join public.payments p on p.id=a.payment_id and p.organization_id=a.organization_id
 where a.organization_id=p_organization_id and a.invoice_id=p_invoice_id),'[]'::jsonb));
 return result;
end $$;
revoke all on function public.sales_invoice_detail(uuid,uuid) from public,anon;
grant execute on function public.sales_invoice_detail(uuid,uuid) to authenticated;
