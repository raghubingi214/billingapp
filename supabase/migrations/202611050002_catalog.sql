-- FR-005 catalog; all writes through audited, retry-safe commands.
create table public.products (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id),
 name text not null check(length(trim(name)) between 1 and 200),
 type text not null check(type in ('product','service')),
 sku text, barcode text, category text not null default '',
 unit text not null default 'pcs' check(length(unit) between 1 and 30),
 hsn_sac text not null default '',
 sale_price numeric(18,2) not null check(sale_price>=0),
 purchase_price numeric(18,2) not null default 0 check(purchase_price>=0),
 tax_percent numeric(5,2) not null default 0 check(tax_percent between 0 and 100),
 price_includes_tax boolean not null default false,
 reorder_level numeric(18,3) not null default 0 check(reorder_level>=0),
 active boolean not null default true,
 version integer not null default 1,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(id,organization_id),
 check(type='product' or reorder_level=0)
);
create unique index product_sku_unique on public.products(organization_id,lower(sku)) where sku is not null;
create index products_org_name on public.products(organization_id,lower(name));
create index products_org_barcode on public.products(organization_id,barcode) where barcode is not null;
alter table public.products enable row level security;
revoke all on public.products from public,anon,authenticated;
grant select on public.products to authenticated;
create policy products_member_read on public.products for select to authenticated
 using(organization_id in(select private.my_organization_ids()));

create function public.save_product(p_request_id uuid,p_organization_id uuid,p_product_id uuid,p_version integer,p_data jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare old_row public.products%rowtype; saved public.products%rowtype; payload jsonb; reply jsonb;
begin
 perform 1 from public.organizations where id=p_organization_id for update;
 if not private.has_role(p_organization_id,array['owner','manager']) then
   raise exception using errcode='42501',message='ACCESS_DENIED';
 end if;
 payload:=jsonb_build_object('organization_id',p_organization_id,'product_id',p_product_id,'version',p_version,'data',p_data);
 reply:=private.replay('save_product',p_request_id,payload);
 if reply is not null then return reply; end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'INVALID_PRODUCT'; end if;
 if p_product_id is not null then
   select * into old_row from public.products where id=p_product_id and organization_id=p_organization_id for update;
   if not found then raise exception using errcode='42501',message='PRODUCT_NOT_FOUND'; end if;
   if p_version is null or old_row.version<>p_version then raise exception 'PRODUCT_VERSION_CONFLICT'; end if;
 end if;
 -- Validate raw decimal precision before assignment to fixed-scale columns.
 if coalesce(p_data->>'sale_price','') !~ '^[0-9]+([.][0-9]{1,2})?$'
 or coalesce(p_data->>'purchase_price','') !~ '^[0-9]+([.][0-9]{1,2})?$'
 or coalesce(p_data->>'tax_percent','') !~ '^[0-9]+([.][0-9]{1,2})?$'
 or coalesce(p_data->>'reorder_level','') !~ '^[0-9]+([.][0-9]{1,3})?$' then raise exception 'INVALID_DECIMAL'; end if;
 saved.id:=coalesce(p_product_id,gen_random_uuid());
 saved.organization_id:=p_organization_id;
 saved.name:=trim(p_data->>'name'); saved.type:=p_data->>'type';
 saved.sku:=nullif(trim(p_data->>'sku'),''); saved.barcode:=nullif(trim(p_data->>'barcode'),'');
 saved.category:=coalesce(trim(p_data->>'category'),''); saved.unit:=trim(p_data->>'unit');
 saved.hsn_sac:=coalesce(trim(p_data->>'hsn_sac'),'');
 saved.sale_price:=(p_data->>'sale_price')::numeric;
 saved.purchase_price:=(p_data->>'purchase_price')::numeric;
 saved.tax_percent:=(p_data->>'tax_percent')::numeric;
 saved.price_includes_tax:=coalesce((p_data->>'price_includes_tax')::boolean,false);
 saved.reorder_level:=(p_data->>'reorder_level')::numeric;
 saved.active:=coalesce((p_data->>'active')::boolean,true);
 if p_product_id is null then
   insert into public.products(id,organization_id,name,type,sku,barcode,category,unit,hsn_sac,sale_price,purchase_price,tax_percent,price_includes_tax,reorder_level,active)
   values(saved.id,saved.organization_id,saved.name,saved.type,saved.sku,saved.barcode,saved.category,saved.unit,saved.hsn_sac,saved.sale_price,saved.purchase_price,saved.tax_percent,saved.price_includes_tax,saved.reorder_level,saved.active)
   returning * into saved;
 else
   if old_row.type<>saved.type then raise exception 'PRODUCT_TYPE_IMMUTABLE'; end if;
   update public.products set name=saved.name,sku=saved.sku,barcode=saved.barcode,category=saved.category,
     unit=saved.unit,hsn_sac=saved.hsn_sac,sale_price=saved.sale_price,purchase_price=saved.purchase_price,
     tax_percent=saved.tax_percent,price_includes_tax=saved.price_includes_tax,reorder_level=saved.reorder_level,
     active=saved.active,version=old_row.version+1,updated_at=now()
   where id=p_product_id returning * into saved;
 end if;
 insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,before_data,after_data,request_id)
 values(p_organization_id,auth.uid(),'product.saved','products',saved.id,
   case when p_product_id is null then null else to_jsonb(old_row) end,to_jsonb(saved),p_request_id);
 reply:=to_jsonb(saved);
 insert into private.command_receipts(actor_id,command_name,request_id,payload,response)
 values(auth.uid(),'save_product',p_request_id,payload,reply);
 return reply;
end $$;
revoke all on function public.save_product(uuid,uuid,uuid,integer,jsonb) from public,anon;
grant execute on function public.save_product(uuid,uuid,uuid,integer,jsonb) to authenticated;
