create table public.supplier_credit_refunds(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),
 purchase_id uuid not null,supplier_id uuid not null,
 amount numeric(18,2) not null check(amount>0),
 refund_date date not null,method text not null check(method in ('cash','upi','card','bank','other')),
 reference text,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 foreign key(purchase_id,organization_id) references public.purchases(id,organization_id),
 foreign key(supplier_id,organization_id) references public.suppliers(id,organization_id),
 check(method='cash' or nullif(trim(reference),'') is not null)
);
create index supplier_credit_refunds_purchase on public.supplier_credit_refunds(purchase_id,organization_id);
create index supplier_credit_refunds_org_date on public.supplier_credit_refunds(organization_id,refund_date);
create index supplier_credit_refunds_supplier on public.supplier_credit_refunds(supplier_id,organization_id);
create index supplier_credit_refunds_actor on public.supplier_credit_refunds(created_by);
create unique index supplier_credit_refund_reference on public.supplier_credit_refunds(organization_id,method,reference)
 where reference is not null and method<>'cash';
alter table public.supplier_credit_refunds enable row level security;
revoke all on public.supplier_credit_refunds from public,anon,authenticated;
grant select on public.supplier_credit_refunds to authenticated;
create policy supplier_credit_refund_read on public.supplier_credit_refunds for select to authenticated
 using(private.has_role(organization_id,array['owner','manager','accountant']));

create function public.record_supplier_credit_refund(p_request_id uuid,p_organization_id uuid,
 p_purchase_id uuid,p_amount text,p_date date,p_method text,p_reference text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb;reply jsonb;purchase public.purchases%rowtype;
 amount_value numeric;paid numeric;returned numeric;refunded numeric;refund_id uuid:=gen_random_uuid();
begin
 perform 1 from public.organizations where id=p_organization_id for update;
 if not private.has_role(p_organization_id,array['owner','manager']) then
  raise exception using errcode='42501',message='ACCESS_DENIED';end if;
 payload:=jsonb_build_object('organization_id',p_organization_id,'purchase_id',p_purchase_id,
  'amount',p_amount,'date',p_date,'method',p_method,'reference',p_reference);
 reply:=private.replay('record_supplier_credit_refund',p_request_id,payload);
 if reply is not null then return reply;end if;
 if coalesce(p_amount,'') !~ '^[0-9]+([.][0-9]{1,2})?$' then raise exception 'INVALID_AMOUNT';end if;
 amount_value:=p_amount::numeric;
 if amount_value<=0 then raise exception 'INVALID_AMOUNT';end if;
 if p_date is null or p_date>(now() at time zone 'Asia/Kolkata')::date then raise exception 'INVALID_REFUND_DATE';end if;
 if p_method is null or p_method not in ('cash','upi','card','bank','other') or
  (p_method<>'cash' and nullif(trim(p_reference),'') is null) then raise exception 'INVALID_REFUND_METHOD';end if;
 if p_reference is not null and length(trim(p_reference))>100 then raise exception 'REFERENCE_TOO_LONG';end if;
 select * into purchase from public.purchases where id=p_purchase_id and organization_id=p_organization_id for update;
 if not found then raise exception 'PURCHASE_NOT_FOUND';end if;
 select coalesce(sum(a.amount),0) into paid from public.supplier_payment_allocations a
  where a.organization_id=p_organization_id and a.purchase_id=p_purchase_id;
 select coalesce(sum(r.total),0) into returned from public.purchase_returns r
  where r.organization_id=p_organization_id and r.purchase_id=p_purchase_id;
 select coalesce(sum(r.amount),0) into refunded from public.supplier_credit_refunds r
  where r.organization_id=p_organization_id and r.purchase_id=p_purchase_id;
 if amount_value>greatest(paid+returned-purchase.grand_total-refunded,0) then
  raise exception 'REFUND_EXCEEDS_SUPPLIER_CREDIT';end if;
 insert into public.supplier_credit_refunds(id,organization_id,purchase_id,supplier_id,amount,refund_date,
  method,reference,created_by) values(refund_id,p_organization_id,p_purchase_id,purchase.supplier_id,
  amount_value,p_date,p_method,nullif(trim(p_reference),''),auth.uid());
 insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,after_data,request_id)
 values(p_organization_id,auth.uid(),'supplier.credit_refunded','supplier_credit_refunds',refund_id,
  jsonb_build_object('purchase_id',p_purchase_id,'amount',amount_value),p_request_id);
 reply:=jsonb_build_object('refund_id',refund_id,'amount',amount_value);
 insert into private.command_receipts(actor_id,command_name,request_id,payload,response)
 values(auth.uid(),'record_supplier_credit_refund',p_request_id,payload,reply);
 return reply;
