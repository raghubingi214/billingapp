create or replace function public.record_receipt(p_request_id uuid,p_organization_id uuid,p_customer_id uuid,
 p_amount text,p_date date,p_method text,p_reference text,p_allocations jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb;reply jsonb;item jsonb;invoice public.sales_invoices%rowtype;payment_id uuid:=gen_random_uuid();
 amount numeric;allocation numeric;allocated numeric:=0;paid numeric;
begin
 perform 1 from public.organizations where id=p_organization_id for update;
 if not private.has_role(p_organization_id,array['owner','manager','cashier']) then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
 payload:=jsonb_build_object('organization_id',p_organization_id,'customer_id',p_customer_id,'amount',p_amount,
 'date',p_date,'method',p_method,'reference',p_reference,'allocations',p_allocations);
 reply:=private.replay('record_receipt',p_request_id,payload);
 if reply is not null then return reply;end if;
 if p_amount is null or p_amount !~ '^[0-9]+([.][0-9]{1,2})?$' then raise exception 'INVALID_AMOUNT';end if;
 amount:=p_amount::numeric;if amount<=0 then raise exception 'INVALID_AMOUNT';end if;
 if p_date is null or p_date>(now() at time zone 'Asia/Kolkata')::date then raise exception 'INVALID_PAYMENT_DATE';end if;
 if p_method is null or p_method not in ('cash','upi','card','bank','other') or
 (p_method<>'cash' and nullif(trim(p_reference),'') is null) then raise exception 'INVALID_PAYMENT_METHOD_OR_REFERENCE';end if;
 if p_customer_id is not null then
 perform 1 from public.customers where id=p_customer_id and organization_id=p_organization_id and active;
 if not found then raise exception 'CUSTOMER_NOT_FOUND';end if;end if;
 if p_allocations is null or jsonb_typeof(p_allocations)<>'array' then raise exception 'INVALID_ALLOCATIONS';end if;
 if jsonb_array_length(p_allocations)>100 then raise exception 'INVALID_ALLOCATIONS';end if;
 if (select count(distinct value->>'invoice_id') from jsonb_array_elements(p_allocations))<>jsonb_array_length(p_allocations) then raise exception 'DUPLICATE_ALLOCATION';end if;
 for item in select value from jsonb_array_elements(p_allocations) loop
 if coalesce(item->>'amount','') !~ '^[0-9]+([.][0-9]{1,2})?$' then raise exception 'INVALID_ALLOCATION';end if;
 allocation:=(item->>'amount')::numeric;if allocation<=0 then raise exception 'INVALID_ALLOCATION';end if;
 select * into invoice from public.sales_invoices where id=(item->>'invoice_id')::uuid and organization_id=p_organization_id and customer_id is not distinct from p_customer_id for update;
 if not found or (invoice.created_by<>auth.uid() and not private.has_role(p_organization_id,array['owner','manager'])) then raise exception using errcode='42501',message='INVOICE_NOT_FOUND';end if;
 select coalesce(sum(a.amount),0) into paid from public.payment_allocations a where a.organization_id=p_organization_id and a.invoice_id=invoice.id;
 if allocation>invoice.grand_total-paid-coalesce((select sum(r.total) from public.sales_returns r where r.organization_id=p_organization_id and r.original_invoice_id=invoice.id),0) then raise exception 'PAYMENT_EXCEEDS_BALANCE';end if;
 allocated:=allocated+allocation;
 end loop;
 if allocated>amount then raise exception 'ALLOCATION_EXCEEDS_RECEIPT';end if;
 if p_customer_id is null and allocated<>amount then raise exception 'GUEST_RECEIPT_MUST_BE_ALLOCATED';end if;
 insert into public.payments(id,organization_id,customer_id,amount,payment_date,method,reference,created_by)
 values(payment_id,p_organization_id,p_customer_id,amount,p_date,p_method,nullif(trim(p_reference),''),auth.uid());
 for item in select value from jsonb_array_elements(p_allocations) loop
 insert into public.payment_allocations(organization_id,payment_id,customer_id,invoice_id,amount)
 values(p_organization_id,payment_id,p_customer_id,(item->>'invoice_id')::uuid,(item->>'amount')::numeric);
 end loop;
 insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,after_data,request_id)
 values(p_organization_id,auth.uid(),'receipt.recorded','payments',payment_id,jsonb_build_object('amount',amount,'allocated',allocated),p_request_id);
 reply:=jsonb_build_object('payment_id',payment_id,'amount',amount,'allocated',allocated,'unapplied',amount-allocated);
 insert into private.command_receipts(actor_id,command_name,request_id,payload,response) values(auth.uid(),'record_receipt',p_request_id,payload,reply);
 return reply;
end $$;
revoke all on function public.record_receipt(uuid,uuid,uuid,text,date,text,text,jsonb) from public,anon;
grant execute on function public.record_receipt(uuid,uuid,uuid,text,date,text,text,jsonb) to authenticated;
