set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$ declare org uuid; customer uuid;req uuid:=gen_random_uuid();reply jsonb;begin
 select id into org from foundation_test_context where label='org_a';
 customer:=(public.save_customer(gen_random_uuid(),org,null,null,'{"name":"Consent fixture","state_code":"36","email":"customer@example.invalid"}')->>'id')::uuid;
 insert into foundation_test_context(label,id) values('consent_customer',customer);
 reply:=public.set_reminder_consent(req,org,customer,'email',true,'Written customer opt-in',0);
 if reply<>public.set_reminder_consent(req,org,customer,'email',true,'Written customer opt-in',0) then raise exception 'FAIL consent retry';end if;
 if (select count(*) from public.customer_reminder_consent)<>1 then raise exception 'FAIL consent duplicate';end if;
 perform public.set_reminder_consent(gen_random_uuid(),org,customer,'email',false,'Customer opted out',1);
 if (select allowed from public.customer_reminder_consent) then raise exception 'FAIL consent revocation';end if;
 begin perform public.set_reminder_consent(gen_random_uuid(),org,customer,'email',true,'Stale opt-in',1);raise exception 'FAIL stale consent';
 exception when raise_exception then if sqlerrm<>'CONSENT_VERSION_CONFLICT' then raise;end if;end;
 begin perform public.set_reminder_consent(gen_random_uuid(),org,customer,'sms',true,'Written opt-in',0);raise exception 'FAIL invalid contact';
 exception when raise_exception then if sqlerrm<>'INVALID_REMINDER_RECIPIENT' then raise;end if;end;
 begin update public.customer_reminder_consent set allowed=true;raise exception 'FAIL direct consent mutation';
 exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_b'),true);
do $$ begin
 if exists(select 1 from public.customer_reminder_consent) then raise exception 'FAIL consent tenant leak';end if;
 begin perform public.set_reminder_consent(gen_random_uuid(),(select id from foundation_test_context where label='org_a'),(select id from foundation_test_context where label='consent_customer'),'email',false,'Cross tenant',2);raise exception 'FAIL tenant consent write';
 exception when insufficient_privilege then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
end $$;
reset role;
do $$ declare org uuid;customer uuid;begin
 select id into org from foundation_test_context where label='org_a';
 select id into customer from foundation_test_context where label='consent_customer';
 if private.reminder_consent_is_current(org,customer,'email',2) then raise exception 'FAIL revoked consent eligible';end if;
 update public.customer_reminder_consent set allowed=true,version=3 where organization_id=org and customer_id=customer;
 if not private.reminder_consent_is_current(org,customer,'email',3) then raise exception 'FAIL current consent ineligible';end if;
 if private.reminder_consent_is_current(org,customer,'email',1) then raise exception 'FAIL old consent job eligible';end if;
 update public.customers set email='changed@example.invalid' where id=customer;
 if private.reminder_consent_is_current(org,customer,'email',3) then raise exception 'FAIL changed recipient eligible';end if;
 update public.customers set email='customer@example.invalid',active=false where id=customer;
 if private.reminder_consent_is_current(org,customer,'email',3) then raise exception 'FAIL inactive customer eligible';end if;
end $$;
select 'Reminder consent assertions passed; fixtures rolled back.' as result;
