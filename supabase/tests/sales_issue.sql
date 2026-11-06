-- Run with a privileged development connection. Everything is rolled back.
-- These fixtures simulate Supabase JWT identity and authenticated database role.
begin;
create temporary table foundation_test_context (
  label text primary key, id uuid, data jsonb
) on commit drop;
grant select,insert,update on foundation_test_context to authenticated;
insert into foundation_test_context(label,id) values
 ('owner_a',gen_random_uuid()),('owner_b',gen_random_uuid()),
 ('staff',gen_random_uuid()),('outsider',gen_random_uuid()),
 ('request_a',gen_random_uuid()),('request_b',gen_random_uuid());
insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,aud,role)
select id,label||'.'||id::text||'@example.invalid',now(),'{}','{}','authenticated','authenticated'
from foundation_test_context where label in ('owner_a','owner_b','staff','outsider');
set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$
declare response jsonb; repeated jsonb; req uuid;
begin
  select id into req from foundation_test_context where label='request_a';
  response:=public.onboard_organization(req,'Shop A','Shop A Legal','36',
    '{"line1":"1 Test Street","city":"Hyderabad","postal_code":"500001"}','unregistered',null,'INV');
  repeated:=public.onboard_organization(req,'Shop A','Shop A Legal','36',
    '{"line1":"1 Test Street","city":"Hyderabad","postal_code":"500001"}','unregistered',null,'INV');
  if response<>repeated then raise exception 'FAIL: retry returned a different organization'; end if;
  if (select count(*) from public.organizations)<>1 then raise exception 'FAIL: onboarding duplicate'; end if;
  if (select count(*) from public.organization_members)<>1 then raise exception 'FAIL: owner membership missing/duplicated'; end if;
  if (select role from public.organization_members)<>'owner' then raise exception 'FAIL: owner role'; end if;
  if (select count(*) from public.outlets)<>1 or (select count(*) from public.invoice_series)<>1
    or (select count(*) from public.business_settings)<>1 or (select count(*) from public.audit_events)<>1 then
    raise exception 'FAIL: atomic onboarding objects missing/duplicated';
  end if;
  insert into foundation_test_context(label,id,data) values('org_a',(response->>'organization_id')::uuid,response);
  begin
    perform public.onboard_organization(req,'CHANGED','Shop A Legal','36',
      '{"line1":"1 Test Street","city":"Hyderabad","postal_code":"500001"}','unregistered',null,'INV');
    raise exception 'FAIL: changed payload accepted for existing request key';
  exception when invalid_parameter_value then
    if sqlerrm<>'IDEMPOTENCY_CONFLICT' then raise; end if;
  end;
  begin
    perform public.onboard_organization(gen_random_uuid(),'Bad','Bad','36','{}','unregistered',null,'INV');
    raise exception 'FAIL: empty address accepted';
  exception when invalid_parameter_value then
    if sqlerrm<>'INVALID_ADDRESS' then raise; end if;
  end;
  begin
    perform public.onboard_organization(gen_random_uuid(),'Bad','Bad','36',
      '{"line1":"1 Test Street","city":"Hyderabad","postal_code":"500001"}','regular',null,'INV');
    raise exception 'FAIL: registered merchant without GSTIN accepted';
  exception when invalid_parameter_value then
    if sqlerrm<>'INVALID_GSTIN' then raise; end if;
  end;
  begin
    update public.organization_members set role='owner';
    raise exception 'FAIL: direct membership write allowed';
  exception when insufficient_privilege then null;
  end;
  begin
    delete from public.audit_events;
    raise exception 'FAIL: direct audit delete allowed';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_b'),true);
do $$
declare response jsonb;
begin
  if exists(select 1 from public.organizations) or exists(select 1 from public.outlets)
     or exists(select 1 from public.organization_members) or exists(select 1 from public.audit_events)
     or exists(select 1 from public.business_settings) or exists(select 1 from public.invoice_series) then
    raise exception 'FAIL: cross-tenant read before onboarding';
  end if;
  response:=public.onboard_organization((select id from foundation_test_context where label='request_b'),
    'Shop B','Shop B Legal','29','{"line1":"2 Test Street","city":"Bengaluru","postal_code":"560001"}',
    'unregistered',null,'INV');
  insert into foundation_test_context(label,id,data) values('org_b',(response->>'organization_id')::uuid,response);
  if (select count(*) from public.organizations)<>1 then raise exception 'FAIL: cross-tenant org visibility'; end if;
  if exists(select 1 from public.organizations where name='Shop A') then raise exception 'FAIL: Org B can read Org A'; end if;
  begin
    perform public.invite_member(gen_random_uuid(),(select id from foundation_test_context where label='org_a'),'intruder@example.invalid','manager');
    raise exception 'FAIL: cross-org invitation accepted';
  exception when insufficient_privilege then
    if sqlerrm<>'ACCESS_DENIED' then raise; end if;
  end;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$
