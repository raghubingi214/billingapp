alter table public.purchase_returns drop constraint purchase_returns_check;
alter table public.purchase_returns add constraint purchase_returns_total_check
 check(total>=0 and total=taxable_amount+tax_total);

create function public.return_purchase(p_request_id uuid,p_organization_id uuid,p_purchase_id uuid,
 p_reason text,p_credit_reference text,p_items jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb;reply jsonb;preview jsonb;line jsonb;return_id uuid:=gen_random_uuid();
 purchase public.purchases%rowtype;balance public.stock_balances%rowtype;
 quantity numeric;target_product_id uuid;
begin
 perform 1 from public.organizations where id=p_organization_id for update;
 if not private.has_role(p_organization_id,array['owner','manager']) then
  raise exception using errcode='42501',message='ACCESS_DENIED';
 end if;
 payload:=jsonb_build_object('organization_id',p_organization_id,'purchase_id',p_purchase_id,
  'reason',p_reason,'credit_reference',p_credit_reference,'items',p_items);
 reply:=private.replay('return_purchase',p_request_id,payload);
 if reply is not null then return reply;end if;
 if p_reason is null or length(trim(p_reason)) not between 3 and 500 then raise exception 'REASON_REQUIRED';end if;
 if p_credit_reference is not null and length(trim(p_credit_reference))>100 then raise exception 'REFERENCE_TOO_LONG';end if;
 select * into purchase from public.purchases where id=p_purchase_id and organization_id=p_organization_id for update;
 if not found then raise exception 'PURCHASE_NOT_FOUND';end if;
 preview:=public.preview_purchase_return(p_organization_id,p_purchase_id,p_items);
 insert into public.purchase_returns(id,organization_id,purchase_id,reason,supplier_credit_reference,
  taxable_amount,tax_total,total,created_by)
 select return_id,p_organization_id,p_purchase_id,trim(p_reason),nullif(trim(p_credit_reference),''),
  sum((value->>'taxable_amount')::numeric),sum((value->>'tax_total')::numeric),sum((value->>'total')::numeric),auth.uid()
 from jsonb_array_elements(preview->'lines');
 for line in select value from jsonb_array_elements(preview->'lines') loop
  quantity:=(line->>'qty')::numeric;target_product_id:=(line->>'product_id')::uuid;
  select * into balance from public.stock_balances where organization_id=p_organization_id
   and outlet_id=purchase.outlet_id and product_id=target_product_id for update;
  if not found or balance.quantity_on_hand-balance.reserved_qty<quantity then
   raise exception 'INSUFFICIENT_AVAILABLE_STOCK';end if;
  insert into public.purchase_return_items(organization_id,return_id,original_purchase_item_id,qty,taxable_amount,tax_total,total)
  values(p_organization_id,return_id,(line->>'purchase_item_id')::uuid,quantity,
   (line->>'taxable_amount')::numeric,(line->>'tax_total')::numeric,(line->>'total')::numeric);
  insert into public.stock_movements(organization_id,outlet_id,product_id,movement_type,signed_qty,before_qty,after_qty,reason,source_id,request_id,created_by)
  values(p_organization_id,purchase.outlet_id,target_product_id,'purchase_return',-quantity,balance.quantity_on_hand,
   balance.quantity_on_hand-quantity,trim(p_reason),return_id,p_request_id,auth.uid());
  update public.stock_balances set quantity_on_hand=balance.quantity_on_hand-quantity,
   version=version+1,updated_at=now() where organization_id=p_organization_id
   and outlet_id=purchase.outlet_id and product_id=target_product_id;
 end loop;
 insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,after_data,request_id)
 values(p_organization_id,auth.uid(),'purchase.returned','purchase_returns',return_id,
  jsonb_build_object('purchase_id',p_purchase_id,'total',preview->'total'),p_request_id);
 reply:=jsonb_build_object('return_id',return_id,'total',preview->'total');
 insert into private.command_receipts(actor_id,command_name,request_id,payload,response)
 values(auth.uid(),'return_purchase',p_request_id,payload,reply);
 return reply;
end $$;
revoke all on function public.return_purchase(uuid,uuid,uuid,text,text,jsonb) from public,anon;
grant execute on function public.return_purchase(uuid,uuid,uuid,text,text,jsonb) to authenticated;