end $$;
revoke all on function public.record_supplier_credit_refund(uuid,uuid,uuid,text,date,text,text) from public,anon;
grant execute on function public.record_supplier_credit_refund(uuid,uuid,uuid,text,date,text,text) to authenticated;
create or replace function public.purchase_detail(p_organization_id uuid,p_purchase_id uuid)
returns jsonb language sql stable security invoker set search_path='' as $$
 select to_jsonb(p)||jsonb_build_object(
  'paid_total',paid.amount,
  'returned_total',returned.amount,
  'net_payable',p.grand_total-returned.amount,
  'balance_due',greatest(p.grand_total-returned.amount-paid.amount,0),
  'supplier_credit_due',greatest(paid.amount+returned.amount-p.grand_total-refunded.amount,0),
  'supplier_refunded_total',refunded.amount,
  'refunds',coalesce((select jsonb_agg(jsonb_build_object('amount',f.amount,'date',f.refund_date,
    'method',f.method,'reference',f.reference) order by f.created_at,f.id)
    from public.supplier_credit_refunds f where f.purchase_id=p.id and f.organization_id=p.organization_id),'[]'::jsonb),
  'items',coalesce((select jsonb_agg(to_jsonb(i)||jsonb_build_object(
    'returned_qty',(select coalesce(sum(ri.qty),0) from public.purchase_return_items ri
      where ri.original_purchase_item_id=i.id and ri.organization_id=i.organization_id)) order by i.id)
    from public.purchase_items i where i.purchase_id=p.id and i.organization_id=p.organization_id),'[]'::jsonb),
  'returns',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'date',r.return_date,
    'reason',r.reason,'reference',r.supplier_credit_reference,'total',r.total) order by r.created_at,r.id)
    from public.purchase_returns r where r.purchase_id=p.id and r.organization_id=p.organization_id),'[]'::jsonb),
  'payments',coalesce((select jsonb_agg(jsonb_build_object('amount',a.amount,'method',sp.method,
    'date',sp.payment_date,'reference',sp.reference) order by sp.created_at)
    from public.supplier_payment_allocations a join public.supplier_payments sp
      on sp.id=a.payment_id and sp.organization_id=a.organization_id
    where a.purchase_id=p.id and a.organization_id=p.organization_id),'[]'::jsonb))
 from public.purchases p
 cross join lateral (select coalesce(sum(a.amount),0) as amount from public.supplier_payment_allocations a
   where a.purchase_id=p.id and a.organization_id=p.organization_id) paid
 cross join lateral (select coalesce(sum(r.total),0) as amount from public.purchase_returns r
   where r.purchase_id=p.id and r.organization_id=p.organization_id) returned
 cross join lateral (select coalesce(sum(f.amount),0) as amount from public.supplier_credit_refunds f
   where f.purchase_id=p.id and f.organization_id=p.organization_id) refunded
 where p.id=p_purchase_id and p.organization_id=p_organization_id;
$$;

create or replace function public.financial_report(p_organization_id uuid,p_kind text,p_from date,p_to date,p_offset integer default 0)
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
 from public.purchases p where p.organization_id=p_organization_id and p.bill_date between p_from and p_to
 union all
 select r.id,r.return_date,coalesce(r.supplier_credit_reference,'Return '||r.id::text),'purchase_return',
 -r.taxable_amount,-r.tax_total,-r.total from public.purchase_returns r
 where r.organization_id=p_organization_id and r.return_date between p_from and p_to),
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
 from public.sales_refunds r where r.organization_id=p_organization_id and r.refund_date between p_from and p_to
 union all select f.id,f.refund_date,coalesce(f.reference,f.method),'supplier_credit_refund',f.method,f.amount
 from public.supplier_credit_refunds f where f.organization_id=p_organization_id and f.refund_date between p_from and p_to),
 page as (select * from entries order by date,id limit 50 offset greatest(0,coalesce(p_offset,0)))
 select (select coalesce(jsonb_agg(to_jsonb(page) order by date,id),'[]'::jsonb) from page),
 coalesce(sum(amount),0),count(*) into rows,total,count from entries;
 else raise exception 'INVALID_REPORT_KIND';end if;
 return jsonb_build_object('kind',p_kind,'from',p_from,'to',p_to,'currency','INR','total',total,'count',count,
 'rows',rows,'generated_at',now(),'note','Posted records only. Credits reduce sales and purchases; refunds reduce collections. Not a filed GST return.');
end $$;
revoke all on function public.financial_report(uuid,text,date,date,integer) from public,anon;
grant execute on function public.financial_report(uuid,text,date,date,integer) to authenticated;
