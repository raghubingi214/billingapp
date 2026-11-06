select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$ declare org uuid;plan uuid;month_start timestamptz;summary jsonb;begin
 select id into org from foundation_test_context where label='org_a';
 month_start:=date_trunc('month',now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
 insert into private.plans(code,name,price_inr,billing_interval,monthly_invoice_limit,trial_invoice_limit)
 values('cross_month_fixture','Fixture',0,'month',100,1) returning id into plan;
 insert into private.subscriptions(organization_id,plan_id,status,period_start,period_end)
 values(org,plan,'trial',month_start-interval '2 days',now()+interval '5 days');
 -- Backdate only the rollback fixture to the previous calendar month.
 update public.sales_invoices set issued_at=month_start-interval '1 day' where organization_id=org;
 begin perform private.require_entitlement(org,'invoice');raise exception 'FAIL trial quota reset at month boundary';
 exception when raise_exception then if sqlerrm<>'PLAN_LIMIT_REACHED' then raise;end if;end;
 summary:=public.subscription_summary(org);
 if summary->>'invoice_usage_period'<>'trial' or (summary->'usage'->>'invoices')::integer<>1 or (summary->'limits'->>'invoices')::integer<>1 then raise exception 'FAIL trial usage summary mismatch';end if;
end $$;
select 'Cross-month trial assertions passed; fixtures rolled back.' as result;
