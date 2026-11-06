set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$
declare org uuid;purchase uuid;detail jsonb;report jsonb;req uuid:=gen_random_uuid();reply jsonb;
begin
 select organization_id,id into org,purchase from public.purchases limit 1;
 reply:=public.record_supplier_credit_refund(req,org,purchase,'20.00',current_date,'cash',null);
 if reply<>public.record_supplier_credit_refund(req,org,purchase,'20.00',current_date,'cash',null) then
  raise exception 'FAIL supplier refund retry';end if;
 detail:=public.purchase_detail(org,purchase);
 if (detail->>'supplier_refunded_total')::numeric<>20 or (detail->>'supplier_credit_due')::numeric<>22.27 then
  raise exception 'FAIL partial supplier refund';end if;
 begin
  perform public.record_supplier_credit_refund(gen_random_uuid(),org,purchase,'22.28',current_date,'cash',null);
  raise exception 'FAIL supplier refund cap';
 exception when raise_exception then if sqlerrm<>'REFUND_EXCEEDS_SUPPLIER_CREDIT' then raise;end if;end;
 perform public.record_supplier_credit_refund(gen_random_uuid(),org,purchase,'22.27',current_date,'bank','SUP-REFUND-2');
 detail:=public.purchase_detail(org,purchase);
 if (detail->>'supplier_credit_due')::numeric<>0 or (detail->>'supplier_refunded_total')::numeric<>42.27 or
  jsonb_array_length(detail->'refunds')<>2 then raise exception 'FAIL final supplier refund';end if;
 report:=public.financial_report(org,'payments',current_date-1,current_date+1,0);
 if (report->>'total')::numeric<>-338.10 or
  (select count(*) from jsonb_array_elements(report->'rows') where value->>'type'='supplier_credit_refund')<>2 then
  raise exception 'FAIL cashflow supplier refund reconciliation';end if;
 begin
  insert into public.supplier_credit_refunds(organization_id,purchase_id,supplier_id,amount,refund_date,method,created_by)
  select org,purchase,supplier_id,1,current_date,'cash',auth.uid() from public.purchases where id=purchase;
  raise exception 'FAIL direct supplier refund insert';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
select 'Supplier credit refund assertions passed; fixtures rolled back.' as result;
