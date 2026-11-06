-- Backdate only the rollback fixture; never mutate a real issued invoice.
update public.sales_invoices set invoice_date=(now() at time zone 'Asia/Kolkata')::date-2,due_date=(now() at time zone 'Asia/Kolkata')::date-1;
update public.customers set email='customer@example.invalid';
set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$ declare invoice public.sales_invoices%rowtype;req uuid:=gen_random_uuid();reply jsonb;begin
 select * into strict invoice from public.sales_invoices;
 begin perform public.queue_customer_reminder(req,invoice.organization_id,invoice.id,'email');raise exception 'FAIL queue without consent';
 exception when raise_exception then if sqlerrm<>'REMINDER_CONSENT_REQUIRED' then raise;end if;end;
 perform public.set_reminder_consent(gen_random_uuid(),invoice.organization_id,invoice.customer_id,'email',true,'Written customer opt-in',0);
 reply:=public.queue_customer_reminder(req,invoice.organization_id,invoice.id,'email');
 if reply<>public.queue_customer_reminder(req,invoice.organization_id,invoice.id,'email') then raise exception 'FAIL queue retry';end if;
 if (select count(*) from public.customer_reminder_jobs)<>1 then raise exception 'FAIL duplicate reminder';end if;
 begin perform public.queue_customer_reminder(gen_random_uuid(),invoice.organization_id,invoice.id,'email');raise exception 'FAIL cooldown bypass';
 exception when raise_exception then if sqlerrm<>'REMINDER_COOLDOWN' then raise;end if;end;
 perform public.set_reminder_consent(gen_random_uuid(),invoice.organization_id,invoice.customer_id,'email',false,'Customer opted out',1);
 if (select state from public.customer_reminder_jobs)<>'cancelled' then raise exception 'FAIL pending reminder not cancelled';end if;
 begin perform public.queue_customer_reminder(gen_random_uuid(),invoice.organization_id,invoice.id,'email');raise exception 'FAIL revoked consent queued';
 exception when raise_exception then if sqlerrm<>'REMINDER_CONSENT_REQUIRED' then raise;end if;end;
 begin update public.customer_reminder_jobs set state='delivered';raise exception 'FAIL client delivery claim';
 exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_b'),true);
do $$ begin
 if exists(select 1 from public.customer_reminder_jobs) then raise exception 'FAIL reminder tenant leak';end if;
 begin perform public.queue_customer_reminder(gen_random_uuid(),(select id from foundation_test_context where label='org_a'),gen_random_uuid(),'email');raise exception 'FAIL reminder tenant command';
 exception when insufficient_privilege then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
end $$;
reset role;
do $$ declare job public.customer_reminder_jobs%rowtype;prepared jsonb;begin
 select * into strict job from public.customer_reminder_jobs;
 -- Rearm only this rollback fixture to exercise dispatch-time revalidation.
 update public.customer_reminder_jobs set state='queued' where id=job.id;
 update public.customer_reminder_consent set allowed=true,version=job.consent_version where organization_id=job.organization_id and customer_id=job.customer_id and channel=job.channel;
 prepared:=private.prepare_customer_reminder(job.id);
 if prepared is null or (prepared->>'balance_due')::numeric<=0 then raise exception 'FAIL valid reminder preparation';end if;
 update public.customers set email='changed@example.invalid' where id=job.customer_id;
 if private.prepare_customer_reminder(job.id) is not null then raise exception 'FAIL changed contact prepared';end if;
 if (select state from public.customer_reminder_jobs where id=job.id)<>'cancelled' then raise exception 'FAIL invalid job not cancelled';end if;
 if has_function_privilege('authenticated','private.prepare_customer_reminder(uuid)','EXECUTE') then raise exception 'FAIL client dispatch preparation';end if;
end $$;
select 'Customer reminder queue assertions passed; fixtures rolled back.' as result;