declare response jsonb; staff_email text; req uuid:=gen_random_uuid();
begin
  select 'staff.'||id::text||'@example.invalid' into staff_email from foundation_test_context where label='staff';
  response:=public.invite_member(req,(select id from foundation_test_context where label='org_a'),staff_email,'cashier');
  if response<>public.invite_member(req,(select id from foundation_test_context where label='org_a'),staff_email,'cashier') then
    raise exception 'FAIL: invitation retry mismatch';
  end if;
  insert into foundation_test_context(label,id) values('invitation',(response->>'invitation_id')::uuid);
  if (select count(*) from public.organization_invitations)<>1 then raise exception 'FAIL: duplicate invitation'; end if;
  begin
    perform public.invite_member(gen_random_uuid(),(select id from foundation_test_context where label='org_a'),'other@example.invalid','owner');
    raise exception 'FAIL: owner invitation accepted';
  exception when invalid_parameter_value then
    if sqlerrm<>'INVALID_ROLE' then raise; end if;
  end;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='outsider'),true);
do $$
begin
  if exists(select 1 from public.organization_invitations) then raise exception 'FAIL: outsider sees invite'; end if;
  begin
    perform public.accept_invitation((select id from foundation_test_context where label='invitation'));
    raise exception 'FAIL: outsider accepted another email invitation';
  exception when insufficient_privilege then
    if sqlerrm<>'INVITATION_UNAVAILABLE' then raise; end if;
  end;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='staff'),true);
do $$
declare response jsonb; member_id uuid;
begin
  if (select count(*) from public.organization_invitations)<>1 then raise exception 'FAIL: recipient cannot see own invitation'; end if;
  response:=public.accept_invitation((select id from foundation_test_context where label='invitation'));
  if response<>public.accept_invitation((select id from foundation_test_context where label='invitation')) then raise exception 'FAIL: invitation accept retry'; end if;
  select id into member_id from public.organization_members where user_id=auth.uid();
  insert into foundation_test_context(label,id) values('staff_member',member_id);
  if (select count(*) from public.organizations)<>1 or (select count(*) from public.organization_members)<>1 then
    raise exception 'FAIL: cashier membership visibility';
  end if;
  if exists(select 1 from public.audit_events) then raise exception 'FAIL: cashier sees financial audit'; end if;
  begin
    perform public.update_member(gen_random_uuid(),(select id from foundation_test_context where label='org_a'),member_id,'manager','active');
    raise exception 'FAIL: cashier self-promotion';
  exception when insufficient_privilege then
    if sqlerrm<>'ACCESS_DENIED' then raise; end if;
  end;
  begin
    perform public.invite_member(gen_random_uuid(),(select id from foundation_test_context where label='org_a'),'x@example.invalid','manager');
    raise exception 'FAIL: cashier can invite';
  exception when insufficient_privilege then
    if sqlerrm<>'ACCESS_DENIED' then raise; end if;
  end;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$
begin
  if (select count(*) from public.organization_members)<>2 then raise exception 'FAIL: owner cannot see team'; end if;
  perform public.update_member(gen_random_uuid(),(select id from foundation_test_context where label='org_a'),
    (select id from foundation_test_context where label='staff_member'),'cashier','revoked');
end $$;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='staff'),true);
do $$
begin
  if exists(select 1 from public.organizations) or exists(select 1 from public.organization_members)
     or exists(select 1 from public.outlets) or exists(select 1 from public.invoice_series)
     or exists(select 1 from public.business_settings) then raise exception 'FAIL: revoked staff retains access'; end if;
  begin
    perform public.accept_invitation((select id from foundation_test_context where label='invitation'));
    raise exception 'FAIL: revoked staff reactivated through consumed invite';
  exception when insufficient_privilege then
    if sqlerrm<>'ACCESS_DENIED' then raise; end if;
  end;
end $$;
select set_config('request.jwt.claim.sub','',true);
do $$
begin
  if exists(select 1 from public.organizations) then raise exception 'FAIL: absent JWT sees org'; end if;
  begin
    perform public.onboard_organization(gen_random_uuid(),'No Auth','No Auth','36',
      '{"line1":"1 Test Street","city":"Hyderabad","postal_code":"500001"}','unregistered',null,'INV');
    raise exception 'FAIL: absent JWT onboarding allowed';
  exception when insufficient_privilege then
    if sqlerrm<>'AUTH_REQUIRED' then raise; end if;
  end;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$
