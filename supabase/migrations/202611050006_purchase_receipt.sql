alter table public.stock_balances add column average_unit_cost numeric(18,6) not null default 0 check(average_unit_cost>=0);
create table public.purchases(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),
 outlet_id uuid not null,supplier_id uuid not null,supplier_bill_no text not null check(length(trim(supplier_bill_no)) between 1 and 100),
 bill_date date not null, supplier_snapshot jsonb not null,
 subtotal numeric(18,2) not null check(subtotal>=0),tax_total numeric(18,2) not null check(tax_total>=0),
 grand_total numeric(18,2) not null check(grand_total>0 and grand_total=subtotal+tax_total),
 status text not null default 'received' check(status='received'),
 created_by uuid not null references auth.users(id),posted_at timestamptz not null default now(),
 unique(id,organization_id),unique(organization_id,supplier_id,supplier_bill_no),
 foreign key(outlet_id,organization_id) references public.outlets(id,organization_id),
 foreign key(supplier_id,organization_id) references public.suppliers(id,organization_id)
);
create table public.purchase_items(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),
 purchase_id uuid not null,product_id uuid not null,product_snapshot jsonb not null,
 qty numeric(18,3) not null check(qty>0),unit_cost numeric(18,2) not null check(unit_cost>=0),
 tax_percent numeric(5,2) not null check(tax_percent between 0 and 100),
 taxable_amount numeric(18,2) not null check(taxable_amount>=0),tax_total numeric(18,2) not null check(tax_total>=0),
 line_total numeric(18,2) not null check(line_total=taxable_amount+tax_total),
 foreign key(purchase_id,organization_id) references public.purchases(id,organization_id),
 foreign key(product_id,organization_id) references public.products(id,organization_id),
 unique(purchase_id,product_id)
);
create index purchases_org_date on public.purchases(organization_id,bill_date desc);
create index purchases_outlet on public.purchases(outlet_id,organization_id);
create index purchases_supplier on public.purchases(supplier_id,organization_id);
create index purchases_actor on public.purchases(created_by);
create index purchase_items_parent on public.purchase_items(purchase_id,organization_id);
create index purchase_items_product on public.purchase_items(product_id,organization_id);
create index purchase_items_org on public.purchase_items(organization_id);
alter table public.purchases enable row level security;
alter table public.purchase_items enable row level security;
revoke all on public.purchases,public.purchase_items from public,anon,authenticated;
grant select on public.purchases,public.purchase_items to authenticated;
create policy purchases_finance_read on public.purchases for select to authenticated
 using(private.has_role(organization_id,array['owner','manager','accountant']));
create policy purchase_items_finance_read on public.purchase_items for select to authenticated
 using(private.has_role(organization_id,array['owner','manager','accountant']));
