set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$
declare org uuid;purchase uuid;supplier uuid;item uuid;detail jsonb;lines jsonb;report jsonb;
begin
 select organization_id,id,supplier_id into org,purchase,supplier from public.purchases limit 1;
 select id into item from public.purchase_items where purchase_id=purchase;
 detail:=public.purchase_detail(org,purchase);
 if (detail->>'paid_total')::numeric<>100 or (detail->>'returned_total')::numeric<>42.26
  or (detail->>'balance_due')::numeric<>280.37 or (detail->>'supplier_credit_due')::numeric<>0 then
  raise exception 'FAIL reconciled purchase detail';end if;
 if (detail->'items'->0->>'returned_qty')::numeric<>1 then raise exception 'FAIL return quantity detail';end if;
 begin
  perform public.pay_supplier(gen_random_uuid(),org,supplier,current_date,'cash',null,
   jsonb_build_array(jsonb_build_object('purchase_id',purchase,'amount','280.38')));
  raise exception 'FAIL return-aware overpayment cap';
 exception when raise_exception then if sqlerrm<>'PAYMENT_EXCEEDS_BALANCE' then raise;end if;end;
 perform public.pay_supplier(gen_random_uuid(),org,supplier,current_date,'cash',null,
  jsonb_build_array(jsonb_build_object('purchase_id',purchase,'amount','280.37')));
 detail:=public.purchase_detail(org,purchase);
 if (detail->>'balance_due')::numeric<>0 then raise exception 'FAIL exact final payment';end if;
 lines:=jsonb_build_array(jsonb_build_object('purchase_item_id',item,'qty','1'));
 perform public.return_purchase(gen_random_uuid(),org,purchase,'Second damaged item',null,lines);
 detail:=public.purchase_detail(org,purchase);
 if (detail->>'supplier_credit_due')::numeric<>42.27 or (detail->>'balance_due')::numeric<>0 then
  raise exception 'FAIL supplier credit due after full payment';end if;
 report:=public.financial_report(org,'purchases',current_date-1,current_date+1,0);
 if (report->>'total')::numeric<>338.10 or (report->>'count')::integer<>3 or
  (select count(*) from jsonb_array_elements(report->'rows') where value->>'type'='purchase_return')<>2 then
  raise exception 'FAIL purchase report return reconciliation';end if;
end $$;
reset role;
select 'Purchase return reconciliation assertions passed; fixtures rolled back.' as result;