declare org uuid; product jsonb; retried jsonb; req uuid:=gen_random_uuid(); input jsonb;
begin
 select id into org from public.organizations limit 1;
 input:='{"name":"Rice","type":"product","sku":"RICE","unit":"kg","sale_price":"50.25","purchase_price":"40.00","tax_percent":"5","reorder_level":"2.500"}';
 product:=public.save_product(req,org,null,null,input);
 retried:=public.save_product(req,org,null,null,input);
 if product<>retried or (select count(*) from public.products)<>1 then raise exception 'FAIL catalog retry'; end if;
 begin
 perform public.save_product(gen_random_uuid(),org,null,null,input);
 raise exception 'FAIL duplicate sku allowed';
 exception when unique_violation then null; end;
 begin
 perform public.save_product(gen_random_uuid(),org,(product->>'id')::uuid,0,input);
 raise exception 'FAIL stale version allowed';
 exception when raise_exception then if sqlerrm<>'PRODUCT_VERSION_CONFLICT' then raise; end if; end;
 begin
 perform public.save_product(gen_random_uuid(),org,null,null,input||'{"sku":"OTHER","sale_price":"1.001"}');
 raise exception 'FAIL precision allowed';
 exception when raise_exception then if sqlerrm<>'INVALID_DECIMAL' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_b'),true);
do $$ begin
 if exists(select 1 from public.products) then raise exception 'FAIL cross tenant catalog'; end if;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$
declare org uuid; outlet uuid; product uuid; req uuid:=gen_random_uuid(); first_reply jsonb; second_reply jsonb;
begin
 select id into org from public.organizations limit 1;
 select id into outlet from public.outlets where organization_id=org limit 1;
 select id into product from public.products where organization_id=org limit 1;
 first_reply:=public.post_stock_count(req,org,outlet,product,1,'10','Opening count');
 second_reply:=public.post_stock_count(req,org,outlet,product,1,'10','Opening count');
 if first_reply<>second_reply or (select count(*) from public.stock_movements)<>1 then raise exception 'FAIL stock retry'; end if;
 perform public.post_stock_count(gen_random_uuid(),org,outlet,product,2,'7','Recount');
 if (select quantity_on_hand from public.stock_balances)<>7 or (select sum(signed_qty) from public.stock_movements)<>7 then raise exception 'FAIL stock reconciliation'; end if;
 begin
 perform public.post_stock_count(gen_random_uuid(),org,outlet,product,2,'8','Stale count');
 raise exception 'FAIL stale stock accepted';
 exception when raise_exception then if sqlerrm<>'STOCK_VERSION_CONFLICT' then raise; end if; end;
 begin
 update public.stock_balances set quantity_on_hand=99;
 raise exception 'FAIL direct balance mutation';
 exception when insufficient_privilege then null; end;
 begin
 delete from public.stock_movements;
 raise exception 'FAIL ledger deletion';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_b'),true);
do $$ begin
 if exists(select 1 from public.stock_movements) or exists(select 1 from public.stock_balances) then raise exception 'FAIL cross tenant stock'; end if;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$
declare org uuid; outlet uuid;
begin
 select id into org from public.organizations limit 1;
 select id into outlet from public.outlets where organization_id=org limit 1;
 if (select count(*) from public.inventory_positions(org,outlet,0,false))<>1 then raise exception 'FAIL inventory query'; end if;
 if exists(select 1 from public.inventory_positions(org,outlet,0,true)) then raise exception 'FAIL false low stock alert'; end if;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$
declare org uuid; req uuid:=gen_random_uuid(); supplier jsonb; data jsonb;
begin
 select id into org from public.organizations limit 1;
 data:='{"name":"Supply Co","phone":"12345","email":"vendor@example.invalid","address":"Market Road","payment_terms_days":"30","opening_balance":"125.50"}';
 supplier:=public.save_supplier(req,org,null,null,data);
 if supplier<>public.save_supplier(req,org,null,null,data) or (select count(*) from public.suppliers)<>1 then raise exception 'FAIL supplier retry'; end if;
 begin
 perform public.save_supplier(gen_random_uuid(),org,(supplier->>'id')::uuid,1,data||'{"opening_balance":"126.50"}');
 raise exception 'FAIL altered opening balance';
 exception when raise_exception then if sqlerrm<>'OPENING_BALANCE_IMMUTABLE' then raise; end if; end;
 begin
 perform public.save_supplier(gen_random_uuid(),org,(supplier->>'id')::uuid,0,data);
 raise exception 'FAIL stale supplier update';
 exception when raise_exception then if sqlerrm<>'SUPPLIER_VERSION_CONFLICT' then raise; end if; end;
 begin
 delete from public.suppliers;
 raise exception 'FAIL direct supplier delete';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_b'),true);
