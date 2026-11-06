create table private.platform_audit_events (
 id uuid primary key default gen_random_uuid(),actor_id uuid not null references auth.users(id),
 action text not null,entity_id uuid not null,data jsonb not null,request_id uuid not null,
 created_at timestamptz not null default now()
);
create index platform_audit_actor_idx on private.platform_audit_events(actor_id,created_at desc);
alter table private.platform_audit_events enable row level security;
revoke all on private.platform_audit_events from public,anon,authenticated;

create function public.create_platform_plan_draft(p_request_id uuid,p_data jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare saved private.plans%rowtype;reply jsonb;begin
 if not private.is_platform_admin() then raise exception using errcode='42501',message='PLATFORM_ACCESS_DENIED';end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||':plan_draft:'||p_request_id::text,0));
 reply:=private.replay('plan_draft',p_request_id,p_data);
 if reply is not null then return reply;end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or length(p_data::text)>10000
 or coalesce(p_data->>'price_inr','') !~ '^[0-9]+([.][0-9]{1,2})?$'
 or jsonb_typeof(p_data->'report_types') is distinct from 'array' then raise exception 'INVALID_PLAN';end if;
 insert into private.plans(code,name,price_inr,billing_interval,monthly_invoice_limit,trial_invoice_limit,staff_limit,location_limit,monthly_reminder_limit,report_types,active)
 values(p_data->>'code',trim(p_data->>'name'),(p_data->>'price_inr')::numeric,p_data->>'billing_interval',
  (p_data->>'monthly_invoice_limit')::integer,(p_data->>'trial_invoice_limit')::integer,
  (p_data->>'staff_limit')::integer,(p_data->>'location_limit')::integer,(p_data->>'monthly_reminder_limit')::integer,
  array(select jsonb_array_elements_text(p_data->'report_types')),false) returning * into saved;
 insert into private.platform_audit_events(actor_id,action,entity_id,data,request_id)
 values(auth.uid(),'plan.drafted',saved.id,to_jsonb(saved),p_request_id);
 reply:=jsonb_build_object('id',saved.id,'active',false);
 insert into private.command_receipts(actor_id,command_name,request_id,payload,response) values(auth.uid(),'plan_draft',p_request_id,p_data,reply);
 return reply;
end $$;
revoke all on function public.create_platform_plan_draft(uuid,jsonb) from public,anon;
grant execute on function public.create_platform_plan_draft(uuid,jsonb) to authenticated;

create function public.platform_plan_catalog(p_offset integer default 0)
returns setof private.plans language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_platform_admin() then raise exception using errcode='42501',message='PLATFORM_ACCESS_DENIED';end if;
 if p_offset is null or p_offset<0 or p_offset>100000 then raise exception 'INVALID_OFFSET';end if;
 return query select * from private.plans order by created_at desc,id limit 50 offset p_offset;
end $$;
revoke all on function public.platform_plan_catalog(integer) from public,anon;
grant execute on function public.platform_plan_catalog(integer) to authenticated;
