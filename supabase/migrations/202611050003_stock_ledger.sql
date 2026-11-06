create table public.stock_balances(
 organization_id uuid not null references public.organizations(id),
 outlet_id uuid not null, product_id uuid not null,
 quantity_on_hand numeric(18,3) not null default 0 check(quantity_on_hand>=0),
 reserved_qty numeric(18,3) not null default 0 check(reserved_qty>=0 and reserved_qty<=quantity_on_hand),
 version integer not null default 1,
 updated_at timestamptz not null default now(),
 primary key(organization_id,outlet_id,product_id),
 foreign key(outlet_id,organization_id) references public.outlets(id,organization_id),
 foreign key(product_id,organization_id) references public.products(id,organization_id)
);
create table public.stock_movements(
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id),
 outlet_id uuid not null, product_id uuid not null,
 movement_type text not null check(movement_type in ('adjustment','purchase','sale','sale_return','purchase_return')),
 signed_qty numeric(18,3) not null check(signed_qty<>0),
 before_qty numeric(18,3) not null, after_qty numeric(18,3) not null,
 reason text not null check(length(trim(reason)) between 3 and 500),
 source_id uuid not null, request_id uuid not null,
 created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 check(after_qty=before_qty+signed_qty),
 foreign key(outlet_id,organization_id) references public.outlets(id,organization_id),
 foreign key(product_id,organization_id) references public.products(id,organization_id),
 unique(organization_id,request_id,product_id,outlet_id)
);
create index stock_movement_timeline on public.stock_movements(organization_id,outlet_id,product_id,created_at desc);
create index stock_balance_product on public.stock_balances(product_id,organization_id);
create index stock_movement_product on public.stock_movements(product_id,organization_id);
create index stock_balance_outlet on public.stock_balances(outlet_id,organization_id);
create index stock_movement_outlet on public.stock_movements(outlet_id,organization_id);
create index stock_movement_actor on public.stock_movements(created_by);
alter table public.stock_balances enable row level security;
alter table public.stock_movements enable row level security;
revoke all on public.stock_balances,public.stock_movements from public,anon,authenticated;
grant select on public.stock_balances,public.stock_movements to authenticated;
create policy stock_member_read on public.stock_balances for select to authenticated
 using(organization_id in(select private.my_organization_ids()));
create policy movement_finance_read on public.stock_movements for select to authenticated
 using(private.has_role(organization_id,array['owner','manager','accountant']));
create function public.post_stock_count(p_request_id uuid,p_organization_id uuid,p_outlet_id uuid,
 p_product_id uuid,p_expected_version integer,p_counted_qty text,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb; reply jsonb; balance public.stock_balances%rowtype;
 counted numeric; movement_id uuid:=gen_random_uuid(); product public.products%rowtype;
begin
 perform 1 from public.organizations where id=p_organization_id for update;
 if not private.has_role(p_organization_id,array['owner']) then raise exception using errcode='42501',message='ACCESS_DENIED'; end if;
 payload:=jsonb_build_object('organization_id',p_organization_id,'outlet_id',p_outlet_id,'product_id',p_product_id,
 'expected_version',p_expected_version,'counted_qty',p_counted_qty,'reason',p_reason);
 reply:=private.replay('stock_count',p_request_id,payload);
 if reply is not null then return reply; end if;
 if p_counted_qty is null or p_counted_qty !~ '^[0-9]+([.][0-9]{1,3})?$' then raise exception 'INVALID_QUANTITY'; end if;
 counted:=p_counted_qty::numeric;
 if p_reason is null or length(trim(p_reason)) not between 3 and 500 then raise exception 'REASON_REQUIRED'; end if;
 perform 1 from public.outlets where id=p_outlet_id and organization_id=p_organization_id and active;
 if not found then raise exception 'OUTLET_NOT_FOUND'; end if;
 select * into product from public.products where id=p_product_id and organization_id=p_organization_id and active for update;
 if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
 if product.type<>'product' then raise exception 'SERVICE_HAS_NO_STOCK'; end if;
 insert into public.stock_balances(organization_id,outlet_id,product_id) values(p_organization_id,p_outlet_id,p_product_id) on conflict do nothing;
 select * into balance from public.stock_balances where organization_id=p_organization_id and outlet_id=p_outlet_id and product_id=p_product_id for update;
 if p_expected_version is null or p_expected_version<>balance.version then raise exception 'STOCK_VERSION_CONFLICT'; end if;
 if counted<balance.reserved_qty then raise exception 'COUNT_BELOW_RESERVED'; end if;
 if counted=balance.quantity_on_hand then raise exception 'NO_STOCK_CHANGE'; end if;
 insert into public.stock_movements(id,organization_id,outlet_id,product_id,movement_type,signed_qty,before_qty,after_qty,reason,source_id,request_id,created_by)
 values(movement_id,p_organization_id,p_outlet_id,p_product_id,'adjustment',counted-balance.quantity_on_hand,balance.quantity_on_hand,counted,trim(p_reason),movement_id,p_request_id,auth.uid());
 update public.stock_balances set quantity_on_hand=counted,version=version+1,updated_at=now()
 where organization_id=p_organization_id and outlet_id=p_outlet_id and product_id=p_product_id;
 insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,before_data,after_data,request_id)
 values(p_organization_id,auth.uid(),'stock.counted','stock_movements',movement_id,to_jsonb(balance),
 jsonb_build_object('quantity_on_hand',counted,'reason',trim(p_reason)),p_request_id);
 reply:=jsonb_build_object('movement_id',movement_id,'quantity_on_hand',counted,'version',balance.version+1);
 insert into private.command_receipts(actor_id,command_name,request_id,payload,response) values(auth.uid(),'stock_count',p_request_id,payload,reply);
 return reply;
end $$;
revoke all on function public.post_stock_count(uuid,uuid,uuid,uuid,integer,text,text) from public,anon;
grant execute on function public.post_stock_count(uuid,uuid,uuid,uuid,integer,text,text) to authenticated;
