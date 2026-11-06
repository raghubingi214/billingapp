create table public.purchase_returns(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id),
 purchase_id uuid not null, return_date date not null default (now() at time zone 'Asia/Kolkata')::date,
 reason text not null check(length(trim(reason)) between 3 and 500),
 supplier_credit_reference text,
 taxable_amount numeric(18,2) not null check(taxable_amount>=0),
 tax_total numeric(18,2) not null check(tax_total>=0),
 total numeric(18,2) not null check(total>0 and total=taxable_amount+tax_total),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(id,organization_id),
 foreign key(purchase_id,organization_id) references public.purchases(id,organization_id)
);
alter table public.purchase_items add constraint purchase_item_tenant_key unique(id,organization_id);
create table public.purchase_return_items(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),
 return_id uuid not null,original_purchase_item_id uuid not null,
 qty numeric(18,3) not null check(qty>0),
 taxable_amount numeric(18,2) not null check(taxable_amount>=0),
 tax_total numeric(18,2) not null check(tax_total>=0),
 total numeric(18,2) not null check(total=taxable_amount+tax_total),
 foreign key(return_id,organization_id) references public.purchase_returns(id,organization_id),
 foreign key(original_purchase_item_id,organization_id) references public.purchase_items(id,organization_id),
 unique(return_id,original_purchase_item_id)
);
create index purchase_returns_purchase on public.purchase_returns(purchase_id,organization_id);
create index purchase_returns_org_date on public.purchase_returns(organization_id,return_date desc);
create index purchase_returns_actor on public.purchase_returns(created_by);
create index purchase_return_items_original on public.purchase_return_items(original_purchase_item_id,organization_id);
create index purchase_return_items_org on public.purchase_return_items(organization_id);
alter table public.purchase_returns enable row level security;
alter table public.purchase_return_items enable row level security;
revoke all on public.purchase_returns,public.purchase_return_items from public,anon,authenticated;
grant select on public.purchase_returns,public.purchase_return_items to authenticated;
create policy purchase_returns_finance_read on public.purchase_returns for select to authenticated
 using(private.has_role(organization_id,array['owner','manager','accountant']));
create policy purchase_return_items_finance_read on public.purchase_return_items for select to authenticated
 using(private.has_role(organization_id,array['owner','manager','accountant']));

create function public.preview_purchase_return(p_organization_id uuid,p_purchase_id uuid,p_items jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare original public.purchase_items%rowtype; purchase public.purchases%rowtype;
 item jsonb;previous record; balance public.stock_balances%rowtype;
 quantity numeric;net numeric;tax numeric;total numeric:=0;lines jsonb:='[]'::jsonb;
begin
 if not private.has_role(p_organization_id,array['owner','manager']) then
  raise exception using errcode='42501',message='ACCESS_DENIED';
 end if;
 select * into purchase from public.purchases where id=p_purchase_id and organization_id=p_organization_id;
 if not found then raise exception 'PURCHASE_NOT_FOUND';end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 100 then
  raise exception 'INVALID_RETURN_ITEMS';end if;
 if (select count(distinct value->>'purchase_item_id') from jsonb_array_elements(p_items))<>jsonb_array_length(p_items) then
  raise exception 'DUPLICATE_RETURN_LINE';end if;
 for item in select value from jsonb_array_elements(p_items) loop
  if coalesce(item->>'qty','') !~ '^[0-9]+([.][0-9]{1,3})?$' then raise exception 'INVALID_QUANTITY';end if;
  quantity:=(item->>'qty')::numeric;
  if quantity<=0 then raise exception 'INVALID_QUANTITY';end if;
  select * into original from public.purchase_items where id=(item->>'purchase_item_id')::uuid
   and purchase_id=p_purchase_id and organization_id=p_organization_id;
  if not found then raise exception 'PURCHASE_ITEM_NOT_FOUND';end if;
  select coalesce(sum(qty),0) as qty,coalesce(sum(taxable_amount),0) as net,
   coalesce(sum(tax_total),0) as tax into previous from public.purchase_return_items
   where original_purchase_item_id=original.id and organization_id=p_organization_id;
  if quantity+previous.qty>original.qty then raise exception 'RETURN_EXCEEDS_RECEIVED';end if;
  select * into balance from public.stock_balances where organization_id=p_organization_id
   and outlet_id=purchase.outlet_id and product_id=original.product_id;
  if not found or balance.quantity_on_hand<quantity then raise exception 'INSUFFICIENT_STOCK';end if;
  net:=round(original.taxable_amount*(previous.qty+quantity)/original.qty,2)-previous.net;
  tax:=round(original.tax_total*(previous.qty+quantity)/original.qty,2)-previous.tax;
  total:=total+net+tax;
  lines:=lines||jsonb_build_array(jsonb_build_object('purchase_item_id',original.id,'product_id',original.product_id,
   'qty',quantity,'remaining_qty',original.qty-previous.qty-quantity,'taxable_amount',net,'tax_total',tax,'total',net+tax));
 end loop;
 return jsonb_build_object('purchase_id',p_purchase_id,'total',total,'lines',lines);
end $$;
revoke all on function public.preview_purchase_return(uuid,uuid,jsonb) from public,anon;
grant execute on function public.preview_purchase_return(uuid,uuid,jsonb) to authenticated;
