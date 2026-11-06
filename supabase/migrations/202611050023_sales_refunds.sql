create table public.sales_refunds(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),
 invoice_id uuid not null,customer_id uuid,amount numeric(18,2) not null check(amount>0),
 refund_date date not null,method text not null check(method in ('cash','upi','card','bank','other')),
 reference text,reason text not null check(length(trim(reason)) between 3 and 500),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 foreign key(invoice_id,organization_id) references public.sales_invoices(id,organization_id),
 foreign key(customer_id,organization_id) references public.customers(id,organization_id),
 check(method='cash' or nullif(trim(reference),'') is not null)
);
create unique index refund_reference on public.sales_refunds(organization_id,method,reference) where reference is not null and method<>'cash';
create index refunds_invoice on public.sales_refunds(invoice_id,organization_id);
create index refunds_customer on public.sales_refunds(customer_id,organization_id);
create index refunds_org_date on public.sales_refunds(organization_id,refund_date);
create index refunds_actor on public.sales_refunds(created_by);
alter table public.sales_refunds enable row level security;
revoke all on public.sales_refunds from public,anon,authenticated;
grant select on public.sales_refunds to authenticated;
create policy refund_finance_read on public.sales_refunds for select to authenticated
 using(private.has_role(organization_id,array['owner','manager','accountant']));
create function public.refund_sale(p_request_id uuid,p_organization_id uuid,p_invoice_id uuid,
 p_amount text,p_method text,p_reference text,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb;reply jsonb;invoice public.sales_invoices%rowtype;amount numeric;paid numeric;credited numeric;refunded numeric;
 refund_id uuid:=gen_random_uuid();
begin
 perform 1 from public.organizations where id=p_organization_id for update;
 if not private.has_role(p_organization_id,array['owner']) then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
 payload:=jsonb_build_object('organization_id',p_organization_id,'invoice_id',p_invoice_id,'amount',p_amount,
 'method',p_method,'reference',p_reference,'reason',p_reason);
 reply:=private.replay('refund_sale',p_request_id,payload);if reply is not null then return reply;end if;
 if p_amount is null or p_amount !~ '^[0-9]+([.][0-9]{1,2})?$' then raise exception 'INVALID_AMOUNT';end if;
 amount:=p_amount::numeric;if amount<=0 then raise exception 'INVALID_AMOUNT';end if;
 if p_method is null or p_method not in ('cash','upi','card','bank','other') or
 (p_method<>'cash' and nullif(trim(p_reference),'') is null) then raise exception 'INVALID_METHOD_OR_REFERENCE';end if;
 if p_reason is null or length(trim(p_reason)) not between 3 and 500 then raise exception 'REASON_REQUIRED';end if;
 select * into invoice from public.sales_invoices where id=p_invoice_id and organization_id=p_organization_id for update;
 if not found then raise exception 'INVOICE_NOT_FOUND';end if;
 select coalesce(sum(a.amount),0) into paid from public.payment_allocations a where a.organization_id=p_organization_id and a.invoice_id=p_invoice_id;
 select coalesce(sum(r.total),0) into credited from public.sales_returns r where r.organization_id=p_organization_id and r.original_invoice_id=p_invoice_id;
 select coalesce(sum(r.amount),0) into refunded from public.sales_refunds r where r.organization_id=p_organization_id and r.invoice_id=p_invoice_id;
 if amount>greatest(0,paid+credited-invoice.grand_total-refunded) then raise exception 'REFUND_EXCEEDS_CREDIT';end if;
 insert into public.sales_refunds(id,organization_id,invoice_id,customer_id,amount,refund_date,method,reference,reason,created_by)
 values(refund_id,p_organization_id,p_invoice_id,invoice.customer_id,amount,(now() at time zone 'Asia/Kolkata')::date,p_method,
 nullif(trim(p_reference),''),trim(p_reason),auth.uid());
 insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,after_data,request_id)
 values(p_organization_id,auth.uid(),'sale.refunded','sales_refunds',refund_id,jsonb_build_object('amount',amount),p_request_id);
 reply:=jsonb_build_object('refund_id',refund_id,'amount',amount);
 insert into private.command_receipts(actor_id,command_name,request_id,payload,response) values(auth.uid(),'refund_sale',p_request_id,payload,reply);
 return reply;
end $$;
revoke all on function public.refund_sale(uuid,uuid,uuid,text,text,text,text) from public,anon;
grant execute on function public.refund_sale(uuid,uuid,uuid,text,text,text,text) to authenticated;
