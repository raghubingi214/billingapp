alter table private.plans add column trial_invoice_limit integer check(trial_invoice_limit>=0);
create or replace function private.require_entitlement(p_organization_id uuid,p_resource text)
returns void language plpgsql security definer set search_path='' as $$
declare subscription private.subscriptions%rowtype; plan private.plans%rowtype;
 used bigint; cap integer; month_start timestamptz;month_end timestamptz;
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
   cap:=case when subscription.status='trial' then coalesce(plan.trial_invoice_limit,plan.monthly_invoice_limit) else plan.monthly_invoice_limit end;
   month_start:=case when subscription.status='trial' then subscription.period_start else date_trunc('month',now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata' end;
   month_end:=case when subscription.status='trial' then subscription.period_end else month_start+interval '1 month' end;
   select count(*) into used from public.sales_invoices
    where organization_id=p_organization_id and issued_at>=month_start
    and issued_at<month_end;
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
