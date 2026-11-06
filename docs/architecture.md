# Mobile application architecture

Authority: Smart_Billing_Inventory_Complete_BRD_FRD_Technical_Specification.docx, version 1.0, sections 7, 8 and 14. User overrides: Android and iPhone only; discard the earlier implementation and rebuild from this document.

## Dependencies and boundaries

Presentation widgets -> Riverpod controller -> domain use case -> repository interface -> Supabase repository -> authenticated API/RPC.

- app: bootstrap, router, theme and mobile navigation.
- core: environment, failures, validation and reusable widgets. No feature business logic.
- shared: organization membership and permissions shared across features.
- features/<feature>/domain: plain Dart entities, repository contracts and use cases. No Flutter, Riverpod or Supabase imports.
- features/<feature>/data: DTO mapping and repository implementations. Backend details stop here.
- features/<feature>/presentation: screens and Riverpod controllers. No direct database calls.
- integrations/supabase: client dependency injection.
- integrations/scanning: mobile camera adapter and injectable scan route. Catalog search and barcode entry consume text results. Sale entry matches active barcode/SKU exactly and asks for manual selection when missing or ambiguous; scanning never finalizes an invoice.
- integrations/firebase, printing and sharing: introduced with their actual implementations.
- l10n: English and Telugu resources during localization work.

Feature folders are added with working code, rather than empty scaffolding. Planned modules: auth, onboarding, dashboard, catalog, inventory, sales, purchases, customers, suppliers, payments, reports, notifications, settings and subscriptions.

## Backend invariants

Identity comes from Supabase Auth. Organizations own business records; active organization membership authorizes every read and command. Owner, manager, cashier and accountant permissions are enforced by PostgreSQL as well as represented in the UI. No client may assign its own role.

Onboarding is one transaction creating organization, owner membership, default outlet, settings, financial-year invoice series and audit event. Retry keys identify commands and reject changed payloads.

Subsequent financial commands will finalize sales, receive purchases, allocate payments and post adjustments atomically. Issued documents and stock movements are immutable. Monetary columns use numeric(18,2), quantities numeric(18,3). The server owns totals, numbering, stock, tax snapshots and permissions.

Read APIs use organization filters, bounded pagination and RLS. UI state is cleared on identity/organization changes. Membership is refreshed before entering the workspace and on app resume; backend membership checks remain authoritative between refreshes.

## Working defaults

India, INR, Asia/Kolkata; online first; one default outlet; email/password authentication with recovery OTP; no negative stock by default; weighted average costing planned. GST configuration is explicit and never presented as IRP registration. Firebase, payment provider, printer hardware and store signing need real project configurations during their respective phases.

## Verification

Domain unit tests, mobile widget tests (360dp and large text), repository/API tests, SQL tenant/role tests, retry/concurrency tests and Android builds. iOS compilation and device testing require macOS/Xcode. Mark each requirement verified only against its acceptance criteria.

## Platform administration

Platform privileges use private.platform_admins, independently of organization membership. Trusted operators provision verified user IDs; the mobile client has no self-promotion or service-role credential. Protected RPCs expose aggregate counts and a bounded business directory. Platform providers are scoped by user and depend on an access check; mobile resume invalidates that check. Merchant RLS remains in force for platform users.

Subscription work must enforce monthly invoice, staff, location, report and reminder limits on the server under concurrent requests (FR-028). S26 also requires trial/active/grace/expired/failed-renewal states, owner usage and renewal views, and server-verified payment webhooks. Payment provider and pricing decisions are still required before live subscription collection.
