create function public.quote_sales_draft(p_organization_id uuid,p_draft_id uuid,p_version integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare draft public.sales_drafts%rowtype;org public.organizations%rowtype;
 product public.products%rowtype;item jsonb;line jsonb;lines jsonb:='[]';quantity numeric;available numeric;
 subtotal numeric:=0;discounts numeric:=0;taxable numeric:=0;taxes numeric:=0;total numeric:=0;rate numeric;requested numeric;
begin
 if not private.has_role(p_organization_id,array['owner','manager','cashier']) then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
 select * into draft from public.sales_drafts where id=p_draft_id and organization_id=p_organization_id;
 if not found or (draft.created_by<>auth.uid() and not private.has_role(p_organization_id,array['owner','manager'])) then raise exception using errcode='42501',message='DRAFT_NOT_FOUND';end if;
 if draft.status<>'draft' then raise exception 'DRAFT_ALREADY_ISSUED';end if;
 if p_version is null or p_version<>draft.version then raise exception 'DRAFT_VERSION_CONFLICT';end if;
 select * into org from public.organizations where id=p_organization_id;
 perform 1 from public.outlets where id=draft.outlet_id and organization_id=p_organization_id and active;
 if not found then raise exception 'OUTLET_NOT_FOUND';end if;
 if draft.customer_id is not null then
 perform 1 from public.customers where id=draft.customer_id and organization_id=p_organization_id and active;
 if not found then raise exception 'CUSTOMER_NOT_FOUND';end if;
 end if;
 for item in select value from jsonb_array_elements(draft.items) loop
 select * into product from public.products where id=(item->>'product_id')::uuid and organization_id=p_organization_id and active;
 if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
 quantity:=(item->>'qty')::numeric;
 if product.type='product' then
 select coalesce(sum((value->>'qty')::numeric),0) into requested from jsonb_array_elements(draft.items)
 where value->>'product_id'=product.id::text;
 select quantity_on_hand-reserved_qty into available from public.stock_balances
 where organization_id=p_organization_id and outlet_id=draft.outlet_id and product_id=product.id;
 if requested>coalesce(available,0) then raise exception 'INSUFFICIENT_STOCK';end if;
 end if;
 rate:=case when org.tax_regime='regular' then product.tax_percent else 0 end;
 line:=private.calculate_sale_line(quantity,product.sale_price,rate,product.price_includes_tax,
 coalesce(item->>'discount_kind','fixed'),coalesce(item->>'discount','0')::numeric,draft.place_of_supply<>org.state_code);
 line:=line||jsonb_build_object('product_id',product.id,'name',product.name,'type',product.type,'sku',product.sku,
 'hsn_sac',product.hsn_sac,'unit',product.unit,'qty',quantity,'unit_price',product.sale_price,
 'tax_percent',rate,'price_includes_tax',product.price_includes_tax);
 lines:=lines||jsonb_build_array(line);
 subtotal:=subtotal+(line->>'gross')::numeric;discounts:=discounts+(line->>'discount')::numeric;
 taxable:=taxable+(line->>'taxable_value')::numeric;taxes:=taxes+(line->>'tax_total')::numeric;total:=total+(line->>'total')::numeric;
 end loop;
 if total<=0 then raise exception 'INVALID_SALE_TOTAL';end if;
 return jsonb_build_object('draft_id',draft.id,'draft_version',draft.version,'organization_id',p_organization_id,
 'outlet_id',draft.outlet_id,'customer_id',draft.customer_id,'place_of_supply',draft.place_of_supply,
 'document_type',case org.tax_regime when 'regular' then 'tax_invoice' when 'composition' then 'bill_of_supply' else 'commercial_invoice' end,
 'subtotal',subtotal,'discount_total',discounts,'taxable_total',taxable,'tax_total',taxes,'grand_total',total,'items',lines);
end $$;
revoke all on function public.quote_sales_draft(uuid,uuid,integer) from public,anon;
grant execute on function public.quote_sales_draft(uuid,uuid,integer) to authenticated;
