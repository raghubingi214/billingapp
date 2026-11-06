set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$
declare org uuid;purchase uuid;item uuid;reply jsonb;lines jsonb;
begin
 select organization_id,id into org,purchase from public.purchases limit 1;
 select id into item from public.purchase_items where purchase_id=purchase;
 lines:=jsonb_build_array(jsonb_build_object('purchase_item_id',item,'qty','1'));
 reply:=public.preview_purchase_return(org,purchase,lines);
 if (reply->>'total')::numeric<>42.26 then raise exception 'FAIL return preview amount';end if;
 if (reply->'lines'->0->>'remaining_qty')::numeric<>9 then raise exception 'FAIL returnable quantity';end if;
 if (select count(*) from public.purchase_returns)<>0 or (select quantity_on_hand from public.stock_balances where organization_id=org limit 1)<>17 then
  raise exception 'FAIL preview wrote business data';end if;
 begin
  perform public.preview_purchase_return(org,purchase,jsonb_build_array(jsonb_build_object('purchase_item_id',item,'qty','11')));
  raise exception 'FAIL excess quantity';
 exception when raise_exception then if sqlerrm<>'RETURN_EXCEEDS_RECEIVED' then raise;end if;end;
 begin
  perform public.preview_purchase_return(org,purchase,lines||lines);
  raise exception 'FAIL duplicate line';
 exception when raise_exception then if sqlerrm<>'DUPLICATE_RETURN_LINE' then raise;end if;end;
 begin
  insert into public.purchase_returns(organization_id,purchase_id,reason,taxable_amount,tax_total,total,created_by)
  values(org,purchase,'Return test',1,0,1,auth.uid());
  raise exception 'FAIL direct insert';
 exception when insufficient_privilege then null;end;
end $$;
select set_config('test.purchase_id',(select id::text from public.purchases limit 1),true);
select set_config('test.item_id',(select id::text from public.purchase_items limit 1),true);
select set_config('test.org_id',(select organization_id::text from public.purchases limit 1),true);
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_b'),true);
do $$
declare org uuid;purchase uuid;item uuid;
begin
 org:=current_setting('test.org_id')::uuid;
 purchase:=current_setting('test.purchase_id')::uuid;
 item:=current_setting('test.item_id')::uuid;
 begin
  perform public.preview_purchase_return(org,purchase,jsonb_build_array(jsonb_build_object('purchase_item_id',item,'qty','1')));
  raise exception 'FAIL cross tenant preview';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
select 'Purchase return preview assertions passed; fixtures rolled back.' as result;
