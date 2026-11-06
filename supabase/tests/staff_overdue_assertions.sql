select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$ declare org uuid;invoice uuid;due date;created integer;begin
 select id into org from foundation_test_context where label='org_a';
 select id,due_date into strict invoice,due from public.sales_invoices where organization_id=org;
 if private.invoice_outstanding(org,invoice)<>(public.sales_invoice_detail(org,invoice)->>'balance_due')::numeric then raise exception 'FAIL overdue balance mismatch';end if;
 if private.build_staff_overdue_alerts(org,due)<>0 then raise exception 'FAIL not overdue yet';end if;
 created:=private.build_staff_overdue_alerts(org,due+1);
 if created<>1 then raise exception 'FAIL overdue generation';end if;
 if private.build_staff_overdue_alerts(org,due+1)<>0 then raise exception 'FAIL overdue retry';end if;
 if private.build_staff_overdue_alerts(org,due+2)<>0 then raise exception 'FAIL rolling cooldown';end if;
 if exists(select 1 from public.notifications n join public.organization_members m on m.organization_id=n.organization_id and m.user_id=n.recipient_user_id where n.type='INVOICE_OVERDUE' and (m.status<>'active' or m.role not in ('owner','manager','accountant'))) then raise exception 'FAIL overdue recipient scope';end if;
 update public.notification_outbox set created_at=now()-interval '25 hours' where organization_id=org and event_type='INVOICE_OVERDUE';
 if private.build_staff_overdue_alerts(org,due+2)<>1 then raise exception 'FAIL cooldown release';end if;
 if has_function_privilege('authenticated','private.build_staff_overdue_alerts(uuid,date)','EXECUTE') then raise exception 'FAIL client alert generation';end if;
end $$;
select 'Staff overdue assertions passed; fixtures rolled back.' as result;