do $$ begin
 if exists(select 1 from public.suppliers) then raise exception 'FAIL cross tenant supplier'; end if;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$
declare org uuid; outlet uuid; product uuid; supplier uuid; req uuid:=gen_random_uuid(); lines jsonb; reply jsonb;
begin
 select id into org from public.organizations limit 1;
 select id into outlet from public.outlets where organization_id=org limit 1;
 select id into product from public.products where organization_id=org limit 1;
 select id into supplier from public.suppliers where organization_id=org limit 1;
 lines:=jsonb_build_array(jsonb_build_object('product_id',product,'qty','10','unit_cost','40.25','tax_percent','5'));
 reply:=public.receive_purchase(req,org,outlet,supplier,'BILL-1',current_date,lines);
 if reply<>public.receive_purchase(req,org,outlet,supplier,'BILL-1',current_date,lines) then raise exception 'FAIL purchase retry'; end if;
 if (select count(*) from public.purchases)<>1 or (select count(*) from public.purchase_items)<>1 then raise exception 'FAIL duplicate purchase'; end if;
 if (reply->>'grand_total')::numeric<>422.63 then raise exception 'FAIL purchase total'; end if;
 if (select quantity_on_hand from public.stock_balances)<>17 then raise exception 'FAIL stock increment'; end if;
 if (select sum(signed_qty) from public.stock_movements)<>17 then raise exception 'FAIL purchase ledger reconciliation'; end if;
 begin
 perform public.receive_purchase(gen_random_uuid(),org,outlet,supplier,'BILL-1',current_date,lines);
 raise exception 'FAIL duplicate vendor bill';
 exception when unique_violation then null; end;
 if (select quantity_on_hand from public.stock_balances)<>17 then raise exception 'FAIL duplicate bill changed stock'; end if;
 begin
 delete from public.purchases;
 raise exception 'FAIL purchase delete allowed';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_b'),true);
do $$ begin
 if exists(select 1 from public.purchases) or exists(select 1 from public.purchase_items) then raise exception 'FAIL cross tenant purchase'; end if;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$
declare org uuid;supplier uuid;purchase uuid;req uuid:=gen_random_uuid();allocations jsonb;reply jsonb;
begin
 select organization_id,supplier_id,id into org,supplier,purchase from public.purchases limit 1;
 allocations:=jsonb_build_array(jsonb_build_object('purchase_id',purchase,'amount','100.00'));
 reply:=public.pay_supplier(req,org,supplier,current_date,'upi','REF-ONE',allocations);
 if reply<>public.pay_supplier(req,org,supplier,current_date,'upi','REF-ONE',allocations) then raise exception 'FAIL payment retry'; end if;
 if (select sum(amount) from public.supplier_payment_allocations)<>100 or (select count(*) from public.supplier_payments)<>1 then raise exception 'FAIL duplicate payment'; end if;
 begin
 perform public.pay_supplier(gen_random_uuid(),org,supplier,current_date,'cash',null,
 jsonb_build_array(jsonb_build_object('purchase_id',purchase,'amount','400')));
 raise exception 'FAIL overpayment';
 exception when raise_exception then if sqlerrm<>'PAYMENT_EXCEEDS_BALANCE' then raise; end if; end;
 begin
 perform public.pay_supplier(gen_random_uuid(),org,supplier,current_date,'upi','REF-ONE',allocations);
 raise exception 'FAIL duplicate reference';
 exception when unique_violation then null; end;
 if (select sum(amount) from public.supplier_payment_allocations)<>100 then raise exception 'FAIL rejected payment changed allocations'; end if;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_b'),true);
do $$ begin
 if exists(select 1 from public.supplier_payments) or exists(select 1 from public.supplier_payment_allocations) then raise exception 'FAIL payment tenant leakage'; end if;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$
declare purchase public.purchases%rowtype; detail jsonb;
begin
 select * into purchase from public.purchases limit 1;
 detail:=public.purchase_detail(purchase.organization_id,purchase.id);
 if (detail->>'paid_total')::numeric<>100 or (detail->>'balance_due')::numeric<>322.63 then raise exception 'FAIL purchase detail balances'; end if;
 if jsonb_array_length(detail->'items')<>1 or jsonb_array_length(detail->'payments')<>1 then raise exception 'FAIL purchase detail history'; end if;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$
