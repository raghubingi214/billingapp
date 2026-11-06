set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$ declare org uuid; req uuid:=gen_random_uuid(); first_reply jsonb;begin
 select id into org from foundation_test_context where label='org_a';
 first_reply:=public.submit_support_request(req,org,'account_closure','Closure request','Please review my closure request.');
 if first_reply<>public.submit_support_request(req,org,'account_closure','Closure request','Please review my closure request.') then raise exception 'FAIL support retry';end if;
 if (select count(*) from public.support_requests)<>1 then raise exception 'FAIL support duplicate';end if;
 if not exists(select 1 from public.organizations where id=org) then raise exception 'FAIL closure deleted business';end if;
 begin insert into public.support_requests(organization_id,requested_by,kind,subject,message) values(org,auth.uid(),'help','Test','Direct insertion attempt');raise exception 'FAIL direct support write';
 exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_b'),true);
do $$ begin
 if exists(select 1 from public.support_requests) then raise exception 'FAIL support tenant leak';end if;
 begin perform public.submit_support_request(gen_random_uuid(),(select id from foundation_test_context where label='org_a'),'export','Export request','Please export this business.');raise exception 'FAIL tenant command';
 exception when insufficient_privilege then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
end $$;
reset role;
select 'Support assertions passed; fixtures rolled back.' as result;
