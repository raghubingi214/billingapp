set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$
declare org uuid;purchase uuid;item uuid;lines jsonb;reply jsonb;request_id uuid:=gen_random_uuid();
begin
 select organization_id,id into org,purchase from public.purchases limit 1;
 select id into item from public.purchase_items where purchase_id=purchase;
 lines:=jsonb_build_array(jsonb_build_object('purchase_item_id',item,'qty','1'));
 reply:=public.return_purchase(request_id,org,purchase,'Damaged goods','CREDIT-1',lines);
 if (reply->>'total')::numeric<>42.26 then raise exception 'FAIL posted credit';end if;
 if reply<>public.return_purchase(request_id,org,purchase,'Damaged goods','CREDIT-1',lines) then raise exception 'FAIL return retry';end if;
 if (select count(*) from public.purchase_returns where organization_id=org)<>1 then raise exception 'FAIL duplicate return';end if;
 if (select quantity_on_hand from public.stock_balances where organization_id=org limit 1)<>16 then raise exception 'FAIL stock reversal';end if;
 if (select sum(signed_qty) from public.stock_movements where organization_id=org)<>16 then raise exception 'FAIL movement reconciliation';end if;
 begin
  perform public.return_purchase(gen_random_uuid(),org,purchase,'Damaged goods',null,
   jsonb_build_array(jsonb_build_object('purchase_item_id',item,'qty','10')));
  raise exception 'FAIL cumulative overreturn';
 exception when raise_exception then if sqlerrm<>'RETURN_EXCEEDS_RECEIVED' then raise;end if;end;
end $$;
reset role;
select 'Purchase return posting assertions passed; fixtures rolled back.' as result;
