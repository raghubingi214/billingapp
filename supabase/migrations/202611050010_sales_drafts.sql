-- Decimal line arithmetic. Round half away from zero at each monetary line boundary.
create function private.calculate_sale_line(p_qty numeric,p_unit_price numeric,p_rate numeric,
 p_inclusive boolean,p_discount_kind text,p_discount numeric,p_interstate boolean)
returns jsonb language plpgsql immutable set search_path='' as $$
declare gross numeric;discount numeric;base numeric;tax numeric;cgst numeric;sgst numeric;igst numeric;
begin
 if p_qty is null or p_qty<=0 or p_qty<>round(p_qty,3) or p_unit_price is null or p_unit_price<0
 or p_unit_price<>round(p_unit_price,2) or p_rate is null or p_rate not between 0 and 100
 or p_discount is null or p_discount<0 or p_discount_kind is null or p_discount_kind not in ('fixed','percent')
 or p_inclusive is null or p_interstate is null then raise exception 'INVALID_LINE'; end if;
 gross:=round(p_qty*p_unit_price,2);
 if p_discount_kind='percent' then
 if p_discount>100 then raise exception 'INVALID_DISCOUNT'; end if;
 discount:=round(gross*p_discount/100,2);
 else discount:=round(p_discount,2);end if;
 if discount>gross then raise exception 'DISCOUNT_EXCEEDS_LINE'; end if;
 if p_inclusive then base:=round((gross-discount)/(1+p_rate/100),2);tax:=gross-discount-base;
 else base:=gross-discount;tax:=round(base*p_rate/100,2);end if;
 if p_interstate then igst:=tax;cgst:=0;sgst:=0;
 else igst:=0;cgst:=round(tax/2,2);sgst:=tax-cgst;end if;
 return jsonb_build_object('gross',gross,'discount',discount,'taxable_value',base,
 'cgst',cgst,'sgst',sgst,'igst',igst,'tax_total',tax,'total',base+tax);
end $$;
revoke all on function private.calculate_sale_line(numeric,numeric,numeric,boolean,text,numeric,boolean) from public,anon,authenticated;

create table public.sales_drafts(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),
 outlet_id uuid not null,customer_id uuid,place_of_supply text not null check(place_of_supply ~ '^[0-9]{2}$'),
 items jsonb not null check(jsonb_typeof(items)='array'),notes text not null default '',
 version integer not null default 1,status text not null default 'draft' check(status in ('draft','issued')),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),unique(id,organization_id),
 foreign key(outlet_id,organization_id) references public.outlets(id,organization_id),
 foreign key(customer_id,organization_id) references public.customers(id,organization_id)
);
create index sales_drafts_org_time on public.sales_drafts(organization_id,updated_at desc);
create index sales_drafts_outlet on public.sales_drafts(outlet_id,organization_id);
create index sales_drafts_customer on public.sales_drafts(customer_id,organization_id);
create index sales_drafts_creator on public.sales_drafts(created_by);
alter table public.sales_drafts enable row level security;
revoke all on public.sales_drafts from public,anon,authenticated;
grant select on public.sales_drafts to authenticated;
create policy draft_scoped_read on public.sales_drafts for select to authenticated
 using(private.has_role(organization_id,array['owner','manager']) or
 (created_by=(select auth.uid()) and private.has_role(organization_id,array['cashier'])));
create function public.save_sales_draft(p_request_id uuid,p_organization_id uuid,p_draft_id uuid,p_version integer,
 p_outlet_id uuid,p_customer_id uuid,p_place_of_supply text,p_items jsonb,p_notes text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare previous public.sales_drafts%rowtype;saved public.sales_drafts%rowtype;item jsonb;payload jsonb;reply jsonb;
begin
 perform 1 from public.organizations where id=p_organization_id for update;
 if not private.has_role(p_organization_id,array['owner','manager','cashier']) then raise exception using errcode='42501',message='ACCESS_DENIED'; end if;
 payload:=jsonb_build_object('organization_id',p_organization_id,'draft_id',p_draft_id,'version',p_version,
 'outlet_id',p_outlet_id,'customer_id',p_customer_id,'place_of_supply',p_place_of_supply,'items',p_items,'notes',p_notes);
 reply:=private.replay('save_sales_draft',p_request_id,payload);
 if reply is not null then return reply; end if;
 if p_draft_id is not null then
 select * into previous from public.sales_drafts where id=p_draft_id and organization_id=p_organization_id for update;
 if not found or (previous.created_by<>auth.uid() and not private.has_role(p_organization_id,array['owner','manager'])) then raise exception using errcode='42501',message='DRAFT_NOT_FOUND'; end if;
 if previous.status<>'draft' then raise exception 'DRAFT_ALREADY_ISSUED'; end if;
 if p_version is null or previous.version<>p_version then raise exception 'DRAFT_VERSION_CONFLICT'; end if;
 end if;
 if p_place_of_supply is null or p_place_of_supply !~ '^[0-9]{2}$' or p_place_of_supply::integer not between 1 and 38 then raise exception 'INVALID_PLACE_OF_SUPPLY'; end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'INVALID_ITEMS';end if;
 if jsonb_array_length(p_items) not between 1 and 100 then raise exception 'INVALID_ITEMS';end if;
 if length(coalesce(p_notes,''))>4000 then raise exception 'NOTES_TOO_LONG';end if;
 perform 1 from public.outlets where id=p_outlet_id and organization_id=p_organization_id and active;
 if not found then raise exception 'OUTLET_NOT_FOUND';end if;
 if p_customer_id is not null then
 perform 1 from public.customers where id=p_customer_id and organization_id=p_organization_id and active;
 if not found then raise exception 'CUSTOMER_NOT_FOUND';end if;end if;
 for item in select value from jsonb_array_elements(p_items) loop
 perform 1 from public.products where id=(item->>'product_id')::uuid and organization_id=p_organization_id and active;
 if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
 if coalesce(item->>'qty','') !~ '^[0-9]+([.][0-9]{1,3})?$' or (item->>'qty')::numeric<=0 then raise exception 'INVALID_QUANTITY';end if;
 if coalesce(item->>'discount_kind','fixed') not in ('fixed','percent')
 or coalesce(item->>'discount','0') !~ '^[0-9]+([.][0-9]{1,2})?$' then raise exception 'INVALID_DISCOUNT';end if;
 end loop;
 if p_draft_id is null then
 insert into public.sales_drafts(organization_id,outlet_id,customer_id,place_of_supply,items,notes,created_by)
 values(p_organization_id,p_outlet_id,p_customer_id,p_place_of_supply,p_items,coalesce(p_notes,''),auth.uid()) returning * into saved;
 else
 update public.sales_drafts set outlet_id=p_outlet_id,customer_id=p_customer_id,place_of_supply=p_place_of_supply,
 items=p_items,notes=coalesce(p_notes,''),version=previous.version+1,updated_at=now() where id=p_draft_id returning * into saved;
 end if;
 insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,after_data,request_id)
 values(p_organization_id,auth.uid(),'sale.draft_saved','sales_drafts',saved.id,jsonb_build_object('version',saved.version),p_request_id);
 reply:=to_jsonb(saved);
 insert into private.command_receipts(actor_id,command_name,request_id,payload,response) values(auth.uid(),'save_sales_draft',p_request_id,payload,reply);
 return reply;
end $$;
revoke all on function public.save_sales_draft(uuid,uuid,uuid,integer,uuid,uuid,text,jsonb,text) from public,anon;
grant execute on function public.save_sales_draft(uuid,uuid,uuid,integer,uuid,uuid,text,jsonb,text) to authenticated;
