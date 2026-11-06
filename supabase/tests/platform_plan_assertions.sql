set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$ begin
 begin perform public.create_platform_plan_draft(gen_random_uuid(),'{}');raise exception 'FAIL merchant created plan';
 exception when insufficient_privilege then if sqlerrm<>'PLATFORM_ACCESS_DENIED' then raise;end if;end;
end $$;
reset role;
insert into private.platform_admins(user_id) select id from foundation_test_context where label='outsider';
set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='outsider'),true);
do $$ declare req uuid:=gen_random_uuid();data jsonb;reply jsonb;begin
 data:=jsonb_build_object('code','fixture_'||replace(auth.uid()::text,'-',''),'name','Fixture Starter','price_inr','199.00','billing_interval','month','monthly_invoice_limit',1000,'staff_limit',2,'location_limit',1,'monthly_reminder_limit',0,'report_types','[]'::jsonb);
 reply:=public.create_platform_plan_draft(req,data);
 if reply<>public.create_platform_plan_draft(req,data) then raise exception 'FAIL plan retry';end if;
 if (reply->>'active')::boolean then raise exception 'FAIL draft activated';end if;
 if (select count(*) from public.platform_plan_catalog() where id=(reply->>'id')::uuid)<>1 then raise exception 'FAIL plan catalog';end if;
 begin insert into private.plans(code,name,price_inr,billing_interval) values('unauthorized_fixture','Invalid',0,'month');raise exception 'FAIL direct plan write';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
select 'Platform plan assertions passed; fixtures rolled back.' as result;
