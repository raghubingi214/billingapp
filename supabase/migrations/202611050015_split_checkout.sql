create function private.issue_sales_invoice(p_request_id uuid,p_organization_id uuid,p_draft_id uuid,
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
 if draft.customer_id is null then raise exception 'CREDIT_CUSTOMER_REQUIRED';end if;
 select * into customer from public.customers where id=draft.customer_id and organization_id=p_organization_id for update;
 select coalesce(sum(i.grand_total),0) into exposure from public.sales_invoices i where i.organization_id=p_organization_id and i.customer_id=customer.id;
 select exposure-coalesce(sum(a.amount),0) into exposure from public.payment_allocations a where a.organization_id=p_organization_id and a.customer_id=customer.id;
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

revoke all on function private.issue_sales_invoice(uuid,uuid,uuid,integer,jsonb,date,numeric) from public,anon,authenticated;
create or replace function public.issue_sales_invoice(p_request_id uuid,p_organization_id uuid,p_draft_id uuid,
 p_version integer,p_expected_quote jsonb,p_due_date date)
returns jsonb language sql security definer set search_path='' as $$
 select private.issue_sales_invoice(p_request_id,p_organization_id,p_draft_id,p_version,p_expected_quote,p_due_date,0);
$$;
create function public.checkout_sale(p_request_id uuid,p_organization_id uuid,p_draft_id uuid,
 p_version integer,p_expected_quote jsonb,p_due_date date,p_tenders jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb;reply jsonb;quote jsonb;draft public.sales_drafts%rowtype;tender jsonb;
 total_paid numeric:=0;amount numeric;issued jsonb;index integer:=0;today date:=(now() at time zone 'Asia/Kolkata')::date;
begin
 perform 1 from public.organizations where id=p_organization_id for update;
 if not private.has_role(p_organization_id,array['owner','manager','cashier']) then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
 payload:=jsonb_build_object('organization_id',p_organization_id,'draft_id',p_draft_id,'version',p_version,
 'quote',p_expected_quote,'due_date',p_due_date,'tenders',p_tenders);
 reply:=private.replay('checkout_sale',p_request_id,payload);
 if reply is not null then return reply;end if;
 quote:=public.quote_sales_draft(p_organization_id,p_draft_id,p_version);
 if p_expected_quote is null or quote<>p_expected_quote then raise exception 'QUOTE_CHANGED';end if;
 select * into draft from public.sales_drafts where id=p_draft_id and organization_id=p_organization_id for update;
 if draft.customer_id is null then raise exception 'CUSTOMER_REQUIRED';end if;
 if p_tenders is null or jsonb_typeof(p_tenders)<>'array' then raise exception 'INVALID_TENDERS';end if;
 if jsonb_array_length(p_tenders)>10 then raise exception 'INVALID_TENDERS';end if;
 for tender in select value from jsonb_array_elements(p_tenders) loop
 if coalesce(tender->>'amount','') !~ '^[0-9]+([.][0-9]{1,2})?$' then raise exception 'INVALID_TENDER_AMOUNT';end if;
 amount:=(tender->>'amount')::numeric;
 if amount<=0 then raise exception 'INVALID_TENDER_AMOUNT';end if;
 if coalesce(tender->>'method','') not in ('cash','upi','card','bank','other') or
 (tender->>'method'<>'cash' and nullif(trim(tender->>'reference'),'') is null) then raise exception 'INVALID_TENDER_METHOD_OR_REFERENCE';end if;
 total_paid:=total_paid+amount;
 end loop;
 if total_paid>(quote->>'grand_total')::numeric then raise exception 'PAYMENT_EXCEEDS_TOTAL';end if;
 issued:=private.issue_sales_invoice(md5('checkout-issue:'||p_request_id::text)::uuid,p_organization_id,
 p_draft_id,p_version,p_expected_quote,p_due_date,total_paid);
 for tender in select value from jsonb_array_elements(p_tenders) loop
 index:=index+1;
 perform public.record_receipt(md5('checkout-receipt:'||p_request_id::text||':'||index::text)::uuid,
 p_organization_id,draft.customer_id,tender->>'amount',today,tender->>'method',tender->>'reference',
 jsonb_build_array(jsonb_build_object('invoice_id',issued->>'invoice_id','amount',tender->>'amount')));
 end loop;
 reply:=issued||jsonb_build_object('paid_total',total_paid,'balance_due',(quote->>'grand_total')::numeric-total_paid);
 insert into private.command_receipts(actor_id,command_name,request_id,payload,response)
 values(auth.uid(),'checkout_sale',p_request_id,payload,reply);
 return reply;
end $$;
revoke all on function public.checkout_sale(uuid,uuid,uuid,integer,jsonb,date,jsonb) from public,anon;
grant execute on function public.checkout_sale(uuid,uuid,uuid,integer,jsonb,date,jsonb) to authenticated;
