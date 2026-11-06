-- Append inside foundation.sql's transaction before its final rollback.
do $$ declare org uuid; plan uuid; first_end timestamptz;begin
 select id into org from foundation_test_context where label='org_a';
 begin perform private.provision_trial(org); raise exception 'FAIL missing trial policy';
 exception when raise_exception then if sqlerrm<>'TRIAL_CONFIGURATION_REQUIRED' then raise;end if;end;
 insert into private.plans(code,name,price_inr,billing_interval,monthly_invoice_limit,staff_limit,location_limit)
 values('fixture_trial','Fixture',0,'month',0,1,1) returning id into plan;
 insert into private.trial_policy(plan_id,duration_days,enabled) values(plan,14,true);
 perform private.provision_trial(org);
 select period_end into first_end from private.subscriptions where organization_id=org;
 perform private.provision_trial(org);
 if (select period_end from private.subscriptions where organization_id=org)<>first_end then raise exception 'FAIL trial retry extended term';end if;
 begin perform private.require_entitlement(org,'invoice'); raise exception 'FAIL invoice cap';
 exception when raise_exception then if sqlerrm<>'PLAN_LIMIT_REACHED' then raise;end if;end;
 begin perform private.require_entitlement(org,'staff'); raise exception 'FAIL staff cap';
 exception when raise_exception then if sqlerrm<>'PLAN_LIMIT_REACHED' then raise;end if;end;
 begin perform private.require_entitlement(org,'location'); raise exception 'FAIL location cap';
 exception when raise_exception then if sqlerrm<>'PLAN_LIMIT_REACHED' then raise;end if;end;
 update private.plans set monthly_invoice_limit=null where id=plan;
 perform private.require_entitlement(org,'invoice');
 update private.subscriptions set status='expired' where organization_id=org;
 begin perform private.require_entitlement(org,'invoice'); raise exception 'FAIL expiry';
 exception when raise_exception then if sqlerrm<>'SUBSCRIPTION_EXPIRED' then raise;end if;end;
 update private.subscriptions set status='grace',grace_until=period_end+interval '1 day' where organization_id=org;
 perform private.require_entitlement(org,'invoice');
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$ begin
 if public.subscription_summary((select id from foundation_test_context where label='org_a'))->>'status'<>'grace' then raise exception 'FAIL owner summary';end if;
 if (public.subscription_summary((select id from foundation_test_context where label='org_a'))->'usage'->>'staff')::integer<>1 then raise exception 'FAIL staff usage';end if;
 if (public.subscription_summary((select id from foundation_test_context where label='org_a'))->'usage'->>'locations')::integer<>1 then raise exception 'FAIL location usage';end if;
 if (public.subscription_summary((select id from foundation_test_context where label='org_a'))->'usage'->>'invoices')::integer<>0 then raise exception 'FAIL invoice usage';end if;
 begin perform public.subscription_summary((select id from foundation_test_context where label='org_b')); raise exception 'FAIL tenant subscription leak';
 exception when insufficient_privilege then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
end $$;
reset role;
update private.subscriptions set status='active',period_start=now()-interval '2 days',period_end=now()-interval '1 day',grace_until=null
 where organization_id=(select id from foundation_test_context where label='org_a');
set local role authenticated;
do $$ begin
 if public.subscription_summary((select id from foundation_test_context where label='org_a'))->>'status'<>'expired' then raise exception 'FAIL stale active display';end if;
end $$;
reset role;
select 'Subscription lifecycle assertions passed; fixtures rolled back.' as result;