create function public.receive_purchase(p_request_id uuid,p_organization_id uuid,p_outlet_id uuid,
 p_supplier_id uuid,p_bill_no text,p_bill_date date,p_items jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb;reply jsonb;supplier public.suppliers%rowtype;product public.products%rowtype;
 balance public.stock_balances%rowtype;item jsonb;purchase_id uuid:=gen_random_uuid();
 qty numeric;cost numeric;rate numeric;net numeric;tax numeric;subtotal numeric:=0;taxes numeric:=0;
begin
 perform 1 from public.organizations where id=p_organization_id for update;
 if not private.has_role(p_organization_id,array['owner','manager']) then raise exception using errcode='42501',message='ACCESS_DENIED'; end if;
 payload:=jsonb_build_object('organization_id',p_organization_id,'outlet_id',p_outlet_id,'supplier_id',p_supplier_id,
 'bill_no',p_bill_no,'bill_date',p_bill_date,'items',p_items);
 reply:=private.replay('receive_purchase',p_request_id,payload);
 if reply is not null then return reply; end if;
 if p_bill_no is null or length(trim(p_bill_no)) not between 1 and 100 or p_bill_date is null
 or p_bill_date>(now() at time zone 'Asia/Kolkata')::date then raise exception 'INVALID_BILL'; end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'INVALID_ITEMS'; end if;
 if jsonb_array_length(p_items) not between 1 and 100 then raise exception 'INVALID_ITEMS'; end if;
 if (select count(distinct value->>'product_id') from jsonb_array_elements(p_items))<>jsonb_array_length(p_items) then raise exception 'DUPLICATE_PRODUCT'; end if;
 select * into supplier from public.suppliers where id=p_supplier_id and organization_id=p_organization_id and active;
 if not found then raise exception 'SUPPLIER_NOT_FOUND'; end if;
 perform 1 from public.outlets where id=p_outlet_id and organization_id=p_organization_id and active;
 if not found then raise exception 'OUTLET_NOT_FOUND'; end if;
 -- Validate every line before recording the header.
 for item in select value from jsonb_array_elements(p_items) loop
 if coalesce(item->>'qty','') !~ '^[0-9]+([.][0-9]{1,3})?$'
 or coalesce(item->>'unit_cost','') !~ '^[0-9]+([.][0-9]{1,2})?$'
 or coalesce(item->>'tax_percent','') !~ '^[0-9]+([.][0-9]{1,2})?$' then raise exception 'INVALID_DECIMAL'; end if;
 qty:=(item->>'qty')::numeric;cost:=(item->>'unit_cost')::numeric;rate:=(item->>'tax_percent')::numeric;
 if qty<=0 or rate>100 then raise exception 'INVALID_LINE'; end if;
 select * into product from public.products where id=(item->>'product_id')::uuid and organization_id=p_organization_id and active and type='product' for update;
 if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
 net:=round(qty*cost,2);tax:=round(net*rate/100,2);subtotal:=subtotal+net;taxes:=taxes+tax;
 end loop;
 insert into public.purchases(id,organization_id,outlet_id,supplier_id,supplier_bill_no,bill_date,supplier_snapshot,subtotal,tax_total,grand_total,created_by)
 values(purchase_id,p_organization_id,p_outlet_id,p_supplier_id,trim(p_bill_no),p_bill_date,to_jsonb(supplier),subtotal,taxes,subtotal+taxes,auth.uid());
 for item in select value from jsonb_array_elements(p_items) loop
 qty:=(item->>'qty')::numeric;cost:=(item->>'unit_cost')::numeric;rate:=(item->>'tax_percent')::numeric;
 select * into product from public.products where id=(item->>'product_id')::uuid and organization_id=p_organization_id;
 net:=round(qty*cost,2);tax:=round(net*rate/100,2);
 insert into public.purchase_items(organization_id,purchase_id,product_id,product_snapshot,qty,unit_cost,tax_percent,taxable_amount,tax_total,line_total)
 values(p_organization_id,purchase_id,product.id,to_jsonb(product),qty,cost,rate,net,tax,net+tax);
 insert into public.stock_balances(organization_id,outlet_id,product_id) values(p_organization_id,p_outlet_id,product.id) on conflict do nothing;
 select * into balance from public.stock_balances where organization_id=p_organization_id and outlet_id=p_outlet_id and product_id=product.id for update;
 insert into public.stock_movements(organization_id,outlet_id,product_id,movement_type,signed_qty,before_qty,after_qty,reason,source_id,request_id,created_by)
 values(p_organization_id,p_outlet_id,product.id,'purchase',qty,balance.quantity_on_hand,balance.quantity_on_hand+qty,'Purchase receipt',purchase_id,p_request_id,auth.uid());
 update public.stock_balances set quantity_on_hand=balance.quantity_on_hand+qty,
 average_unit_cost=round((balance.quantity_on_hand*balance.average_unit_cost+net)/(balance.quantity_on_hand+qty),6),
 version=version+1,updated_at=now() where organization_id=p_organization_id and outlet_id=p_outlet_id and product_id=product.id;
 end loop;
 insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,after_data,request_id)
 values(p_organization_id,auth.uid(),'purchase.received','purchases',purchase_id,jsonb_build_object('grand_total',subtotal+taxes),p_request_id);
 reply:=jsonb_build_object('purchase_id',purchase_id,'grand_total',subtotal+taxes);
 insert into private.command_receipts(actor_id,command_name,request_id,payload,response) values(auth.uid(),'receive_purchase',p_request_id,payload,reply);
 return reply;
end $$;
revoke all on function public.receive_purchase(uuid,uuid,uuid,uuid,text,date,jsonb) from public,anon;
grant execute on function public.receive_purchase(uuid,uuid,uuid,uuid,text,date,jsonb) to authenticated;
