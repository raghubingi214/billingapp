create or replace function public.update_business_settings(p_request_id uuid,p_organization_id uuid,p_version integer,p_data jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
<<settings_command>>
declare org public.organizations%rowtype;settings public.business_settings%rowtype;
 payload jsonb;reply jsonb;name text;legal_name text;state text;regime text;gst text;address jsonb;prefix text;
 fy_start integer;fy text;doc text;
begin
 perform 1 from public.organizations where id=p_organization_id for update;
 if not private.has_role(p_organization_id,array['owner']) then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
 payload:=jsonb_build_object('organization_id',p_organization_id,'version',p_version,'data',p_data);
 reply:=private.replay('update_settings',p_request_id,payload);if reply is not null then return reply;end if;
 select * into org from public.organizations where id=p_organization_id;
 select * into settings from public.business_settings where organization_id=p_organization_id for update;
 if p_version is null or settings.version<>p_version then raise exception 'SETTINGS_VERSION_CONFLICT';end if;
 name:=trim(p_data->>'name');legal_name:=trim(p_data->>'legal_name');state:=p_data->>'state_code';
 regime:=p_data->>'tax_regime';gst:=nullif(upper(trim(p_data->>'gstin')),'');address:=p_data->'address';prefix:=p_data->>'prefix';
 if name is null or length(name) not between 1 and 160 or legal_name is null or length(legal_name) not between 1 and 200 then raise exception 'INVALID_BUSINESS_NAME';end if;
 if state is null or state !~ '^[0-9]{2}$' or state::integer not between 1 and 38 then raise exception 'INVALID_STATE';end if;
 if regime is null or regime not in ('unregistered','regular','composition') then raise exception 'INVALID_TAX_REGIME';end if;
 if regime='unregistered' and gst is not null then raise exception 'UNREGISTERED_GSTIN_NOT_ALLOWED';end if;
 if regime<>'unregistered' and (gst is null or gst !~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$' or left(gst,2)<>state) then raise exception 'INVALID_GSTIN';end if;
 if address is null or jsonb_typeof(address)<>'object' or length(address::text)>4000 or
 nullif(trim(address->>'line1'),'') is null or nullif(trim(address->>'city'),'') is null or
 coalesce(address->>'postal_code','') !~ '^[1-9][0-9]{5}$' then raise exception 'INVALID_ADDRESS';end if;
 if prefix is null or prefix !~ '^[A-Z0-9]{1,4}$' then raise exception 'INVALID_PREFIX';end if;
 update public.organizations set name=settings_command.name,legal_name=settings_command.legal_name,state_code=state,tax_regime=regime,gstin=gst,address=settings_command.address where id=p_organization_id;
 update public.outlets set name=settings_command.name,state_code=state,address=settings_command.address where organization_id=p_organization_id and is_default;
 fy_start:=extract(year from now() at time zone 'Asia/Kolkata')::integer;
 if extract(month from now() at time zone 'Asia/Kolkata')<4 then fy_start:=fy_start-1;end if;
 fy:=right(fy_start::text,2)||'-'||right((fy_start+1)::text,2);
 doc:=case regime when 'regular' then 'tax_invoice' when 'composition' then 'bill_of_supply' else 'commercial_invoice' end;
 update public.invoice_series set active=false where organization_id=p_organization_id and doc_type<>'credit_note';
 insert into public.invoice_series(organization_id,financial_year,doc_type,prefix) values(p_organization_id,fy,doc,prefix)
 on conflict(organization_id,doc_type,financial_year,prefix) do update set active=true;
 update public.business_settings set version=version+1,updated_at=now() where organization_id=p_organization_id;
 insert into public.audit_events(organization_id,actor_user_id,action,table_name,record_id,before_data,after_data,request_id)
 values(p_organization_id,auth.uid(),'business.settings_updated','organizations',p_organization_id,
 to_jsonb(org),p_data,p_request_id);
 reply:=jsonb_build_object('organization_id',p_organization_id,'version',settings.version+1);
 insert into private.command_receipts(actor_id,command_name,request_id,payload,response) values(auth.uid(),'update_settings',p_request_id,payload,reply);
 return reply;
end $$;
revoke all on function public.update_business_settings(uuid,uuid,integer,jsonb) from public,anon;
grant execute on function public.update_business_settings(uuid,uuid,integer,jsonb) to authenticated;