declare org uuid;req uuid:=gen_random_uuid();data jsonb;customer jsonb;
begin
 select id into org from public.organizations limit 1;
 data:='{"name":"Customer A","state_code":"36","credit_limit":"1000.00","billing_address":"Hyderabad"}';
 customer:=public.save_customer(req,org,null,null,data);
 if customer<>public.save_customer(req,org,null,null,data) or (select count(*) from public.customers)<>1 then raise exception 'FAIL customer retry'; end if;
 begin
 perform public.save_customer(gen_random_uuid(),org,(customer->>'id')::uuid,0,data);
 raise exception 'FAIL stale customer update';
 exception when raise_exception then if sqlerrm<>'CUSTOMER_VERSION_CONFLICT' then raise; end if; end;
 begin
 perform public.save_customer(gen_random_uuid(),org,null,null,data||'{"credit_limit":"1.001"}');
 raise exception 'FAIL credit precision';
 exception when raise_exception then if sqlerrm<>'INVALID_CREDIT_LIMIT' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_b'),true);
do $$ begin
 if exists(select 1 from public.customers) then raise exception 'FAIL cross tenant customer'; end if;
end $$;
reset role;

do $$
declare line jsonb;
begin
 line:=private.calculate_sale_line(2,500,18,false,'percent',10,false);
 if (line->>'total')::numeric<>1062 or (line->>'cgst')::numeric<>81 or (line->>'sgst')::numeric<>81 then raise exception 'FAIL documented tax example';end if;
 line:=private.calculate_sale_line(1,118,18,true,'fixed',0,true);
 if (line->>'taxable_value')::numeric<>100 or (line->>'igst')::numeric<>18 then raise exception 'FAIL inclusive interstate';end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$
declare org uuid;outlet uuid;product uuid;customer uuid;req uuid:=gen_random_uuid();items jsonb;draft jsonb;stock numeric;
begin
 select id into org from public.organizations limit 1;
 select id into outlet from public.outlets where organization_id=org limit 1;
 select id into product from public.products where organization_id=org limit 1;
 select id into customer from public.customers where organization_id=org limit 1;
 select quantity_on_hand into stock from public.stock_balances limit 1;
 items:=jsonb_build_array(jsonb_build_object('product_id',product,'qty','3','discount_kind','percent','discount','10'));
 draft:=public.save_sales_draft(req,org,null,null,outlet,customer,'36',items,'Test draft');
 if draft<>public.save_sales_draft(req,org,null,null,outlet,customer,'36',items,'Test draft') then raise exception 'FAIL draft retry';end if;
 if (select count(*) from public.sales_drafts)<>1 or (select quantity_on_hand from public.stock_balances limit 1)<>stock then raise exception 'FAIL draft stock invariant';end if;
 if (select next_seq from public.invoice_series limit 1)<>1 then raise exception 'FAIL draft reserved number';end if;
 begin
 perform public.save_sales_draft(gen_random_uuid(),org,(draft->>'id')::uuid,0,outlet,customer,'36',items,'stale');
 raise exception 'FAIL stale draft';
 exception when raise_exception then if sqlerrm<>'DRAFT_VERSION_CONFLICT' then raise;end if;end;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$
declare draft public.sales_drafts%rowtype;quote jsonb;reply jsonb;req uuid:=gen_random_uuid();
begin
 select * into draft from public.sales_drafts limit 1;
 quote:=public.quote_sales_draft(draft.organization_id,draft.id,draft.version);
 reply:=public.issue_sales_invoice(req,draft.organization_id,draft.id,draft.version,quote,current_date);
 if reply<>public.issue_sales_invoice(req,draft.organization_id,draft.id,draft.version,quote,current_date) then raise exception 'FAIL issue retry';end if;
 if (select count(*) from public.sales_invoices)<>1 or (select count(*) from public.sales_invoice_items)<>1 then raise exception 'FAIL duplicate invoice';end if;
 if (select quantity_on_hand from public.stock_balances limit 1)<>14 then raise exception 'FAIL issue stock';end if;
 if (select sum(signed_qty) from public.stock_movements)<>14 then raise exception 'FAIL issue reconciliation';end if;
 if (select next_seq from public.invoice_series where id=(select series_id from public.sales_invoices))<>2 then raise exception 'FAIL invoice sequence';end if;
 begin
 delete from public.sales_invoices;
 raise exception 'FAIL finalized invoice deletion';
 exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_b'),true);
do $$ begin
 if exists(select 1 from public.sales_invoices) or exists(select 1 from public.sales_invoice_items) then raise exception 'FAIL cross tenant invoice';end if;
end $$;
reset role;
select 'Invoice issuance and prior assertions passed; fixtures rolled back.' as result;







rollback;
