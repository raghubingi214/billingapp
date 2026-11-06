create table public.suppliers(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id),
 name text not null check(length(trim(name)) between 1 and 200),
 phone text not null default '' check(length(phone)<=30),
 email text not null default '' check(length(email)<=254),
 gstin text check(gstin is null or gstin ~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$'),
 address text not null default '' check(length(address)<=2000),
 payment_terms_days integer not null default 0 check(payment_terms_days between 0 and 365),
 opening_balance numeric(18,2) not null default 0 check(opening_balance>=0),
 active boolean not null default true,
 version integer not null default 1,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(id,organization_id)
);
create index suppliers_org_name on public.suppliers(organization_id,lower(name));
alter table public.suppliers enable row level security;
revoke all on public.suppliers from public,anon,authenticated;
grant select on public.suppliers to authenticated;
create policy suppliers_finance_read on public.suppliers for select to authenticated
 using(private.has_role(organization_id,array['owner','manager','accountant']));
create function public.save_supplier(p_request_id uuid,p_organization_id uuid,p_supplier_id uuid,p_version integer,p_data jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare previous public.suppliers%rowtype; saved public.suppliers%rowtype; reply jsonb; payload jsonb;
begin
 perform 1 from public.organizations where id=p_organization_id for update;
 if not private.has_role(p_organization_id,array['owner','manager']) then raise exception using errcode='42501',message='ACCESS_DENIED'; end if;
 payload:=jsonb_build_object('organization_id',p_organization_id,'supplier_id',p_supplier_id,'version',p_version,'data',p_data);
 reply:=private.replay('save_supplier',p_request_id,payload);
 if reply is not null then return reply; end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'INVALID_SUPPLIER'; end if;
 if p_supplier_id is not null then
 select * into previous from public.suppliers where id=p_supplier_id and organization_id=p_organization_id for update;
 if not found then raise exception using errcode='42501',message='SUPPLIER_NOT_FOUND'; end if;
 if p_version is null or previous.version<>p_version then raise exception 'SUPPLIER_VERSION_CONFLICT'; end if;
 end if;
 if coalesce(p_data->>'opening_balance','') !~ '^[0-9]+([.][0-9]{1,2})?$'
 or coalesce(p_data->>'payment_terms_days','') !~ '^[0-9]{1,3}$' then raise exception 'INVALID_SUPPLIER_AMOUNT_OR_TERMS'; end if;
 if p_supplier_id is not null and (p_data->>'opening_balance')::numeric<>previous.opening_balance then raise exception 'OPENING_BALANCE_IMMUTABLE'; end if;
 saved.id:=coalesce(p_supplier_id,gen_random_uuid());
 saved.name:=trim(p_data->>'name');
 saved.phone:=coalesce(trim(p_data->>'phone'),'');
 saved.email:=coalesce(lower(trim(p_data->>'email')),'');
 if saved.email<>'' and saved.email !~ '^[^ @]+@[^ @]+[.][^ @]+$' then raise exception 'INVALID_EMAIL'; end if;
 saved.gstin:=nullif(upper(trim(p_data->>'gstin')),'');
 saved.address:=coalesce(trim(p_data->>'address'),'');
 saved.payment_terms_days:=(p_data->>'payment_terms_days')::integer;
 saved.opening_balance:=(p_data->>'opening_balance')::numeric;
 saved.active:=coalesce((p_data->>'active')::boolean,true);
 if p_supplier_id is null then
 insert into public.suppliers(id,organization_id,name,phone,email,gstin,address,payment_terms_days,opening_balance,active)
 values(saved.id,p_organization_id,saved.name,saved.phone,saved.email,saved.gstin,saved.address,saved.payment_terms_days,saved.opening_balance,saved.active) returning * into saved;
 else
 update public.suppliers set name=saved.name,phone=saved.phone,email=saved.email,gstin=saved.gstin,address=saved.address,
 payment_terms_days=saved.payment_terms_days,active=saved.active,version=previous.version+1,updated_at=now()
 where id=p_supplier_id returning * into saved;
 end if;
 insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,before_data,after_data,request_id)
 values(p_organization_id,auth.uid(),'supplier.saved','suppliers',saved.id,
 case when p_supplier_id is null then null else to_jsonb(previous) end,to_jsonb(saved),p_request_id);
 reply:=to_jsonb(saved);
 insert into private.command_receipts(actor_id,command_name,request_id,payload,response) values(auth.uid(),'save_supplier',p_request_id,payload,reply);
 return reply;
end $$;
revoke all on function public.save_supplier(uuid,uuid,uuid,integer,jsonb) from public,anon;
grant execute on function public.save_supplier(uuid,uuid,uuid,integer,jsonb) to authenticated;
