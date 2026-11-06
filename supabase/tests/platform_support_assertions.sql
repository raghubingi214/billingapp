set local role authenticated;
do $$ begin
 begin perform 1 from public.platform_support_thread(gen_random_uuid());raise exception 'FAIL merchant platform thread';
 exception when insufficient_privilege then if sqlerrm<>'PLATFORM_ACCESS_DENIED' then raise;end if;end;
 begin perform 1 from public.platform_support_queue();raise exception 'FAIL merchant platform queue';
 exception when insufficient_privilege then if sqlerrm<>'PLATFORM_ACCESS_DENIED' then raise;end if;end;
end $$;
reset role;
insert into private.platform_admins(user_id) select id from foundation_test_context where label='outsider';
set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='outsider'),true);
do $$ begin
 if (select count(*) from public.platform_support_queue())<>1 then raise exception 'FAIL support queue count';end if;
 if (select kind from public.platform_support_queue())<>'account_closure' then raise exception 'FAIL request kind';end if;
 if exists(select 1 from public.support_requests) then raise exception 'FAIL broad support read granted';end if;
 declare command uuid:=gen_random_uuid(); support_id uuid; reply jsonb;begin
  select id into support_id from public.platform_support_queue();
  reply:=public.begin_support_review(command,support_id);
  if reply<>public.begin_support_review(command,support_id) then raise exception 'FAIL triage retry';end if;
  reply:=public.reply_to_support(command,support_id,'We are reviewing your request.');
  if reply<>public.reply_to_support(command,support_id,'We are reviewing your request.') then raise exception 'FAIL support reply retry';end if;
  if (select count(*) from public.platform_support_thread(support_id))<>1 then raise exception 'FAIL platform thread';end if;
  if exists(select 1 from public.platform_support_queue('open')) then raise exception 'FAIL triage open queue';end if;
  if (select count(*) from public.platform_support_queue('in_review'))<>1 then raise exception 'FAIL triage review queue';end if;
  begin perform public.begin_support_review(gen_random_uuid(),support_id);raise exception 'FAIL stale triage';
  exception when raise_exception then if sqlerrm<>'SUPPORT_STATUS_CHANGED' then raise;end if;end;
 end;
end $$;
reset role;
update private.platform_admins set active=false where user_id=(select id from foundation_test_context where label='outsider');
set local role authenticated;
do $$ begin
 begin perform 1 from public.platform_support_queue();raise exception 'FAIL revoked queue access';
 exception when insufficient_privilege then if sqlerrm<>'PLATFORM_ACCESS_DENIED' then raise;end if;end;
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$ begin
 if (select count(*) from public.support_replies)<>1 then raise exception 'FAIL owner reply visibility';end if;
 begin perform public.reply_to_support(gen_random_uuid(),(select id from public.support_requests limit 1),'Unauthorized reply');raise exception 'FAIL owner platform reply';
 exception when insufficient_privilege then if sqlerrm<>'PLATFORM_ACCESS_DENIED' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_b'),true);
do $$ begin
 if exists(select 1 from public.support_replies) then raise exception 'FAIL reply tenant leak';end if;
end $$;
reset role;
select 'Platform support assertions passed; fixtures rolled back.' as result;
