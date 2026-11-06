create table public.customers(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),
 name text not null check(length(trim(name)) between 1 and 200),
 phone text not null default '' check(length(phone)<=30),email text not null default '' check(length(email)<=254),
 gstin text check(gstin is null or gstin ~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$'),
 state_code text not null check(state_code ~ '^[0-9]{2}$'),
 billing_address text not null default '' check(length(billing_address)<=2000),
 shipping_address text not null default '' check(length(shipping_address)<=2000),
 credit_limit numeric(18,2) check(credit_limit>=0),
 active boolean not null default true,version integer not null default 1,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(id,organization_id),check(gstin is null or left(gstin,2)=state_code)
);
create index customers_org_name on public.customers(organization_id,lower(name));
alter table public.customers enable row level security;
revoke all on public.customers from public,anon,authenticated;
grant select on public.customers to authenticated;
create policy customer_finance_read on public.customers for select to authenticated
 using(private.has_role(organization_id,array['owner','manager','accountant']));
create function public.save_customer(p_request_id uuid,p_organization_id uuid,p_customer_id uuid,p_version integer,p_data jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare previous public.customers%rowtype;saved public.customers%rowtype;payload jsonb;reply jsonb;
begin
 perform 1 from public.organizations where id=p_organization_id for update;
 if not private.has_role(p_organization_id,array['owner','manager']) then raise exception using errcode='42501',message='ACCESS_DENIED'; end if;
 payload:=jsonb_build_object('organization_id',p_organization_id,'customer_id',p_customer_id,'version',p_version,'data',p_data);
 reply:=private.replay('save_customer',p_request_id,payload);
 if reply is not null then return reply; end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'INVALID_CUSTOMER'; end if;
 if p_customer_id is not null then
 select * into previous from public.customers where id=p_customer_id and organization_id=p_organization_id for update;
 if not found then raise exception using errcode='42501',message='CUSTOMER_NOT_FOUND'; end if;
 if p_version is null or previous.version<>p_version then raise exception 'CUSTOMER_VERSION_CONFLICT'; end if;
 end if;
 if nullif(p_data->>'credit_limit','') is not null and (p_data->>'credit_limit') !~ '^[0-9]+([.][0-9]{1,2})?$' then raise exception 'INVALID_CREDIT_LIMIT'; end if;
 saved.id:=coalesce(p_customer_id,gen_random_uuid());saved.name:=trim(p_data->>'name');
 saved.phone:=coalesce(trim(p_data->>'phone'),'');saved.email:=coalesce(lower(trim(p_data->>'email')),'');
 if saved.email<>'' and saved.email !~ '^[^ @]+@[^ @]+[.][^ @]+$' then raise exception 'INVALID_EMAIL'; end if;
 saved.gstin:=nullif(upper(trim(p_data->>'gstin')),'');saved.state_code:=p_data->>'state_code';
 if saved.state_code is null or saved.state_code !~ '^[0-9]{2}$' or saved.state_code::integer not between 1 and 38 then raise exception 'INVALID_STATE'; end if;
 saved.billing_address:=coalesce(trim(p_data->>'billing_address'),'');saved.shipping_address:=coalesce(trim(p_data->>'shipping_address'),'');
 saved.credit_limit:=nullif(p_data->>'credit_limit','')::numeric;saved.active:=coalesce((p_data->>'active')::boolean,true);
 if p_customer_id is null then
 insert into public.customers(id,organization_id,name,phone,email,gstin,state_code,billing_address,shipping_address,credit_limit,active)
 values(saved.id,p_organization_id,saved.name,saved.phone,saved.email,saved.gstin,saved.state_code,saved.billing_address,saved.shipping_address,saved.credit_limit,saved.active)
 returning * into saved;
 else
 update public.customers set name=saved.name,phone=saved.phone,email=saved.email,gstin=saved.gstin,state_code=saved.state_code,
 billing_address=saved.billing_address,shipping_address=saved.shipping_address,credit_limit=saved.credit_limit,active=saved.active,
 version=previous.version+1,updated_at=now() where id=p_customer_id returning * into saved;
 end if;
 insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,before_data,after_data,request_id)
 values(p_organization_id,auth.uid(),'customer.saved','customers',saved.id,
 case when p_customer_id is null then null else to_jsonb(previous) end,to_jsonb(saved),p_request_id);
 reply:=to_jsonb(saved);
 insert into private.command_receipts(actor_id,command_name,request_id,payload,response) values(auth.uid(),'save_customer',p_request_id,payload,reply);
 return reply;
end $$;
revoke all on function public.save_customer(uuid,uuid,uuid,integer,jsonb) from public,anon;
grant execute on function public.save_customer(uuid,uuid,uuid,integer,jsonb) to authenticated;
