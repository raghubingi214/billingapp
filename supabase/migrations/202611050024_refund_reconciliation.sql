create or replace function public.sales_invoice_detail(p_organization_id uuid,p_invoice_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare invoice public.sales_invoices%rowtype;paid numeric;credited numeric;refunded numeric;result jsonb;
begin
 if not private.has_role(p_organization_id,array['owner','manager','cashier','accountant']) then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
 select * into invoice from public.sales_invoices where id=p_invoice_id and organization_id=p_organization_id;
 if not found or (not private.has_role(p_organization_id,array['owner','manager','accountant']) and invoice.created_by<>auth.uid()) then raise exception using errcode='42501',message='INVOICE_NOT_FOUND';end if;
 select coalesce(sum(a.amount),0) into paid from public.payment_allocations a where a.organization_id=p_organization_id and a.invoice_id=p_invoice_id;
 select coalesce(sum(r.total),0) into credited from public.sales_returns r where r.organization_id=p_organization_id and r.original_invoice_id=p_invoice_id;
 select coalesce(sum(r.amount),0) into refunded from public.sales_refunds r where r.organization_id=p_organization_id and r.invoice_id=p_invoice_id;
 result:=to_jsonb(invoice)||jsonb_build_object('paid_total',paid,'balance_due',greatest(0,invoice.grand_total-paid-credited+refunded),'credit_total',credited,'refunded_total',refunded,'refund_due',greatest(0,paid+credited-invoice.grand_total-refunded),
 'items',coalesce((select jsonb_agg(to_jsonb(i)||jsonb_build_object('returned_qty',coalesce((select sum(r.qty) from public.sales_return_items r where r.organization_id=p_organization_id and r.original_invoice_item_id=i.id),0)) order by i.id) from public.sales_invoice_items i
 where i.organization_id=p_organization_id and i.invoice_id=p_invoice_id),'[]'::jsonb),
 'payments',coalesce((select jsonb_agg(jsonb_build_object('amount',a.amount,'method',p.method,'date',p.payment_date) order by p.created_at)
 from public.payment_allocations a join public.payments p on p.id=a.payment_id and p.organization_id=a.organization_id
 where a.organization_id=p_organization_id and a.invoice_id=p_invoice_id),'[]'::jsonb));
 return result;
end $$;
revoke all on function public.sales_invoice_detail(uuid,uuid) from public,anon;
grant execute on function public.sales_invoice_detail(uuid,uuid) to authenticated;


create or replace function public.customer_ledger(p_organization_id uuid,p_customer_id uuid,p_from date,p_to date,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare customer public.customers%rowtype;opening numeric;closing numeric;events jsonb;
begin
 if not private.has_role(p_organization_id,array['owner','manager','accountant']) then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
 if p_from is null or p_to is null or p_to<p_from then raise exception 'INVALID_DATE_RANGE';end if;
 select * into customer from public.customers where id=p_customer_id and organization_id=p_organization_id;
 if not found then raise exception 'CUSTOMER_NOT_FOUND';end if;
 with entries as (
 select i.invoice_date as date,i.grand_total as delta from public.sales_invoices i where i.organization_id=p_organization_id and i.customer_id=p_customer_id
 union all select r.return_date,-r.total from public.sales_returns r join public.sales_invoices i on i.id=r.original_invoice_id and i.organization_id=r.organization_id
 where r.organization_id=p_organization_id and i.customer_id=p_customer_id
 union all select r.refund_date,r.amount from public.sales_refunds r where r.organization_id=p_organization_id and r.customer_id=p_customer_id
 union all select p.payment_date,-p.amount from public.payments p where p.organization_id=p_organization_id and p.customer_id=p_customer_id)
 select coalesce(sum(delta) filter(where date<p_from),0),coalesce(sum(delta) filter(where date<=p_to),0)
 into opening,closing from entries;
 with entries as (
 select i.id,i.invoice_date as date,i.issued_at as created_at,'invoice'::text as type,i.invoice_number as reference,
 i.grand_total as debit,0::numeric as credit,i.grand_total as delta
 from public.sales_invoices i where i.organization_id=p_organization_id and i.customer_id=p_customer_id
 union all
 select r.id,r.return_date,r.created_at,'credit_note',r.credit_note_number,0,r.total,-r.total
 from public.sales_returns r join public.sales_invoices i on i.id=r.original_invoice_id and i.organization_id=r.organization_id
 where r.organization_id=p_organization_id and i.customer_id=p_customer_id
 union all
 select r.id,r.refund_date,r.created_at,'refund',coalesce(r.reference,r.method),r.amount,0,r.amount
 from public.sales_refunds r where r.organization_id=p_organization_id and r.customer_id=p_customer_id
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


create or replace function public.dashboard_summary(p_organization_id uuid,p_from date,p_to date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare limited boolean;sales numeric;collections numeric;outstanding numeric;low_count bigint;
begin
 if not private.has_role(p_organization_id,array['owner','manager','cashier','accountant']) then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'INVALID_DATE_RANGE';end if;
 limited:=not private.has_role(p_organization_id,array['owner','manager','accountant']);
 select coalesce(sum(i.grand_total),0) into sales from public.sales_invoices i
 where i.organization_id=p_organization_id and i.invoice_date between p_from and p_to and (not limited or i.created_by=auth.uid());
 select sales-coalesce(sum(r.total),0) into sales from public.sales_returns r join public.sales_invoices i on i.id=r.original_invoice_id and i.organization_id=r.organization_id
 where r.organization_id=p_organization_id and r.return_date between p_from and p_to and (not limited or i.created_by=auth.uid());
 select coalesce(sum(p.amount),0) into collections from public.payments p
 where p.organization_id=p_organization_id and p.payment_date between p_from and p_to and (not limited or p.created_by=auth.uid());
 select collections-coalesce(sum(r.amount),0) into collections from public.sales_refunds r
 where r.organization_id=p_organization_id and r.refund_date between p_from and p_to and
 (not limited or exists(select 1 from public.sales_invoices i where i.id=r.invoice_id and i.created_by=auth.uid()));
 select coalesce(sum(greatest(0,i.grand_total-coalesce((select sum(a.amount) from public.payment_allocations a
 where a.organization_id=p_organization_id and a.invoice_id=i.id),0)-coalesce((select sum(r.total) from public.sales_returns r where r.organization_id=p_organization_id and r.original_invoice_id=i.id),0)+coalesce((select sum(r.amount) from public.sales_refunds r where r.organization_id=p_organization_id and r.invoice_id=i.id),0))),0) into outstanding
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


create or replace function private.issue_sales_invoice(p_request_id uuid,p_organization_id uuid,p_draft_id uuid,
 p_version integer,p_expected_quote jsonb,p_due_date date,p_initial_paid numeric)
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
 if draft.customer_id is null and p_initial_paid<(quote->>'grand_total')::numeric then raise exception 'GUEST_REQUIRES_FULL_PAYMENT';end if;
 select * into customer from public.customers where id=draft.customer_id and organization_id=p_organization_id for update;
 select coalesce(sum(i.grand_total),0) into exposure from public.sales_invoices i where i.organization_id=p_organization_id and i.customer_id=customer.id;
 select exposure-coalesce(sum(a.amount),0) into exposure from public.payment_allocations a where a.organization_id=p_organization_id and a.customer_id=customer.id;
 select exposure-coalesce(sum(r.total),0) into exposure from public.sales_returns r join public.sales_invoices i on i.id=r.original_invoice_id and i.organization_id=r.organization_id where r.organization_id=p_organization_id and i.customer_id=customer.id;
 select exposure+coalesce(sum(r.amount),0) into exposure from public.sales_refunds r where r.organization_id=p_organization_id and r.customer_id=customer.id;
 if customer.credit_limit is not null and exposure+(quote->>'grand_total')::numeric-p_initial_paid>customer.credit_limit then raise exception 'CREDIT_LIMIT_EXCEEDED';end if;
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
 quote->>'document_type',today,p_due_date,draft.place_of_supply,to_jsonb(org),case when draft.customer_id is null then jsonb_build_object('name','Walk-in','state_code',draft.place_of_supply) else to_jsonb(customer) end,quote,
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
