create function public.platform_subscription_options(p_organization_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if not private.is_platform_admin() then
    raise exception using errcode='42501', message='PLATFORM_ACCESS_DENIED';
  end if;
  if not exists (select 1 from public.organizations where id=p_organization_id) then
    raise exception 'ORGANIZATION_NOT_FOUND';
  end if;
  return jsonb_build_object(
    'current', (
      select jsonb_build_object('plan_id',s.plan_id,'name',p.name,'version',s.version,
        'gateway_managed',s.gateway_subscription_id is not null)
      from private.subscriptions s join private.plans p on p.id=s.plan_id
      where s.organization_id=p_organization_id
    ),
    'plans', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id',id,'name',name,'price_inr',price_inr,'interval',billing_interval
      ) order by price_inr,name,id),'[]'::jsonb)
      from private.plans where active
    )
  );
end $$;

create function public.assign_platform_subscription(
  p_request_id uuid,p_organization_id uuid,p_plan_id uuid,p_expected_version integer
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  prior private.subscriptions%rowtype;
  plan private.plans%rowtype;
  saved private.subscriptions%rowtype;
  payload jsonb;
  reply jsonb;
  starts_at timestamptz := now();
  ends_at timestamptz;
begin
  if not private.is_platform_admin() then
    raise exception using errcode='42501', message='PLATFORM_ACCESS_DENIED';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||':assign_subscription:'||p_request_id::text,0));
  perform 1 from public.organizations where id=p_organization_id for update;
  if not found then raise exception 'ORGANIZATION_NOT_FOUND'; end if;
  if not private.is_platform_admin() then
    raise exception using errcode='42501', message='PLATFORM_ACCESS_DENIED';
  end if;
  payload := jsonb_build_object('organization_id',p_organization_id,'plan_id',p_plan_id,'version',p_expected_version);
  reply := private.replay('assign_subscription',p_request_id,payload);
  if reply is not null then return reply; end if;

  select * into prior from private.subscriptions where organization_id=p_organization_id for update;
  if prior.version is distinct from p_expected_version then raise exception 'SUBSCRIPTION_CHANGED'; end if;
  if prior.gateway_subscription_id is not null then raise exception 'GATEWAY_MANAGED_SUBSCRIPTION'; end if;
  select * into plan from private.plans where id=p_plan_id and active for share;
  if not found then raise exception 'PLAN_NOT_AVAILABLE'; end if;

  ends_at := case
    when plan.price_inr=0 then 'infinity'::timestamptz
    when plan.billing_interval='year' then starts_at+interval '1 year'
    else starts_at+interval '1 month'
  end;
  insert into private.subscriptions(organization_id,plan_id,status,period_start,period_end)
  values(p_organization_id,p_plan_id,'active',starts_at,ends_at)
  on conflict (organization_id) do update set
    plan_id=excluded.plan_id,status='active',period_start=excluded.period_start,
    period_end=excluded.period_end,grace_until=null,cancel_at_period_end=false,
    version=private.subscriptions.version+1,updated_at=now()
  returning * into saved;
  insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,before_data,after_data,request_id)
  values(p_organization_id,auth.uid(),'subscription.assigned','subscriptions',saved.id,
    jsonb_build_object('plan_id',prior.plan_id,'version',prior.version),
    jsonb_build_object('plan_id',saved.plan_id,'version',saved.version,'period_end',saved.period_end),p_request_id);
  reply := jsonb_build_object('plan_id',saved.plan_id,'version',saved.version,'period_end',saved.period_end);
  insert into private.command_receipts(actor_id,command_name,request_id,payload,response)
  values(auth.uid(),'assign_subscription',p_request_id,payload,reply);
  return reply;
end $$;

revoke all on function public.platform_subscription_options(uuid) from public,anon;
revoke all on function public.assign_platform_subscription(uuid,uuid,uuid,integer) from public,anon;
grant execute on function public.platform_subscription_options(uuid) to authenticated;
grant execute on function public.assign_platform_subscription(uuid,uuid,uuid,integer) to authenticated;
