create or replace function public.subscription_summary(p_organization_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare subscription private.subscriptions%rowtype; plan private.plans%rowtype;
begin
 if not private.has_role(p_organization_id,array['owner']) then
  raise exception using errcode='42501',message='ACCESS_DENIED';
 end if;
 select * into subscription from private.subscriptions where organization_id=p_organization_id;
 if not found then return jsonb_build_object('status','unconfigured');end if;
 select * into strict plan from private.plans where id=subscription.plan_id;
 return jsonb_build_object('status',case when subscription.period_start>now() then 'pending' when subscription.status in ('trial','active') and subscription.period_end<=now() then 'expired' when subscription.status='grace' and subscription.grace_until<=now() then 'expired' else subscription.status end,'plan_name',plan.name,
  'period_start',subscription.period_start,'period_end',subscription.period_end,
  'grace_until',subscription.grace_until,'cancel_at_period_end',subscription.cancel_at_period_end,
  'price_inr',plan.price_inr,'billing_interval',plan.billing_interval,
  'usage',jsonb_build_object('staff',(select count(*) from public.organization_members where organization_id=p_organization_id and status='active'),'locations',(select count(*) from public.outlets where organization_id=p_organization_id),'invoices',(select count(*) from public.sales_invoices where organization_id=p_organization_id and issued_at >= (date_trunc('month',now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata') and issued_at < ((date_trunc('month',now() at time zone 'Asia/Kolkata')+interval '1 month') at time zone 'Asia/Kolkata'))), 'limits',jsonb_build_object('invoices',plan.monthly_invoice_limit,'staff',plan.staff_limit,
   'locations',plan.location_limit,'reminders',plan.monthly_reminder_limit,'reports',plan.report_types));
end $$;
revoke all on function public.subscription_summary(uuid) from public,anon;
grant execute on function public.subscription_summary(uuid) to authenticated;


