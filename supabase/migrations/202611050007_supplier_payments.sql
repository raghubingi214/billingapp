create table public.supplier_payments(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),
 supplier_id uuid not null,amount numeric(18,2) not null check(amount>0),payment_date date not null,
 method text not null check(method in ('cash','upi','card','bank','other')),
 reference text,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(id,organization_id),unique(id,supplier_id,organization_id),
 foreign key(supplier_id,organization_id) references public.suppliers(id,organization_id),
 check(method='cash' or nullif(trim(reference),'') is not null)
);
create unique index supplier_payment_reference on public.supplier_payments(organization_id,method,reference)
 where reference is not null and method<>'cash';
create table public.supplier_payment_allocations(
 organization_id uuid not null references public.organizations(id),payment_id uuid not null,
 supplier_id uuid not null,purchase_id uuid not null,amount numeric(18,2) not null check(amount>0),
 primary key(payment_id,purchase_id),
 foreign key(payment_id,supplier_id,organization_id) references public.supplier_payments(id,supplier_id,organization_id),
 foreign key(purchase_id,organization_id) references public.purchases(id,organization_id)
);
create index supplier_payments_supplier on public.supplier_payments(supplier_id,organization_id);
create index supplier_payments_actor on public.supplier_payments(created_by);
create index supplier_payments_org_date on public.supplier_payments(organization_id,payment_date);
create index supplier_alloc_purchase on public.supplier_payment_allocations(purchase_id,organization_id);
create index supplier_alloc_org on public.supplier_payment_allocations(organization_id);
alter table public.supplier_payments enable row level security;
alter table public.supplier_payment_allocations enable row level security;
revoke all on public.supplier_payments,public.supplier_payment_allocations from public,anon,authenticated;
grant select on public.supplier_payments,public.supplier_payment_allocations to authenticated;
create policy supplier_payment_finance_read on public.supplier_payments for select to authenticated
 using(private.has_role(organization_id,array['owner','manager','accountant']));
create policy supplier_allocation_finance_read on public.supplier_payment_allocations for select to authenticated
 using(private.has_role(organization_id,array['owner','manager','accountant']));
create function public.pay_supplier(p_request_id uuid,p_organization_id uuid,p_supplier_id uuid,
 p_date date,p_method text,p_reference text,p_allocations jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb;reply jsonb;item jsonb;purchase public.purchases%rowtype;
 total numeric:=0;allocation numeric;paid numeric;payment_id uuid:=gen_random_uuid();
begin
 perform 1 from public.organizations where id=p_organization_id for update;
 if not private.has_role(p_organization_id,array['owner','manager']) then raise exception using errcode='42501',message='ACCESS_DENIED'; end if;
 payload:=jsonb_build_object('organization_id',p_organization_id,'supplier_id',p_supplier_id,
 'date',p_date,'method',p_method,'reference',p_reference,'allocations',p_allocations);
 reply:=private.replay('pay_supplier',p_request_id,payload);
 if reply is not null then return reply; end if;
 if p_date is null or p_date>(now() at time zone 'Asia/Kolkata')::date then raise exception 'INVALID_PAYMENT_DATE'; end if;
 if p_method is null or p_method not in ('cash','upi','card','bank','other')
 or (p_method<>'cash' and nullif(trim(p_reference),'') is null) then raise exception 'INVALID_PAYMENT_METHOD_OR_REFERENCE'; end if;
 if p_allocations is null or jsonb_typeof(p_allocations)<>'array' then raise exception 'INVALID_ALLOCATIONS'; end if;
 if jsonb_array_length(p_allocations) not between 1 and 100 then raise exception 'INVALID_ALLOCATIONS'; end if;
 if (select count(distinct value->>'purchase_id') from jsonb_array_elements(p_allocations))<>jsonb_array_length(p_allocations) then raise exception 'DUPLICATE_ALLOCATION'; end if;
 for item in select value from jsonb_array_elements(p_allocations) loop
 if coalesce(item->>'amount','') !~ '^[0-9]+([.][0-9]{1,2})?$' then raise exception 'INVALID_AMOUNT'; end if;
 allocation:=(item->>'amount')::numeric;
 if allocation<=0 then raise exception 'INVALID_AMOUNT'; end if;
 select * into purchase from public.purchases where id=(item->>'purchase_id')::uuid
 and organization_id=p_organization_id and supplier_id=p_supplier_id for update;
 if not found then raise exception 'PURCHASE_NOT_FOUND'; end if;
 select coalesce(sum(amount),0) into paid from public.supplier_payment_allocations
 where organization_id=p_organization_id and purchase_id=purchase.id;
 if allocation>purchase.grand_total-paid then raise exception 'PAYMENT_EXCEEDS_BALANCE'; end if;
 total:=total+allocation;
 end loop;
 insert into public.supplier_payments(id,organization_id,supplier_id,amount,payment_date,method,reference,created_by)
 values(payment_id,p_organization_id,p_supplier_id,total,p_date,p_method,nullif(trim(p_reference),''),auth.uid());
 for item in select value from jsonb_array_elements(p_allocations) loop
 insert into public.supplier_payment_allocations(organization_id,payment_id,supplier_id,purchase_id,amount)
 values(p_organization_id,payment_id,p_supplier_id,(item->>'purchase_id')::uuid,(item->>'amount')::numeric);
 end loop;
 insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,after_data,request_id)
 values(p_organization_id,auth.uid(),'supplier.paid','supplier_payments',payment_id,jsonb_build_object('amount',total),p_request_id);
 reply:=jsonb_build_object('payment_id',payment_id,'amount',total);
 insert into private.command_receipts(actor_id,command_name,request_id,payload,response) values(auth.uid(),'pay_supplier',p_request_id,payload,reply);
 return reply;
end $$;
revoke all on function public.pay_supplier(uuid,uuid,uuid,date,text,text,jsonb) from public,anon;
grant execute on function public.pay_supplier(uuid,uuid,uuid,date,text,text,jsonb) to authenticated;
