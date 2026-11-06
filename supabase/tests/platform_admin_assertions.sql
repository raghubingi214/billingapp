set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$ begin
 if public.platform_admin_status() then raise exception 'FAIL merchant owner became platform admin';end if;
 begin perform public.platform_overview(); raise exception 'FAIL merchant read platform overview';
 exception when insufficient_privilege then if sqlerrm<>'PLATFORM_ACCESS_DENIED' then raise;end if;end;
 begin perform 1 from public.platform_businesses(0); raise exception 'FAIL merchant listed businesses';
 exception when insufficient_privilege then if sqlerrm<>'PLATFORM_ACCESS_DENIED' then raise;end if;end;
 begin insert into private.platform_admins(user_id) values(auth.uid()); raise exception 'FAIL self promotion';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
insert into private.platform_admins(user_id) select id from foundation_test_context where label='outsider';
set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='outsider'),true);
do $$ declare summary jsonb;begin
 if not public.platform_admin_status() then raise exception 'FAIL provisioned platform admin';end if;
 summary:=public.platform_overview();
 if (summary->>'businesses')::integer<>2 then raise exception 'FAIL platform count';end if;
 if (select count(*) from public.platform_businesses(0))<>2 then raise exception 'FAIL platform list';end if;
 if exists(select 1 from public.organizations) then raise exception 'FAIL platform admin bypassed merchant RLS';end if;
end $$;
reset role;
update private.platform_admins set active=false,revoked_at=now()
 where user_id=(select id from foundation_test_context where label='outsider');
set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='outsider'),true);
do $$ begin
 if public.platform_admin_status() then raise exception 'FAIL revoked platform access';end if;
 begin perform public.platform_overview(); raise exception 'FAIL revoked admin overview';
 exception when insufficient_privilege then if sqlerrm<>'PLATFORM_ACCESS_DENIED' then raise;end if;end;
end $$;
reset role;
select 'Platform admin isolation assertions passed; fixtures rolled back.' as result;
