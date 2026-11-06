create table public.customer_reminder_consent (
 organization_id uuid not null,
 customer_id uuid not null,
 channel text not null check(channel in ('email','sms','whatsapp')),
 allowed boolean not null default false,
 recipient text not null,
 evidence text not null check(length(trim(evidence)) between 3 and 500),
 version integer not null default 1 check(version>0),
 updated_by uuid not null references auth.users(id),
 updated_at timestamptz not null default now(),
 primary key(organization_id,customer_id,channel),
 foreign key(customer_id,organization_id) references public.customers(id,organization_id)
);
create index reminder_consent_actor_idx on public.customer_reminder_consent(updated_by);
alter table public.customer_reminder_consent enable row level security;
revoke all on public.customer_reminder_consent from public,anon,authenticated;
grant select on public.customer_reminder_consent to authenticated;
create policy reminder_consent_finance_read on public.customer_reminder_consent for select to authenticated
 using(private.has_role(organization_id,array['owner','manager','accountant']));

create function public.set_reminder_consent(p_request_id uuid,p_organization_id uuid,p_customer_id uuid,p_channel text,p_allowed boolean,p_evidence text,p_version integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare customer public.customers%rowtype;previous public.customer_reminder_consent%rowtype;
 payload jsonb;reply jsonb;recipient text;next_version integer;begin
 perform 1 from public.organizations where id=p_organization_id for update;
 if not private.has_role(p_organization_id,array['owner','manager']) then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
 payload:=jsonb_build_object('org',p_organization_id,'customer',p_customer_id,'channel',p_channel,'allowed',p_allowed,'evidence',trim(p_evidence),'version',p_version);
 reply:=private.replay('reminder_consent',p_request_id,payload);
 if reply is not null then return reply;end if;
 if p_channel is null or p_channel not in ('email','sms','whatsapp') or p_allowed is null
 or p_evidence is null or length(trim(p_evidence)) not between 3 and 500 then raise exception 'INVALID_CONSENT';end if;
 select * into customer from public.customers where id=p_customer_id and organization_id=p_organization_id for update;
 if not found then raise exception 'CUSTOMER_NOT_FOUND';end if;
 select * into previous from public.customer_reminder_consent where organization_id=p_organization_id and customer_id=p_customer_id and channel=p_channel;
 if p_version is null or p_version<>coalesce(previous.version,0) then raise exception 'CONSENT_VERSION_CONFLICT';end if;
 recipient:=case when p_channel='email' then lower(trim(customer.email)) else trim(customer.phone) end;
 if p_allowed and (not customer.active or (p_channel='email' and recipient !~ '^[^ @]+@[^ @]+[.][^ @]+$')
 or (p_channel<>'email' and recipient !~ '^[+][1-9][0-9]{7,14}$')) then raise exception 'INVALID_REMINDER_RECIPIENT';end if;
 next_version:=coalesce(previous.version,0)+1;
 insert into public.customer_reminder_consent(organization_id,customer_id,channel,allowed,recipient,evidence,version,updated_by)
 values(p_organization_id,p_customer_id,p_channel,p_allowed,recipient,trim(p_evidence),next_version,auth.uid())
 on conflict(organization_id,customer_id,channel) do update set allowed=excluded.allowed,recipient=excluded.recipient,evidence=excluded.evidence,version=excluded.version,updated_by=excluded.updated_by,updated_at=now();
 insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,before_data,after_data,request_id)
 values(p_organization_id,auth.uid(),'customer.reminder_consent','customer_reminder_consent',p_customer_id,
 jsonb_build_object('channel',p_channel,'allowed',previous.allowed),jsonb_build_object('channel',p_channel,'allowed',p_allowed,'version',next_version),p_request_id);
 reply:=jsonb_build_object('version',next_version,'allowed',p_allowed);
 insert into private.command_receipts(actor_id,command_name,request_id,payload,response) values(auth.uid(),'reminder_consent',p_request_id,payload,reply);
 return reply;
end $$;
revoke all on function public.set_reminder_consent(uuid,uuid,uuid,text,boolean,text,integer) from public,anon;
grant execute on function public.set_reminder_consent(uuid,uuid,uuid,text,boolean,text,integer) to authenticated;
