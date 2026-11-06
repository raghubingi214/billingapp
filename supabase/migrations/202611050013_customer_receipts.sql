create table public.payments(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),
 customer_id uuid not null,amount numeric(18,2) not null check(amount>0),payment_date date not null,
 method text not null check(method in ('cash','upi','card','bank','other')),reference text,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(id,customer_id,organization_id),
 foreign key(customer_id,organization_id) references public.customers(id,organization_id),
 check(method='cash' or nullif(trim(reference),'') is not null)
);
create unique index receipt_reference on public.payments(organization_id,method,reference) where reference is not null and method<>'cash';
create table public.payment_allocations(
 organization_id uuid not null references public.organizations(id),payment_id uuid not null,customer_id uuid not null,
 invoice_id uuid not null,amount numeric(18,2) not null check(amount>0),primary key(payment_id,invoice_id),
 foreign key(payment_id,customer_id,organization_id) references public.payments(id,customer_id,organization_id),
 foreign key(invoice_id,organization_id) references public.sales_invoices(id,organization_id)
);
create index payments_customer on public.payments(customer_id,organization_id);
create index payments_org_date on public.payments(organization_id,payment_date);
create index payments_creator on public.payments(created_by);
create index allocations_invoice on public.payment_allocations(invoice_id,organization_id);
create index allocations_org on public.payment_allocations(organization_id);
alter table public.payments enable row level security;
alter table public.payment_allocations enable row level security;
revoke all on public.payments,public.payment_allocations from public,anon,authenticated;
grant select on public.payments,public.payment_allocations to authenticated;
create policy receipt_scoped_read on public.payments for select to authenticated
 using(private.has_role(organization_id,array['owner','manager','accountant']) or
 (created_by=(select auth.uid()) and private.has_role(organization_id,array['cashier'])));
create policy allocation_scoped_read on public.payment_allocations for select to authenticated
 using(exists(select 1 from public.payments p where p.id=payment_id and p.organization_id=payment_allocations.organization_id));
create function public.record_receipt(p_request_id uuid,p_organization_id uuid,p_customer_id uuid,
 p_amount text,p_date date,p_method text,p_reference text,p_allocations jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb;reply jsonb;item jsonb;invoice public.sales_invoices%rowtype;payment_id uuid:=gen_random_uuid();
 amount numeric;allocation numeric;allocated numeric:=0;paid numeric;
begin
 perform 1 from public.organizations where id=p_organization_id for update;
 if not private.has_role(p_organization_id,array['owner','manager','cashier']) then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
 payload:=jsonb_build_object('organization_id',p_organization_id,'customer_id',p_customer_id,'amount',p_amount,
 'date',p_date,'method',p_method,'reference',p_reference,'allocations',p_allocations);
 reply:=private.replay('record_receipt',p_request_id,payload);
 if reply is not null then return reply;end if;
 if p_amount is null or p_amount !~ '^[0-9]+([.][0-9]{1,2})?$' then raise exception 'INVALID_AMOUNT';end if;
 amount:=p_amount::numeric;if amount<=0 then raise exception 'INVALID_AMOUNT';end if;
 if p_date is null or p_date>(now() at time zone 'Asia/Kolkata')::date then raise exception 'INVALID_PAYMENT_DATE';end if;
 if p_method is null or p_method not in ('cash','upi','card','bank','other') or
 (p_method<>'cash' and nullif(trim(p_reference),'') is null) then raise exception 'INVALID_PAYMENT_METHOD_OR_REFERENCE';end if;
 perform 1 from public.customers where id=p_customer_id and organization_id=p_organization_id and active;
 if not found then raise exception 'CUSTOMER_NOT_FOUND';end if;
 if p_allocations is null or jsonb_typeof(p_allocations)<>'array' then raise exception 'INVALID_ALLOCATIONS';end if;
 if jsonb_array_length(p_allocations)>100 then raise exception 'INVALID_ALLOCATIONS';end if;
 if (select count(distinct value->>'invoice_id') from jsonb_array_elements(p_allocations))<>jsonb_array_length(p_allocations) then raise exception 'DUPLICATE_ALLOCATION';end if;
 for item in select value from jsonb_array_elements(p_allocations) loop
 if coalesce(item->>'amount','') !~ '^[0-9]+([.][0-9]{1,2})?$' then raise exception 'INVALID_ALLOCATION';end if;
 allocation:=(item->>'amount')::numeric;if allocation<=0 then raise exception 'INVALID_ALLOCATION';end if;
 select * into invoice from public.sales_invoices where id=(item->>'invoice_id')::uuid and organization_id=p_organization_id and customer_id=p_customer_id for update;
 if not found or (invoice.created_by<>auth.uid() and not private.has_role(p_organization_id,array['owner','manager'])) then raise exception using errcode='42501',message='INVOICE_NOT_FOUND';end if;
 select coalesce(sum(a.amount),0) into paid from public.payment_allocations a where a.organization_id=p_organization_id and a.invoice_id=invoice.id;
 if allocation>invoice.grand_total-paid then raise exception 'PAYMENT_EXCEEDS_BALANCE';end if;
 allocated:=allocated+allocation;
 end loop;
 if allocated>amount then raise exception 'ALLOCATION_EXCEEDS_RECEIPT';end if;
 insert into public.payments(id,organization_id,customer_id,amount,payment_date,method,reference,created_by)
 values(payment_id,p_organization_id,p_customer_id,amount,p_date,p_method,nullif(trim(p_reference),''),auth.uid());
 for item in select value from jsonb_array_elements(p_allocations) loop
 insert into public.payment_allocations(organization_id,payment_id,customer_id,invoice_id,amount)
 values(p_organization_id,payment_id,p_customer_id,(item->>'invoice_id')::uuid,(item->>'amount')::numeric);
 end loop;
 insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,after_data,request_id)
 values(p_organization_id,auth.uid(),'receipt.recorded','payments',payment_id,jsonb_build_object('amount',amount,'allocated',allocated),p_request_id);
 reply:=jsonb_build_object('payment_id',payment_id,'amount',amount,'allocated',allocated,'unapplied',amount-allocated);
 insert into private.command_receipts(actor_id,command_name,request_id,payload,response) values(auth.uid(),'record_receipt',p_request_id,payload,reply);
 return reply;
