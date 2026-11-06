-- Draft: deploy only after subscription provisioning and tests are ready.
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
 perform private.require_entitlement(p_organization_id,'invoice');
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

create or replace function public.onboard_organization(
  p_request_id uuid,p_name text,p_legal_name text,p_state_code text,
  p_address jsonb,p_tax_regime text,p_gstin text,p_prefix text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  uid uuid:=auth.uid(); org_id uuid; outlet_id uuid; reply jsonb; payload jsonb;
  fy_start integer; fy text; document_type text;
begin
  payload:=jsonb_build_object('name',p_name,'legal_name',p_legal_name,'state',p_state_code,'address',p_address,'tax_regime',p_tax_regime,'gstin',p_gstin,'prefix',p_prefix);
  reply:=private.replay('onboard',p_request_id,payload);
  if reply is not null then
    if not private.has_role((reply->>'organization_id')::uuid,array['owner']) then raise exception using errcode='42501',message='ACCESS_DENIED'; end if;
    return reply;
  end if;
  if nullif(trim(p_name),'') is null or length(trim(p_name))>160 or nullif(trim(p_legal_name),'') is null or length(trim(p_legal_name))>200 then
    raise exception using errcode='22023',message='INVALID_BUSINESS_NAME';
  end if;
  if p_state_code is null or p_state_code !~ '^[0-9]{2}$' or p_state_code::int not between 1 and 38 then
    raise exception using errcode='22023',message='INVALID_STATE';
  end if;
  if p_address is null or jsonb_typeof(p_address)<>'object' or length(p_address::text)>4000
    or nullif(trim(p_address->>'line1'),'') is null or nullif(trim(p_address->>'city'),'') is null
    or coalesce(p_address->>'postal_code','') !~ '^[1-9][0-9]{5}$' then
    raise exception using errcode='22023',message='INVALID_ADDRESS';
  end if;
  if p_tax_regime is null or p_tax_regime not in ('unregistered','regular','composition') then
    raise exception using errcode='22023',message='INVALID_TAX_REGIME';
  end if;
  if p_prefix is null or p_prefix !~ '^[A-Z0-9]{1,4}$' then raise exception using errcode='22023',message='INVALID_PREFIX'; end if;
  if p_tax_regime='unregistered' and nullif(trim(p_gstin),'') is not null then
    raise exception using errcode='22023',message='UNREGISTERED_GSTIN_NOT_ALLOWED';
  end if;
  if p_tax_regime<>'unregistered' and (p_gstin is null or p_gstin !~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$' or left(p_gstin,2)<>p_state_code) then
    raise exception using errcode='22023',message='INVALID_GSTIN';
  end if;
  insert into public.profiles(user_id) values(uid) on conflict(user_id) do nothing;
  insert into public.organizations(name,legal_name,state_code,address,tax_regime,gstin,created_by)
  values(trim(p_name),trim(p_legal_name),p_state_code,p_address,p_tax_regime,nullif(trim(p_gstin),''),uid) returning id into org_id;
  perform private.provision_trial(org_id);
  insert into public.organization_members(organization_id,user_id,role) values(org_id,uid,'owner');
  insert into public.outlets(organization_id,name,code,state_code,address,is_default)
  values(org_id,trim(p_name),'MAIN',p_state_code,p_address,true) returning id into outlet_id;
  insert into public.business_settings(organization_id) values(org_id);
  fy_start:=extract(year from now() at time zone 'Asia/Kolkata')::integer;
  if extract(month from now() at time zone 'Asia/Kolkata')<4 then fy_start:=fy_start-1; end if;
  fy:=right(fy_start::text,2)||'-'||right((fy_start+1)::text,2);
  document_type:=case p_tax_regime when 'regular' then 'tax_invoice' when 'composition' then 'bill_of_supply' else 'commercial_invoice' end;
  insert into public.invoice_series(organization_id,financial_year,doc_type,prefix) values(org_id,fy,document_type,p_prefix);
  insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,after_data,request_id)
  values(org_id,uid,'organization.created','organizations',org_id,jsonb_build_object('name',trim(p_name),'tax_regime',p_tax_regime),p_request_id);
  reply:=jsonb_build_object('organization_id',org_id,'outlet_id',outlet_id);
  insert into private.command_receipts(actor_id,command_name,request_id,payload,response) values(uid,'onboard',p_request_id,payload,reply);
  return reply;
end $$;
