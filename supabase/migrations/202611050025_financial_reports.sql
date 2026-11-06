create function public.financial_report(p_organization_id uuid,p_kind text,p_from date,p_to date,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;total numeric;count bigint;
begin
 if not private.has_role(p_organization_id,array['owner','accountant']) then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>3660 then raise exception 'INVALID_DATE_RANGE';end if;
 if p_kind='sales' then
 with entries as (
 select i.id,i.invoice_date as date,i.invoice_number as reference,'invoice'::text as type,
 i.taxable_total as taxable,i.tax_total as tax,i.grand_total as amount
 from public.sales_invoices i where i.organization_id=p_organization_id and i.invoice_date between p_from and p_to
 union all
 select r.id,r.return_date,r.credit_note_number,'credit_note',
 -(select coalesce(sum(ri.taxable_value),0) from public.sales_return_items ri where ri.return_id=r.id and ri.organization_id=r.organization_id),
 -(select coalesce(sum(ri.cgst+ri.sgst+ri.igst),0) from public.sales_return_items ri where ri.return_id=r.id and ri.organization_id=r.organization_id),
 -r.total from public.sales_returns r where r.organization_id=p_organization_id and r.return_date between p_from and p_to),
 page as (select * from entries order by date,id limit 50 offset greatest(0,coalesce(p_offset,0)))
 select (select coalesce(jsonb_agg(to_jsonb(page) order by date,id),'[]'::jsonb) from page),
 coalesce(sum(amount),0),count(*) into rows,total,count from entries;
 elsif p_kind='purchases' then
 with entries as (
 select p.id,p.bill_date as date,p.supplier_bill_no as reference,'purchase'::text as type,
 p.subtotal as taxable,p.tax_total as tax,p.grand_total as amount
 from public.purchases p where p.organization_id=p_organization_id and p.bill_date between p_from and p_to),
 page as (select * from entries order by date,id limit 50 offset greatest(0,coalesce(p_offset,0)))
 select (select coalesce(jsonb_agg(to_jsonb(page) order by date,id),'[]'::jsonb) from page),
 coalesce(sum(amount),0),count(*) into rows,total,count from entries;
 elsif p_kind='payments' then
 with entries as (
 select p.id,p.payment_date as date,coalesce(p.reference,p.method) as reference,'customer_receipt'::text as type,
 p.method,p.amount from public.payments p where p.organization_id=p_organization_id and p.payment_date between p_from and p_to
 union all select p.id,p.payment_date,coalesce(p.reference,p.method),'supplier_payment',p.method,-p.amount
 from public.supplier_payments p where p.organization_id=p_organization_id and p.payment_date between p_from and p_to
 union all select r.id,r.refund_date,coalesce(r.reference,r.method),'customer_refund',r.method,-r.amount
 from public.sales_refunds r where r.organization_id=p_organization_id and r.refund_date between p_from and p_to),
 page as (select * from entries order by date,id limit 50 offset greatest(0,coalesce(p_offset,0)))
 select (select coalesce(jsonb_agg(to_jsonb(page) order by date,id),'[]'::jsonb) from page),
 coalesce(sum(amount),0),count(*) into rows,total,count from entries;
 else raise exception 'INVALID_REPORT_KIND';end if;
 return jsonb_build_object('kind',p_kind,'from',p_from,'to',p_to,'currency','INR','total',total,'count',count,
 'rows',rows,'generated_at',now(),'note','Posted records only. Credits reduce sales; refunds reduce collections. Not a filed GST return.');
end $$;
revoke all on function public.financial_report(uuid,text,date,date,integer) from public,anon;
grant execute on function public.financial_report(uuid,text,date,date,integer) to authenticated;