end $$;
revoke all on function public.record_receipt(uuid,uuid,uuid,text,date,text,text,jsonb) from public,anon;
grant execute on function public.record_receipt(uuid,uuid,uuid,text,date,text,text,jsonb) to authenticated;
create or replace function public.issue_sales_invoice(p_request_id uuid,p_organization_id uuid,p_draft_id uuid,
 p_version integer,p_expected_quote jsonb,p_due_date date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb;reply jsonb;quote jsonb;draft public.sales_drafts%rowtype;org public.organizations%rowtype;
 customer public.customers%rowtype;series public.invoice_series%rowtype;
 invoice_id uuid:=gen_random_uuid();number text;today date:=(now() at time zone 'Asia/Kolkata')::date;
 fy_start integer;fy text;line jsonb;grouped record;balance public.stock_balances%rowtype;exposure numeric;
begin
 perform 1 from public.organizations where id=p_organization_id for update;
 if not private.has_role(p_organization_id,array['owner','manager','cashier']) then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
 payload:=jsonb_build_object('organization_id',p_organization_id,'draft_id',p_draft_id,'version',p_version,'quote',p_expected_quote,'due_date',p_due_date);
 reply:=private.replay('issue_sale',p_request_id,payload);
 if reply is not null then return reply;end if;
 select * into draft from public.sales_drafts where id=p_draft_id and organization_id=p_organization_id for update;
 if not found then raise exception 'DRAFT_NOT_FOUND';end if;
 quote:=public.quote_sales_draft(p_organization_id,p_draft_id,p_version);
 if p_expected_quote is null or quote<>p_expected_quote then raise exception 'QUOTE_CHANGED';end if;
 if p_due_date is null or p_due_date<today then raise exception 'INVALID_DUE_DATE';end if;
 -- Credit-only issue in this command. Guest checkout will use atomic checkout/payment command.
 if draft.customer_id is null then raise exception 'CREDIT_CUSTOMER_REQUIRED';end if;
 select * into customer from public.customers where id=draft.customer_id and organization_id=p_organization_id for update;
 select coalesce(sum(i.grand_total),0) into exposure from public.sales_invoices i where i.organization_id=p_organization_id and i.customer_id=customer.id;
 select exposure-coalesce(sum(a.amount),0) into exposure from public.payment_allocations a where a.organization_id=p_organization_id and a.customer_id=customer.id;
 if customer.credit_limit is not null and exposure+(quote->>'grand_total')::numeric>customer.credit_limit then raise exception 'CREDIT_LIMIT_EXCEEDED';end if;
 select * into org from public.organizations where id=p_organization_id;
 fy_start:=extract(year from today)::integer;
 if extract(month from today)<4 then fy_start:=fy_start-1;end if;
 fy:=right(fy_start::text,2)||'-'||right((fy_start+1)::text,2);
 select * into series from public.invoice_series where organization_id=p_organization_id
 and doc_type=quote->>'document_type' and active order by financial_year desc,id limit 1 for update;
 if not found then raise exception 'INVOICE_SERIES_REQUIRED';end if;
 if series.financial_year<>fy then
 insert into public.invoice_series(organization_id,financial_year,doc_type,prefix)
 values(p_organization_id,fy,series.doc_type,series.prefix)
 on conflict(organization_id,doc_type,financial_year,prefix) do nothing;
 select * into series from public.invoice_series where organization_id=p_organization_id
 and financial_year=fy and doc_type=series.doc_type and prefix=series.prefix for update;
 end if;
 if series.next_seq>=999999 then raise exception 'SERIES_EXHAUSTED';end if;
 number:=series.prefix||'/'||replace(fy,'-','')||'/'||lpad(series.next_seq::text,6,'0');
 insert into public.sales_invoices(id,organization_id,draft_id,outlet_id,customer_id,series_id,invoice_number,
 document_type,invoice_date,due_date,place_of_supply,supplier_snapshot,recipient_snapshot,quote_snapshot,
 subtotal,discount_total,taxable_total,tax_total,grand_total,created_by)
 values(invoice_id,p_organization_id,draft.id,draft.outlet_id,customer.id,series.id,number,
 quote->>'document_type',today,p_due_date,draft.place_of_supply,to_jsonb(org),to_jsonb(customer),quote,
 (quote->>'subtotal')::numeric,(quote->>'discount_total')::numeric,(quote->>'taxable_total')::numeric,
 (quote->>'tax_total')::numeric,(quote->>'grand_total')::numeric,auth.uid());
 for line in select value from jsonb_array_elements(quote->'items') loop
 insert into public.sales_invoice_items(organization_id,invoice_id,product_id,snapshot,qty,unit_price,taxable_value,cgst,sgst,igst,total)
 values(p_organization_id,invoice_id,(line->>'product_id')::uuid,line,(line->>'qty')::numeric,
 (line->>'unit_price')::numeric,(line->>'taxable_value')::numeric,(line->>'cgst')::numeric,
 (line->>'sgst')::numeric,(line->>'igst')::numeric,(line->>'total')::numeric);
 end loop;
 for grouped in select (value->>'product_id')::uuid as product_id,sum((value->>'qty')::numeric) as qty
 from jsonb_array_elements(quote->'items') where value->>'type'='product' group by value->>'product_id' order by value->>'product_id' loop
 select * into balance from public.stock_balances where organization_id=p_organization_id
 and outlet_id=draft.outlet_id and product_id=grouped.product_id for update;
 if not found or balance.quantity_on_hand-balance.reserved_qty<grouped.qty then raise exception 'INSUFFICIENT_STOCK';end if;
 insert into public.stock_movements(organization_id,outlet_id,product_id,movement_type,signed_qty,before_qty,after_qty,reason,source_id,request_id,created_by)
 values(p_organization_id,draft.outlet_id,grouped.product_id,'sale',-grouped.qty,balance.quantity_on_hand,
 balance.quantity_on_hand-grouped.qty,'Sales invoice',invoice_id,p_request_id,auth.uid());
 update public.stock_balances set quantity_on_hand=quantity_on_hand-grouped.qty,version=version+1,updated_at=now()
 where organization_id=p_organization_id and outlet_id=draft.outlet_id and product_id=grouped.product_id;
 end loop;
 update public.invoice_series set next_seq=next_seq+1 where id=series.id;
 update public.sales_drafts set status='issued',updated_at=now() where id=draft.id;
 insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,after_data,request_id)
 values(p_organization_id,auth.uid(),'sale.issued','sales_invoices',invoice_id,jsonb_build_object('invoice_number',number),p_request_id);
 reply:=jsonb_build_object('invoice_id',invoice_id,'invoice_number',number,'grand_total',quote->'grand_total');
 insert into private.command_receipts(actor_id,command_name,request_id,payload,response) values(auth.uid(),'issue_sale',p_request_id,payload,reply);
 return reply;
end $$;
revoke all on function public.issue_sales_invoice(uuid,uuid,uuid,integer,jsonb,date) from public,anon;
grant execute on function public.issue_sales_invoice(uuid,uuid,uuid,integer,jsonb,date) to authenticated;


