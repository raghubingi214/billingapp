create table public.report_exports(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),
 created_by uuid not null references auth.users(id),kind text not null,
 from_date date not null,to_date date not null,payload jsonb not null,
 created_at timestamptz not null default now()
);
create index report_exports_org_time on public.report_exports(organization_id,created_at desc);
create index report_exports_creator on public.report_exports(created_by);
alter table public.report_exports enable row level security;
revoke all on public.report_exports from public,anon,authenticated;
grant select on public.report_exports to authenticated;
create policy export_finance_read on public.report_exports for select to authenticated
 using(private.has_role(organization_id,array['owner','accountant']));
create function public.create_report_export(p_request_id uuid,p_organization_id uuid,p_kind text,p_from date,p_to date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb;reply jsonb;report jsonb;all_rows jsonb:='[]';offset_rows integer:=0;export_id uuid:=gen_random_uuid();
begin
 perform 1 from public.organizations where id=p_organization_id for update;
 if not private.has_role(p_organization_id,array['owner','accountant']) then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
 payload:=jsonb_build_object('organization_id',p_organization_id,'kind',p_kind,'from',p_from,'to',p_to);
 reply:=private.replay('report_export',p_request_id,payload);if reply is not null then return reply;end if;
 report:=public.financial_report(p_organization_id,p_kind,p_from,p_to,0);
 if (report->>'count')::bigint>50000 then raise exception 'EXPORT_REQUIRES_BACKGROUND_JOB';end if;
 loop
 all_rows:=all_rows||(report->'rows');
 exit when jsonb_array_length(report->'rows')<50;
 offset_rows:=offset_rows+50;
 report:=public.financial_report(p_organization_id,p_kind,p_from,p_to,offset_rows);
 end loop;
 reply:=report||jsonb_build_object('export_id',export_id,'rows',all_rows);
 insert into public.report_exports(id,organization_id,created_by,kind,from_date,to_date,payload)
 values(export_id,p_organization_id,auth.uid(),p_kind,p_from,p_to,reply);
 insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,after_data,request_id)
 values(p_organization_id,auth.uid(),'report.exported','report_exports',export_id,
 jsonb_build_object('kind',p_kind,'from',p_from,'to',p_to,'count',jsonb_array_length(all_rows)),p_request_id);
 insert into private.command_receipts(actor_id,command_name,request_id,payload,response)
 values(auth.uid(),'report_export',p_request_id,payload,reply);
 return reply;
end $$;
revoke all on function public.create_report_export(uuid,uuid,text,date,date) from public,anon;
grant execute on function public.create_report_export(uuid,uuid,text,date,date) to authenticated;
