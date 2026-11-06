begin;
do $$ begin
 if has_table_privilege('authenticated','private.plans','INSERT')
 or has_table_privilege('authenticated','private.subscriptions','UPDATE')
 or has_function_privilege('authenticated','private.provision_trial(uuid)','EXECUTE')
 or has_function_privilege('authenticated','private.require_entitlement(uuid,text)','EXECUTE') then
  raise exception 'FAIL client subscription authority';
 end if;
 begin
  insert into private.plans(code,name,price_inr,billing_interval,staff_limit)
  values('invalid_fixture','Fixture',0,'month',0);
  raise exception 'FAIL invalid staff limit accepted';
 exception when check_violation then null;end;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
 begin
  perform public.subscription_summary(gen_random_uuid());
  raise exception 'FAIL unauthorized summary';
 exception when insufficient_privilege then
  if sqlerrm<>'ACCESS_DENIED' then raise;end if;
 end;
end $$;
reset role;
select 'Subscription foundation assertions passed; fixtures rolled back.' as result;
rollback;
