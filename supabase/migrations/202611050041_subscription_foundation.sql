-- Draft migration: validate with entitlement command hooks before deployment.
-- Pricing and provider identifiers are configured by trusted operators.
create table private.plans (
 id uuid primary key default gen_random_uuid(),
 code text not null unique check(code ~ '^[a-z][a-z0-9_]{1,63}$'),
 name text not null check(length(trim(name)) between 1 and 120),
 monthly_invoice_limit integer check(monthly_invoice_limit>=0),
 staff_limit integer check(staff_limit>=1),
 location_limit integer check(location_limit>=1),
 monthly_reminder_limit integer check(monthly_reminder_limit>=0),
 report_types text[] not null default '{}',
 price_inr numeric(18,2) not null check(price_inr>=0),
 billing_interval text not null check(billing_interval in ('month','year')),
 active boolean not null default true,
 created_at timestamptz not null default now()
);

create table private.subscriptions (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null unique references public.organizations(id),
 plan_id uuid not null references private.plans(id),
 status text not null check(status in ('trial','active','grace','expired','failed_renewal')),
 period_start timestamptz not null,
 period_end timestamptz not null,
 grace_until timestamptz,
 cancel_at_period_end boolean not null default false,
 gateway_customer_id text,
 gateway_subscription_id text unique,
 version integer not null default 1 check(version>0),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(period_end>period_start),
 check(grace_until is null or grace_until>=period_end),
 check(status<>'grace' or grace_until is not null)
);
create index subscriptions_plan_idx on private.subscriptions(plan_id);
alter table private.plans enable row level security;
alter table private.subscriptions enable row level security;
revoke all on private.plans,private.subscriptions from public,anon,authenticated;

-- Immutable event receipt identity provides a deduplication boundary for future
-- provider-verified webhook processing; it grants no client payment authority.
create table private.subscription_events (
 provider text not null check(length(provider) between 1 and 40),
 event_id text not null check(length(event_id) between 1 and 256),
 subscription_id uuid not null references private.subscriptions(id),
 event_type text not null,
 received_at timestamptz not null default now(),
 primary key(provider,event_id)
);
create index subscription_events_subscription_idx on private.subscription_events(subscription_id);
alter table private.subscription_events enable row level security;
revoke all on private.subscription_events from public,anon,authenticated;

-- Call only after the command's successful replay check, and before new writes.
-- Every command that consumes quota must retain the organization row lock until
-- commit. Subscription changes must acquire that same lock before changing plans.
create function private.require_entitlement(p_organization_id uuid,p_resource text)
returns void language plpgsql security definer set search_path='' as $$
declare subscription private.subscriptions%rowtype; plan private.plans%rowtype;
 used bigint; cap integer; month_start timestamptz;
begin
 perform 1 from public.organizations where id=p_organization_id for update;
 if not found then raise exception 'ORGANIZATION_NOT_FOUND';end if;
 select * into subscription from private.subscriptions where organization_id=p_organization_id;
 if not found then raise exception 'SUBSCRIPTION_REQUIRED';end if;
 if subscription.period_start>now() or not (
   (subscription.status in ('trial','active') and now()<subscription.period_end)
   or (subscription.status='grace' and now()<subscription.grace_until)
 ) then raise exception 'SUBSCRIPTION_EXPIRED';end if;
 select * into strict plan from private.plans where id=subscription.plan_id;
 -- Retired plans remain usable by existing subscriptions until their period ends.
 if p_resource='invoice' then
   cap:=plan.monthly_invoice_limit;
   month_start:=date_trunc('month',now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
   select count(*) into used from public.sales_invoices
    where organization_id=p_organization_id and issued_at>=month_start
    and issued_at<month_start+interval '1 month';
 elsif p_resource='staff' then
   cap:=plan.staff_limit;
   select count(*) into used from public.organization_members
    where organization_id=p_organization_id and status='active';
 elsif p_resource='location' then
   cap:=plan.location_limit;
   select count(*) into used from public.outlets where organization_id=p_organization_id;
 else
   raise exception 'UNKNOWN_ENTITLEMENT';
 end if;
 if cap is not null and used>=cap then raise exception 'PLAN_LIMIT_REACHED';end if;
end $$;
revoke all on function private.require_entitlement(uuid,text) from public,anon,authenticated;
create index sales_invoices_monthly_usage_idx on public.sales_invoices(organization_id,issued_at);

-- Trial policy is explicitly configured by a trusted operator. No prices or
-- trial duration are invented by a client or silently assigned by this migration.
create table private.trial_policy (
 singleton boolean primary key default true check(singleton),
 plan_id uuid not null references private.plans(id),
 duration_days integer not null check(duration_days between 1 and 365),
 enabled boolean not null default false
);
alter table private.trial_policy enable row level security;
revoke all on private.trial_policy from public,anon,authenticated;

create function private.provision_trial(p_organization_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare policy private.trial_policy%rowtype;
begin
 perform 1 from public.organizations where id=p_organization_id for update;
 if not found then raise exception 'ORGANIZATION_NOT_FOUND';end if;
 if exists(select 1 from private.subscriptions where organization_id=p_organization_id) then return;end if;
 select t.* into policy from private.trial_policy t join private.plans p on p.id=t.plan_id
 where t.singleton and t.enabled and p.active;
 if not found then raise exception 'TRIAL_CONFIGURATION_REQUIRED';end if;
 insert into private.subscriptions(organization_id,plan_id,status,period_start,period_end)
 values(p_organization_id,policy.plan_id,'trial',now(),now()+make_interval(days=>policy.duration_days));
end $$;
revoke all on function private.provision_trial(uuid) from public,anon,authenticated;

create function public.subscription_summary(p_organization_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare subscription private.subscriptions%rowtype; plan private.plans%rowtype;
begin
 if not private.has_role(p_organization_id,array['owner']) then
  raise exception using errcode='42501',message='ACCESS_DENIED';
 end if;
 select * into subscription from private.subscriptions where organization_id=p_organization_id;
 if not found then return jsonb_build_object('status','unconfigured');end if;
 select * into strict plan from private.plans where id=subscription.plan_id;
 return jsonb_build_object('status',subscription.status,'plan_name',plan.name,
  'period_start',subscription.period_start,'period_end',subscription.period_end,
  'grace_until',subscription.grace_until,'cancel_at_period_end',subscription.cancel_at_period_end,
  'price_inr',plan.price_inr,'billing_interval',plan.billing_interval,
  'limits',jsonb_build_object('invoices',plan.monthly_invoice_limit,'staff',plan.staff_limit,
   'locations',plan.location_limit,'reminders',plan.monthly_reminder_limit,'reports',plan.report_types));
end $$;
revoke all on function public.subscription_summary(uuid) from public,anon;
grant execute on function public.subscription_summary(uuid) to authenticated;
