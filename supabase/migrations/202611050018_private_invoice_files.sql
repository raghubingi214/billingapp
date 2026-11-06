insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('invoice-pdfs','invoice-pdfs',false,10485760,array['application/pdf'])
on conflict(id) do nothing;
create table public.invoice_pdf_jobs(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),
 invoice_id uuid not null,template_version integer not null default 1,
 status text not null default 'queued' check(status in ('queued','processing','ready','failed')),
 attempts integer not null default 0,next_attempt_at timestamptz not null default now(),
 last_error_code text,created_at timestamptz not null default now(),
 unique(invoice_id,template_version),unique(id,organization_id),
 foreign key(invoice_id,organization_id) references public.sales_invoices(id,organization_id)
);
create index pdf_jobs_org on public.invoice_pdf_jobs(organization_id);
create index pdf_jobs_ready on public.invoice_pdf_jobs(status,next_attempt_at);
create table public.file_assets(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),
 invoice_id uuid not null,template_version integer not null,
 bucket text not null check(bucket='invoice-pdfs'),path text not null,
 mime text not null default 'application/pdf' check(mime='application/pdf'),
 sha256 text not null check(sha256 ~ '^[0-9a-f]{64}$'),created_at timestamptz not null default now(),
 unique(invoice_id,template_version),unique(bucket,path),
 foreign key(invoice_id,organization_id) references public.sales_invoices(id,organization_id),
 check(path=organization_id::text||'/'||invoice_id::text||'/v'||template_version::text||'.pdf')
);
create index file_assets_org on public.file_assets(organization_id);
alter table public.invoice_pdf_jobs enable row level security;
alter table public.file_assets enable row level security;
revoke all on public.invoice_pdf_jobs,public.file_assets from public,anon,authenticated;
grant select on public.invoice_pdf_jobs,public.file_assets to authenticated;
create policy pdf_job_invoice_read on public.invoice_pdf_jobs for select to authenticated
 using(exists(select 1 from public.sales_invoices i where i.id=invoice_id and i.organization_id=invoice_pdf_jobs.organization_id));
create policy asset_invoice_read on public.file_assets for select to authenticated
 using(exists(select 1 from public.sales_invoices i where i.id=invoice_id and i.organization_id=file_assets.organization_id));
create policy invoice_pdf_download on storage.objects for select to authenticated
 using(bucket_id='invoice-pdfs' and exists(
 select 1 from public.file_assets f where f.bucket=bucket_id and f.path=name));
-- No client INSERT/UPDATE/DELETE policy: trusted worker alone writes canonical artifacts.
create function private.queue_invoice_pdf() returns trigger language plpgsql set search_path='' as $$
begin
 insert into public.invoice_pdf_jobs(organization_id,invoice_id) values(new.organization_id,new.id);
 return new;
end $$;
revoke all on function private.queue_invoice_pdf() from public,anon,authenticated;
create trigger invoice_pdf_on_issue after insert on public.sales_invoices
 for each row execute function private.queue_invoice_pdf();
