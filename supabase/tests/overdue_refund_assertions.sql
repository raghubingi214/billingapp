select set_config('request.jwt.claim.sub',(select id::text from foundation_test_context where label='owner_a'),true);
do $$ declare invoice record;count_due integer:=0;generated integer;as_of date;org uuid;begin
 select id into org from foundation_test_context where label='org_a';
 select max(due_date)+1 into as_of from public.sales_invoices where organization_id=org;
 for invoice in select id from public.sales_invoices where organization_id=org loop
  if private.invoice_outstanding(org,invoice.id)<>(public.sales_invoice_detail(org,invoice.id)->>'balance_due')::numeric then raise exception 'FAIL refund overdue reconciliation';end if;
  if private.invoice_outstanding(org,invoice.id)>0 then count_due:=count_due+1;end if;
 end loop;
 if count_due<>0 then raise exception 'FAIL settled refund fixture has outstanding debt';end if;
 generated:=private.build_staff_overdue_alerts(org,as_of);
 if generated<>0 then raise exception 'FAIL paid/returned/refunded invoice generated overdue alert';end if;
end $$;
select 'Refund overdue assertions passed; fixtures rolled back.' as result;
