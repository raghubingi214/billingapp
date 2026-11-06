# Specification implementation tracker

Source: D:/Downloads/Smart_Billing_Inventory_Complete_BRD_FRD_Technical_Specification.docx, version 1.0.

The earlier Flutter demo and per-user billing schema were removed at the user's request. Six prior tables were checked empty before removal. Supabase connection retained. This rebuild starts from the specification.

## Delivery phases

| Phase | Status | Exit evidence required |
|---|---|---|
| 0 Discovery | Document read; working defaults recorded | Merchant interviews, tax review and validation of three flows remain external |
| 1 Foundation | In progress | Auth, onboarding, roles, mobile shell and tenant isolation tests |
| 2 Catalog and stock | Implemented in part; validation gaps remain | Product CRUD, purchases, reconciled immutable movements, low stock |
| 3 Sales and receipts | Implemented in part; validation gaps remain | Draft, quote, exactly-once issue, GST math, private PDF, payments, ledger, returns |
| 4 Reports and notifications | Reports, in-app notifications, audit and settings partially implemented | Reconciled exports, outbox, FCM, audit and settings |
| 5 Pilot and release | Pending | Device QA, backups/restore, monitoring, legal/support pages, signing and merchant acceptance |
| 6 Enhancements | Deferred per document | Separately scoped integrations and multi-outlet capabilities |

## Functional requirements

| ID | Requirement | Status |
|---|---|---|
| FR-001 | Auth/logout/recovery | In progress |
| FR-002 | Atomic organization onboarding | In progress |
| FR-003 | Staff invites and RBAC | In progress |
| FR-004 | Organization switching | Partial; see evidence and remaining gaps |
| FR-005 | Product/service master | Partial; see evidence and remaining gaps |
| FR-006 | Search and scan | Partial; see evidence and remaining gaps |
| FR-007 | Stock balances and ledger | Partial; see evidence and remaining gaps |
| FR-008 | Low-stock alerts | Partial; see evidence and remaining gaps |
| FR-009 | Stocktake and approvals | Partial; see evidence and remaining gaps |
| FR-010 | Barcode and images | Partial; scanner, private image upload/view/removal and retry tests implemented; storage/device validation and cleanup pending |
| FR-011 | Sales drafts | Partial; see evidence and remaining gaps |
| FR-012 | Atomic invoice issue | Partial; see evidence and remaining gaps |
| FR-013 | Split payment methods | Partial; see evidence and remaining gaps |
| FR-014 | Private PDF/share/print | Partial; see evidence and remaining gaps |
| FR-015 | Customer credit sales | Partial; see evidence and remaining gaps |
| FR-016 | Sales returns/credit notes | Partial; see evidence and remaining gaps |
| FR-017 | Deterministic discounts/GST | Partial; see evidence and remaining gaps |
| FR-018 | Suppliers | Partial; see evidence and remaining gaps |
| FR-019 | Purchases and receipt | Partial; see evidence and remaining gaps |
| FR-020 | Supplier payments | Partial; see evidence and remaining gaps |
| FR-021 | Purchase returns | Partial; return and supplier refund flows wired; valuation and device validation pending |
| FR-022 | Customers/credit limits | Partial; see evidence and remaining gaps |
| FR-023 | Customer ledger/statements | Partial; see evidence and remaining gaps |
| FR-024 | Consented overdue reminders | Partial; consent UI, audited queue, cooldown, cancellation and staff generator implemented/tested; scheduling, worker/provider delivery and concurrency validation pending |
| FR-025 | Dashboard KPIs | Partial; see evidence and remaining gaps |
| FR-026 | Filtered reports/exports | Partial; see evidence and remaining gaps |
| FR-027 | Immutable audit | In progress |
| FR-028 | Server plan entitlements | Partial foundation; summary/usage and lifecycle checks implemented; enforcement migration remains unapplied |
| FR-029 | GST/invoice settings | Partial; owner settings implemented, tax review pending |
| FR-030 | In-app/FCM notifications | Partial; in-app feed implemented, FCM pending |
| FR-031 | Support/export/deletion | Partial; owner requests, platform triage/replies and mobile history implemented; export generation, retention review and closure fulfillment pending |

## Screens and acceptance

Implemented in part: S01–S03 auth/onboarding; S04 live summary; S05–S11 sale drafts/checkout/details; S12–S14 catalog and stock; S15 owner stock count; S16 low-stock filter; S17–S19 customers/ledger/receipt; S20–S21 suppliers/purchases; S22 basic reports; S25 team. Full screen acceptance, remaining sections, and UAT-01–UAT-12 are unproven. SQL fixture and widget evidence do not substitute for device/pilot acceptance. Loading, empty, error, accessibility, audit, API and permission evidence are required before a feature is complete.

## External dependencies

Firebase Android/iOS configuration and server sender credentials; APNs configuration; chosen gateway and webhook credentials; printer models; GST professional review; production domains, policy text, signing identities and store accounts; pilot merchants. These do not block implementing the independent application and database layers.

## Implementation evidence 2026-11-05

- Purchase-return mobile retry now saves the immutable confirmed command under the current actor, organization and purchase before sending. The same UUID and line payload are restored after reopening and retried without a second preview; other users cannot see the stored command. Focused lost-response and storage tests passed. Persistence uses app-local SharedPreferences; device restart testing remains pending.
- Flutter analyzer clean and Android debug APK rebuilt after purchase-return retry fix.

- Supplier credit refund settlement applied: tenant-scoped immutable refund rows, owner/manager retry-safe posting, cap against paid plus returned less original bill and prior refunds, bill detail reconciliation, and positive cash-flow entries. Rollback-only SQL fixture passed partial/full settlement, retry, cap, direct-write denial and cash-flow total. Mobile purchase detail links to a refund form with local amount validation and confirmation; focused refund widget test passed. Live device flow and inventory cost valuation remain pending.
- Flutter analyzer clean and Android debug APK rebuilt after supplier refund integration.

- Purchase-return reconciliation applied: bill detail now exposes returned total, net payable, remaining due, supplier credit due, returned quantity and return history; supplier payment RPC caps allocations at net payable; purchase report/export includes negative return rows. Rollback-only fixture passed exact payment cap, supplier credit due after a second return and net report total. Mobile bill displays these amounts and limits return/payment inputs locally; focused purchase widget tests passed. Supplier-credit refund/settlement, weighted-average valuation treatment and device testing remain pending.
- Flutter analyzer clean and Android debug APK rebuilt after purchase-return mobile reconciliation.

- Purchase-detail mobile return form now collects per-line quantities, reason and optional credit reference; validates the received quantity and decimals locally, asks the server to preview credit, confirms, then posts through the retry-safe RPC and reloads detail. Focused purchase widget tests passed, including invalid quantity blocked before preview and server amount shown before post. The current purchase detail/payment/report views still need returned-credit reconciliation, and real-device flow remains unverified.

- Purchase-return posting RPC applied. It locks the organization, revalidates preview, checks unreserved stock, writes immutable return/line rows, negative stock movements, audit event and retry receipt in one transaction. Rollback-only fixtures passed amount, identical retry, cumulative quantity cap and movement/balance reconciliation. Supplier payment caps, bill/credit reporting, refund settlement and mobile entry remain pending.

- Purchase-return foundation applied: tenant-scoped return header/items with read-only client grants and owner/manager `preview_purchase_return` RPC. Preview validates unique positive quantities, cumulative return cap, stock availability and proportional original tax/cost rounding without writing business rows. Rollback-only purchase fixture passed preview amount, cap, duplicate, direct-write and cross-tenant assertions. Posting command, supplier-credit settlement, report reconciliation and mobile form remain pending.

- Audit history mobile detail now displays the stored before/after JSON snapshots when present. Owner/accountant RLS still controls the read. Flutter analyzer clean; live role and device review pending.
- Android debug APK rebuilt successfully after the audit detail change; device review remains pending.

- Camera barcode scanner integrated into catalog search, product barcode entry and sale entry using mobile_scanner 7.5.0. Android/iOS camera declarations added; plugin manages camera lifecycle. Scans retain leading zeroes, cancel preserves search, and sale entry matches active barcode/SKU exactly without posting a sale. Unknown/ambiguous matches require manual selection. Analyzer clean and 38 Flutter tests passed. Actual camera/permission/device tests and iPhone compilation remain unverified; product images remain pending.
- Android debug build including the native scanner dependency succeeded; APK updated at build/app/outputs/flutter-apk/app-debug.apk. Scanner configuration reference: https://pub.dev/packages/mobile_scanner/versions/7.5.0.

- Stock movement history now loads older pages beyond the first 50 entries, retains loaded rows after a failed page, and retries at the same offset. Full Flutter regression suite: 35 tests passed, including history paging/retry. Device acceptance remains pending.
- Final validation after approval/history integration: Flutter analyzer clean; Android debug APK rebuilt successfully from final source at build/app/outputs/flutter-apk/app-debug.apk. No Android device run or iOS build verified.

- Mobile stock approvals connected: managers submit counted quantity and reason from Inventory without posting stock; owners review pending requests with confirmation, and managers can view request status. Version conflicts require a fresh count. Backend authorization remains authoritative. Device acceptance remains pending.
- Flutter regression suite: 34 tests passed, including manager request routing without direct stock posting, owner confirmation and removal of completed review actions, and manager read-only approval history.

- Manager stock-adjustment requests and owner review backend applied with versioned posting, approval notifications, audit and retry protection. SQL passed for manager request retry/no stock change, self-approval denial, owner approval retry and ledger reconciliation. Mobile request/review screens and stale-approval UX remain pending.

- Owner mobile business settings connected with profile/address, tax regime/GSTIN and future invoice prefix, confirmation/version checks and membership refresh. Backend tests proved old snapshots and numbering history remain unchanged. Settings widget tests, signature/logo/terms/template settings and tax review remain pending.

- Versioned owner business/tax/prefix settings backend added with audit and retry handling. Active future series changes preserve old numbering history and issued snapshots. Settings SQL verification is underway; mobile settings UI and broader tax review remain pending.

- Phone-width (360dp), 1.6x text navigation tests passed for four tabs, accountant no-sale action, owner sale action and business-switch tab reset. Added paged read-only owner/accountant audit timeline. Full before/after drilldown, audit UI tests and real-device validation remain pending.

- Mobile workspace now follows Home / Sales / Inventory / More navigation with persistent New Sale for authorized roles. Organization changes reset tab selection, and More exposes existing business tools. Navigation/device accessibility tests and organization-wide refresh after cross-tab mutations remain pending.

- Notification widget tests passed for unread-only filtering/mark-read removal and error retry. Added delayed catalog response regression to verify newer search results win. FCM push remains unconfigured and no device delivery is claimed.

- Catalog search now queries full tenant catalog by name/SKU/barcode before paging, with debounced input and discarded stale responses. SQL case-insensitive match/no-match/archive checks passed. 5k-item latency target and scanner remain pending.

- Durable in-app notifications/outbox applied for invoice, receipt, purchase, return and refund events. Recipient/member RLS, mark-read RPC and event dedupe tests passed. Mobile feed supports unread filter, paging and authorized invoice/purchase navigation. FCM configuration/dispatch, preferences, scheduled low-stock/overdue digests and notification widget tests remain pending.

The matrix above is the current scope status. Milestone notes below preserve partial results; later implementations may supersede a pending item in an older note. No full-release completion is claimed.

- Full-period export tested with 56 posted purchases across two API pages: 56 unique rows and INR 477.63 total, with all fixtures rolled back.

- Mobile full CSV export/sharing added from audited server snapshots with filter/timestamp/currency/reconciliation metadata and spreadsheet formula-safe text escaping. Native share sheet includes iPad anchor. Real-device sharing and multi-page SQL export fixture remain pending.

- Audited full-period export snapshots applied: server iterates report pages under organization command lock, preserves filters/totals/timestamp, rejects over-50k exports for a future background job and makes snapshot/audit retry-safe. SQL passed for snapshot totals, retry uniqueness, audit creation and client-delete denial. Multi-page export fixture, CSV generation/sharing and PDF export remain pending.

- Mobile owner/accountant reports screen connected for sales/credits, purchases and cash flow, with date filters, full-period server totals, generated timestamp and paged details. CSV/PDF exports, report widget tests, stock/profit/aging/GST views and manager grants remain pending.

- Owner/accountant financial report RPC applied with date-filtered paged sales/credit notes, purchases and net receipt/payment/refund activity. SQL reconciled net sales, vendor bills and cash flow including supplier disbursements. Mobile report UI, CSV/PDF export, stock/profit/aging/GST-specific reports and export audits remain pending.

- Mobile owner refund entry added when invoice has refundable credit, with amount/method/reference/reason validation, explicit confirmation of an already-paid refund, retry key and balance refresh. Gateway execution is not implied. Refund-history display, approval workflow and full live UAT remain pending.

- Refunds now reconcile invoice refund-due/refunded totals, customer ledger debits, net dashboard collections and credit exposure. SQL passed for paid sale -> partial return -> refund: zero due/refund due, zero customer balance, and matching net sales/collections. Mobile refund settlement remains pending.

- Owner refund settlement backend applied with credited-paid-balance cap, immutable records, unique non-cash references, reason/audit and retry handling. SQL passed for exact refund, retry without duplication, over-refund rejection and delete denial. Refund-aware ledger/dashboard/detail updates and mobile refund entry remain pending.

- Mobile owner return screen added from invoice detail: original-line quantities, previously returned quantity, reason, optional goods restock, confirmation and retry key. Backend remains authoritative for caps/tax/permissions. Manager approval, refund settlement, credit-note PDF/history and device UAT remain pending.

- Credit notes integrated into invoice balance/refund-due values, returned quantities, ledger credits, net dashboard sales/outstanding and credit exposure. SQL reconciliation passed after a complete multi-part return: zero due, exact credited total, returned quantity cap, zero customer ledger and net sales. Refund settlement and mobile return entry remain pending.

- Owner-authorized linked sales return backend applied: immutable credit notes, original tax components, cumulative rounding, per-line return caps, optional restock and retry/audit. Receipt caps now subtract credited amounts. SQL passed for retry, restock, over-return rejection, post-credit receipt cap and exact full-return cumulative total. Invoice/ledger/dashboard credit presentation, refunds, approval workflow and return mobile UI remain pending.

- Customer running ledger backend/mobile screen added with date filters, opening/closing balances and paged invoice/receipt events. SQL reconciled receipt advances and subsequent-period opening balance. Statement export, return credits and ledger-specific widget tests remain pending.

- Deployed authenticated invoice-pdf endpoint: verifies identity and scoped invoice access, generates from server snapshots, writes immutable private path, stores checksum/version metadata and returns a 60-second signed link after access recheck. Mobile invoice preview downloads this canonical file. Unauthenticated endpoint probe correctly returned 401. Positive authenticated end-to-end execution, server PDF visual QA, bundled/pinned server fonts, scheduled queue retries and thermal output remain pending. Local template visual QA does not prove server layout quality.

- Private invoice PDF bucket, immutable client-facing asset metadata and transactional PDF job queue applied. Issuance queues one versioned job in the invoice transaction. SQL passed for queue uniqueness, private bucket, denied client metadata/job mutation and cross-tenant job isolation. Trusted PDF worker, signed retrieval integration and canonical file generation remain pending; mobile preview currently renders locally.

- Invoice PDF fixture generated from issued snapshots; PDF test passed. Poppler confirmed one A4 page, and rendered page visually inspected with clean table/totals/footer and no clipping. This covers the 12-line English sample only; multi-page, multilingual, thermal and private immutable storage remain pending.

- Added offline-font A4 invoice renderer and mobile preview/share/print entry from issued snapshots. Renderer excludes changing receipt balances to keep issued content stable. Visual render QA, private immutable server storage, thermal template, multilingual shaping, signatures/logo and legal-field review remain pending. FR-014 is not complete.

- Live mobile dashboard added with Today/7/30-day sales and collections, all-date invoice outstanding, low-stock pairs and refresh timestamp. Cashier financial totals restricted to own activity. SQL reconciliation test passed for invoice sales, received cash including advance, allocated outstanding and low stock. Returns/net-sales adjustments, trend chart, outlet filter and dashboard widget tests remain pending.

- Mobile walk-in selection added to new/resumed sales. Customer picker becomes optional for guest drafts; issuing without tender is blocked locally and full-payment enforcement remains server-side. Registered-tax recipient requirements and full live checkout UAT remain pending.

- Guest checkout backend added using nullable customer references and a minimal Walk-in invoice snapshot; no synthetic contact record. Guest credit is rejected and receipts must be fully allocated. Guest mobile selection and tax-required recipient-field checks remain pending; no GST compliance acceptance claimed.

- Checkout confirmation now shows entered tender breakdown, with clear-payments control before confirmation. Added regression proving split checkout retries preserve tender amounts/methods/references after mutable input changes. Guest checkout and persisted pending-command recovery remain pending.

- Mobile sale editor now captures up to ten tender methods with positive decimal amounts and non-cash references, calling atomic checkout when tenders are present. Pending invoice retries retain deep-copied tenders alongside quote/draft. Mobile split-specific tests, tender removal/edit UX, guest checkout and cross-restart retry recovery remain pending.

- Atomic named-customer split checkout backend applied. Invoice/stock/number and all tender receipts commit in one transaction; credit limit checks only residual dues. Private issue helper prevents clients claiming fictitious initial payments. SQL passed for cash+bank tender, zero-credit-limit fully paid sale, same checkout retry, single stock deduction and exact allocations. Mobile split-tender form and guest checkout remain pending.

- Customer receipt entry integrated into invoice details for authorized sales staff, including positive decimal amount, method/reference, confirmation, same-request retry key and refreshed server balance. Accountant views omit receipt entry. Multi-invoice mobile allocation, advances UI, receipt artifacts and cross-restart retry persistence remain pending.

- Mobile invoice issuance retains a deep copy of the confirmed draft/quote/request key after an ambiguous failure. Retry resends that exact command without another draft save. A regression test simulates a lost response and mutated form inputs. Cross-restart pending-command persistence remains pending.

- Mobile sales draft list/editor added with product/service lines, quantity/discount, limited customer picker, outlet/place-of-supply, notes, draft save/resume, authoritative quote review and confirmed credit issuance. Accountant action hidden; backend permission checks remain authoritative. Mobile issue retry recovery after ambiguous network outcomes, UI-specific tests, receipt entry, guest/split checkout and PDF remain pending.

- Mobile sales list and immutable invoice detail views connected. Authorized sales detail read computes balances across all applied receipts, avoiding partial RLS sums for cashiers. Limited customer picker exposes only ID/name/state. SQL passed for detail balances and picker results. Mobile draft/quote/issue and receipt entry remain pending.

- Customer receipt backend applied: partial/multi-invoice allocations, unapplied advances, unique non-cash references, permission checks, balance caps and audit/retries. Credit exposure now subtracts allocated receipts. SQL passed for receipt retry, unapplied remainder, overpayment/over-allocation rejection and tenant isolation. Later advance allocation, refunds, receipt/mobile sales screens remain pending.

- Atomic credit invoice issue applied: quote equality/version checks, FY numbering, immutable business/customer/line snapshots, grouped stock deduction, credit-limit check, audit and retry protection. SQL tests passed for one invoice/number/stock deduction on retry, stock reconciliation, finalized-write denial and tenant isolation. Credit exposure currently sums issued invoices until receipt/credit integration; guest/split-tender checkout, payments, returns, durable outbox/PDF and sales UI remain pending.

- Android debug APK successfully built at build/app/outputs/flutter-apk/app-debug.apk after Kotlin cache configuration change. This proves native compilation, not device behavior or iOS compilation.
- Sales quote backend revalidates membership/draft version, current product prices, available stock, discounts and explicit merchant tax regime. Quotes reserve neither stock nor numbers. Invoice issue and sales mobile workflows remain pending.

- Sales draft backend and decimal line calculator applied. Tests passed for documented discount/GST example, inclusive interstate math, draft retries/version conflicts, no stock change and no number reservation. Quote/issuance, customer-safe picker, payments, sales UI and tax-review acceptance remain pending. Android retry build still running at this checkpoint.

- Customer mobile list and create/edit forms connected with addresses, state/GSTIN consistency and optional credit-limit validation. Customer-specific widget tests and sales-safe lookup remain pending.
- First Android debug build failed in shared_preferences_android Kotlin incremental caches. Disabled incremental Kotlin compilation and selected in-process compiler; retry pending. No APK success claimed.

- Customer backend applied with protected PII, address/state/GST fields, credit limits, audit, retry and version checks. SQL assertions passed for retry, stale version, credit precision and tenant isolation. Customer mobile UI, cashier-safe sales lookup and credit-limit enforcement at invoice issue remain pending.

- Two purchase payment widget tests passed: read-only users have no payment form and invalid zero amounts never reach the repository. Android debug build started for native compilation verification; outcome pending.

- Purchase detail screen shows immutable supplier/product snapshots, lines, totals, applied payments and server-calculated balance. Owner/manager payment entry uses confirmation, reference validation and retry key reuse. purchase_detail SQL tests passed for exact paid/balance totals and line/payment history. Dedicated payment widget tests, drafts and full device UAT remain pending.

- Supplier payments backend applied: atomic multi-bill allocations, server balance caps, immutable payment records, unique non-cash references, permission checks, audit and retries. SQL passed for partial allocation/retry, overpayment rejection, duplicate digital reference rollback and tenant isolation. Payment mobile UI and opening-balance settlement remain pending.

- Mobile purchase list and receipt entry connected: supplier/outlet/product options, multi-line quantities/cost/tax, duplicate product validation, bill date/number, confirmation and retry key reuse on unchanged requests. Posted records shown in paged list. Purchase details/drafts, persisted retry keys, supplier payments and purchase-specific widget tests remain pending.

- Purchase receipt backend applied: atomic posted bill/line snapshots, decimal totals, stock movements/balance updates, weighted average base-cost update, audit and retry receipts. SQL passed for exact totals, retry, duplicate supplier bill rejection without stock change, ledger reconciliation, immutable client records and tenant isolation. Purchase drafts/mobile posting, tax split review, supplier payments and unknown opening-stock valuation remain pending.

- Supplier mobile list and create/edit forms connected to backend commands. Owner/manager editing, accountant browsing, paged results, contact fields, payment terms and immutable opening balance are represented. Supplier-specific widget tests, duplicate warnings, archive controls and purchase receipt workflow remain pending.

- Supplier backend applied: tenant-scoped contact/tax fields, payment terms, immutable opening balance, archive flag, audited retry-safe updates and version conflict checks. SQL assertions passed for retry, opening-balance protection, stale update rejection, direct-write denial and tenant isolation. Supplier mobile UI, duplicate warnings and purchase posting remain pending.

- Added RLS-preserving inventory_positions RPC with outlet validation and full-catalog low-stock filtering before pagination. Mobile stock screen exposes low-stock toggle. Query tests passed for normal positions and exclusion of above-threshold stock; daily notification dispatch and suggested reorder workflow remain pending.

- Inventory widget regressions passed: cashier balance access without count/history actions, count precision/reason validation, and owner movement history. Current Flutter validation: analyzer clean, 15 tests passed.

- Mobile inventory screens now load outlet-scoped stock positions, display latest 50 movements to authorized roles, and post owner stock counts with quantity/reason validation and version conflict feedback. Paging covers stock positions. Full history paging, low-stock center, purchase receipts, approval requests and inventory-specific widget tests remain pending.

- Stock ledger migration applied: composite tenant/outlet/product integrity, immutable client ledger access, versioned owner stock counts, required reasons, retry protection and audit records. SQL tests passed for count retry, ledger/balance reconciliation, stale-count rejection, denied direct writes/deletes and cross-tenant isolation. Stock mobile screens, manager approval workflow and purchase receipts remain pending.

- Mobile catalog list/editor now wired to save_product, with 50-row paging, search within loaded rows, active/archive filter, product/service fields and archive/restore confirmation. Owner/manager mutation actions are shown; backend still authorizes commands. Full server search, images, scanner, editor widget tests and stock ledger remain pending.

- Phase 2 catalog migration applied: tenant-scoped product/service master, decimal money, unique SKU, version conflict checks, archive flag, retry-safe audited save_product RPC. Mobile catalog UI and inventory posting remain pending. Catalog SQL assertions cover retries, duplicate SKU rejection, stale version rejection, decimal precision and tenant isolation.

- Owner team-access screen now lists members, changes staff roles and revokes/reactivates access with confirmation through update_member RPC. Owner rows have no mutation action. UI-specific role-change tests and live multi-device UAT are still pending.

- Organization foundation migration applied to connected Supabase project.
- supabase/tests/foundation.sql passed remotely inside a rollback-only transaction: atomic onboarding, identical retry, changed-payload conflict, tenant isolation, direct-write denial, role escalation denial, invitation acceptance and revoked-member denial. Fixtures rolled back.
- Flutter analyzer: no issues. Flutter tests: 9 passed (domain boundaries, configuration validation, auth validation, duplicate submission and 360dp/large-text/keyboard layouts).
- Auth, onboarding, business selection, app theme and guarded routing implemented in feature layers. Team management UI and invitation discovery still pending despite backend RPC coverage.
- No Android device/emulator available. iOS build requires macOS/Xcode. Email callback allowlist and actual recovery email roundtrip remain unverified. Full Phase 1 acceptance is therefore still in progress.
- Mobile invitation creation/revocation and recipient acceptance are now connected to the permission-checked RPCs. Owner entry is in the workspace; recipient entry is in business selection. Staff member role editing and invitation UI-specific tests remain pending.
- Invitation regression tests added: recipient acceptance invokes membership refresh, malformed email never reaches the repository, and active organization selection survives route transitions while remaining isolated by user identity. Current validation: analyzer clean, 12 Flutter tests passed. Staff role editing and full live invitation UAT remain pending.


- Platform admin foundation: separate private access grants and protected aggregate overview RPCs applied. Rollback SQL assertions passed for merchant denial, self-promotion denial, provisioning, revocation, and preservation of merchant RLS. Mobile business picker exposes an aggregate overview only to provisioned platform administrators. No real account provisioned; business operations, plans and device verification remain pending. Android debug build passed before this UI addition.

- Platform mobile overview now uses a repository boundary and user-scoped providers. Two provider tests passed for denial without fetching overview and revocation invalidating loaded data. Corrected test import lints; analyzer rerun pending.

- Mobile platform business directory connected to protected platform_businesses RPC, with 50-record pages and error retry. Displays business name/status/staff count only. Analyzer clean; platform provider tests passed including denied directory requests. Android build running for these additions. Platform account provisioning and plan management remain pending.

- Android debug build with platform business directory passed. Added platform access revalidation on app resume; cached overview/directory hide during access refresh. Three focused platform tests passed, including a lifecycle revocation widget test. Lifecycle additions still require a fresh APK/device check.

- Platform resume changes verified: analyzer clean, four focused access tests passed, and Android debug APK rebuilt successfully. No native device or iOS verification claimed. FR-028/S26 requirements reviewed: concurrency-safe entitlements and verified subscription billing remain unimplemented.

- Drafted subscription foundation migration 041 locally: private plans, subscription lifecycle/period constraints, and provider-event deduplication records. Not deployed: entitlement hooks, rollback SQL/concurrency tests, owner subscription API/UI, provider verification and pricing remain required. No subscriptions assigned or payment collection enabled.

- Local subscription draft now includes require_entitlement for trial/active/grace period validity and monthly invoice/staff/location usage. Uses the organization lock shared by issue/invitation commands, and counts issued timestamps in India calendar months. Not deployed or proven: command insertion after replay, onboarding assignment, subscription mutation locks, reminder/report gates and concurrency tests remain required.

- Draft migration 042 integrates the invoice entitlement guard after successful replay and before new invoice writes. Verified the existing invoice function body is otherwise preserved. Not applied: local Docker engine unavailable; no SQL/concurrency validation or onboarding subscription assignment exists yet.

- Subscription drafts now include an operator-configured trial policy and idempotent provision_trial helper, called atomically by the draft onboarding function. Missing trial configuration fails explicitly; migration creates no pricing or trial duration. Added owner-only subscription summary RPC excluding provider identifiers. Still undeployed and unverified in PostgreSQL; Docker Desktop startup attempted.

- Migration 041 applied successfully to connected Supabase: private subscription foundation and owner summary API. Rollback SQL checks passed for client write/provision denial, invalid staff-limit rejection and unauthorized summary denial. No plans/subscriptions/trial policy seeded. Migration 042 remains LOCAL ONLY: billing/onboarding commands are unchanged live. Lifecycle/usage/concurrency validation remains pending.

- Owner mobile Subscription entry connected to summary RPC through repository/providers. Includes loading/retry, pull refresh, explicit unconfigured state, plan/status/period/limits display. Analyzer clean; unconfigured business widget test passed. Usage counters, friendly date/status formatting, lifecycle refresh, payment actions, full state tests and native verification remain pending.

- Subscription screen now formats dates in device local time, displays readable status/limit labels, and explicitly labels an empty report allowance. Analyzer clean; two widget tests passed, including failure-to-retry on 360dp at 2x text. Live subscription states/usage, lifecycle refresh and device validation remain pending.

- Live PostgreSQL rollback lifecycle suite passed: missing trial configuration, retry without term extension, invoice/staff/location caps, unlimited invoice setting, expired denial, grace access, owner summary and cross-tenant summary denial. All fixture plans/subscriptions/policy rolled back. Does not prove concurrent requests or migration 042 command integration.

- Migration 043 deployed: owner summary includes India-calendar-month invoice usage and current active staff/location counts. Lifecycle rollback suite passed with usage count assertions and tenant denial. Mobile displays used/limit values. Migration 042 is still intentionally unapplied; enforcement/provisioning integration remains pending.

- Subscription screen revalidates its server summary on app resume and hides cached content during refresh. Three widget tests passed: configured plan/usage transitioning to unconfigured on resume, narrow 2x-text retry, and initial unconfigured state. Analyzer and APK build running for latest changes.

- Subscription APK build passed. Migration 044 applied: summary derives expired/pending display status from server time instead of showing stale active state. PostgreSQL lifecycle suite passed with past-period active record reported as expired; fixtures rolled back. Added mobile Not started label. Enforcement migration 042 still unapplied.

- Full Flutter regression suite passed: 50 tests, covering current architecture/auth/catalog/inventory/navigation/notifications/platform/purchases/sales/subscriptions/team tests. Last successful Android debug build includes subscription resume/usage UI; later Not started text label remains source-only. Full BRD/FRD acceptance is not established. Docker info process terminated with missing Linux engine pipe; local PostgreSQL concurrency environment remains unavailable.

- Support request backend migration 045 applied: owner-scoped help/feedback/export/account-closure requests, bounded input, hourly rate cap, retry receipt and audit. Rollback SQL passed identical retry, duplicate prevention, direct-write denial, tenant isolation and preservation of business on closure request. Mobile request/history UI, operational handling, export generation, retention review and closure fulfillment remain pending.

- Mobile owner Help & requests screen connected through support repository: validated forms, closure review confirmation, same-payload in-memory retry key, and paginated request history. Invalid-form widget test passed. Corrected analyzer brace lint; rerun pending. Persistent command recovery, operational handling, all request types/device tests remain pending.

- Support widget tests passed for lost-response retry retaining command UUID and invalid input blocked before repository. Added request-history refresh button and resume invalidation. Retry command remains in-memory only; reopening/restarting recovery is pending. Latest analyzer/test rerun pending; prior support analyzer was clean.

- Added pending support command model and app-local persistence adapter, scoped by actor and organization. Store test passed for new-instance restoration, actor/tenant isolation and clearing. Screen save/restore integration remains pending, so restart-safe support retry is not yet delivered. Storage follows existing SharedPreferences approach and is not encrypted.

- Support screen now saves confirmed command before RPC, restores actor/business-scoped command and fields when reopened, and clears saved data only after acknowledged success. Dropdown keyed to restored request kind. Storage and in-screen retry tests passed previously; integrated suite result pending. Corrected latest brace lint. Device restart/reopen end-to-end test still required.

- Support reopen widget flow passed: lost response persisted, screen disposed and rebuilt, details/UUID restored, successful retry used original UUID and cleared saved command. Four support tests passed. Native device process-death validation remains pending. Analyzer/APK checks running for support integration.

- Android support integration debug APK passed. Platform support queue migration 046 applied with status filter and bounded pagination, limited to explicit support submissions. Rollback tests passed merchant denial, provisioned admin queue access, no direct support table visibility for platform user, and revoked-admin denial. Platform queue mobile UI, status transitions, fulfillment and operator provisioning remain pending.

- Mobile Platform Support queue connected through platform repository and access-dependent providers. Includes open/review/resolved/cancelled filters, paging, request expansion and access refresh on resume. Merchant provider denial assertion added. Analyzer/platform tests running. Status changes, assignment, replies and export/closure fulfillment remain pending.

- Support triage migration 047 applied: platform-only begin_support_review command locks request, requires open state, records audit and retry receipt. Rollback tests passed identical retry, queue transition and stale-command rejection alongside queue access tests. Mobile review action, administrator assignment/replies and request fulfillment remain pending.

- Mobile platform Start review action connected with confirmation, busy guard, per-request in-memory retry UUID and queue invalidation after acknowledgment. Five platform tests passed including confirmation-before-command and queue refresh. Review command recovery across reopen, support replies/resolution/fulfillment, native build and real operator provisioning remain pending.

- Support replies migration 048 applied: immutable owner-readable thread rows, platform-only bounded reply command, audit and idempotent receipt. Rollback suite passed reply retry without duplicate, owner visibility, merchant reply-command denial and cross-tenant reply isolation. Mobile reply composer/history and platform thread read API remain pending; account closure/export fulfillment is not implemented.

- Owner support history now opens a paginated response screen via organization/request-scoped repository reads. Includes empty/loading/retry, refresh, resume refresh and local date formatting. Source parse issue corrected before verification. Analyzer/support suite running; dedicated thread UI test, platform reply composer and device validation pending.

- Support providers extracted from screens to eliminate circular screen imports. Analyzer clean. Added owner-thread widget test for selected business/request scoping and refreshing displayed responses. Support suite running; server RLS remains the security boundary, separate from client parameter assertions.

- Mobile platform Reply to owner composer connected to protected reply API. Includes access-dependent rendering/resume refresh, bounded required message, busy state and same-text in-memory retry UUID. Analyzer clean; platform tests running with blank-message validation assertion. Reply draft persistence, platform prior-reply history, native/device validation and support fulfillment remain pending.

- Platform support thread migration 049 applied: bounded request-specific reply history guarded by active platform access. Combined rollback support suite passed reading the created reply through the protected thread RPC. Merchant thread-denial assertion added for the next suite run. Mobile platform thread wiring remains pending; owner thread already implemented.

- Platform reply composer now reads paginated protected thread history with loading/retry and access dependencies. Analyzer clean before added lifecycle test. Initial lifecycle test exposed invalid synthetic paused-to-resumed transition in test setup; corrected to real intermediate lifecycle states. Corrected test rerun and APK build running.

- Latest Android debug APK with platform reply composer/history built successfully. Eight platform tests passed, including unchanged reply command UUID across repeated lost responses. Current device discovery found only Windows/Chrome/Edge; no Android/iPhone connected and no emulator installed. Native device QA and iOS compilation remain unverified.

- Catalog image private bucket migration 050 applied: 3MiB JPEG/PNG/WebP limit, immutable UUID object names, existing-product/tenant membership checks, owner/manager write and member read policies. Boundary SQL passed private bucket config, anonymous helper denial, malformed/path traversal denial and absent membership denial. Positive-role/storage HTTP upload tests, image attachment metadata, optimized mobile picker/upload/display and cleanup remain pending.

- Product image attachment migration 051 applied: uploaded-object presence/path validation, role/tenant enforcement, product version check, audit and retry receipt. Rollback catalog suite passed missing-upload rejection, removal retry and stale-version rejection. Positive real upload/attach, mobile image pipeline and orphan cleanup remain pending.

- Added image_picker and direct image dependency, gallery optimization adapter (1280px/JPEG/3MiB), and catalog image repository for immutable upload, versioned attachment and five-minute signed retrieval. Optimization tests running; analyzer found style lints and fixes running. Mobile product image screen and iOS photo permission text still pending; no device upload claimed.

- Catalog list now opens Product image screen for member viewing and owner/manager gallery upload/attach. Includes optimized local preview, private signed retrieval, retained command/path for in-screen attachment retries and list refresh after success. iOS photo permission description added; plist XML parsed. Analyzer running; widget/device upload, storage lost-response recovery, removal and orphan cleanup pending.

- Resumed image validation: seven catalog tests passed and analyzer clean. Upload repository now verifies exact stored bytes after upload exceptions before treating a prior upload as complete; mismatching/unavailable files preserve failure. Mock HTTP retry tests running; Android image-picker build running. Real storage upload, image removal, orphan cleanup and native/device verification remain pending.

- Image-picker Android debug build passed. Added owner/manager Remove image action with confirmation, versioned null attachment and retained in-screen retry command. Removal widget test added for confirmation-before-call and no upload. Analyzer/catalog suite running. Stored-object cleanup, persistent image-command recovery and real-device/storage upload remain pending.

- Auth callback now platform-specific: Chrome uses current HTTP origin (or explicit web override); installed apps always request registered smartbilling callback. Nine auth tests passed including URL routing and 360dp recovery layout. Analyzer clean. Latest Android build running; existing Chrome session stdin closed, so preview hot restart was not possible through that handle. Supabase allowlist and actual email roundtrip still need verification with fresh links.

- Android debug APK rebuilt successfully with product-image removal and platform-specific auth callback. Restarted verified old Flutter preview process on 8087 to load current source; replacement Chrome debug compilation running. Nine auth tests passed; live confirmation roundtrip still pending.

- Chrome preview restarted successfully on 8087 with platform-specific auth redirect source. Product image retrieval now offers inline signed-link retry and renews on app resume without changing pending selected images. Added signing-failure retry test asserting no attachment command. Analyzer/catalog suite running; device and real storage verification remain pending.

- Migration 052 removed direct client catalog-object deletion; confirmed bucket policies now expose only insert/read. Product reference removal remains audited/versioned; trusted orphan cleanup worker still pending. Image retry test caught setState callback returning a Future; moved async request creation outside setState and reran focused image UI tests. Prior analyzer clean.

- Resumed verification: all four product-image UI tests passed, including signed-link failure retry after immediate-Future-error fix, removal confirmation, attachment retry and read-only controls. Verified iOS photo-library usage key occurs once and deployment target is 13.0. Analyzer running. Native image/gallery and real storage roundtrip remain unverified.


- Five current image UI tests passed, including four-minute renewal and timer disposal. Drafted reminder-consent migration 053 locally: default-denied channels, contact snapshot/evidence, role checks, stale-version protection, audit and retry receipts. Not deployed or SQL-tested; reminder queue/cooldown/delivery and mobile consent UI remain pending. No customer messages sent.


- Reminder-consent migration 053 deployed. Rollback SQL passed opt-in/retry, revocation, stale reactivation rejection, invalid recipient denial, client write denial and tenant read/command isolation. Contact snapshot is stored so future delivery must compare against current customer contact. Mobile consent UI, dispatch-time revalidation, cooldown, staff alerts and delivery providers remain pending. No customer communications sent.

- Mobile customer Reminder consent screen connected through domain repository and Supabase adapter. Owner/manager customer entry, per-channel default-denied state, opt-out control, required evidence, versioned command and in-screen retry UUID implemented. Analyzer running; dedicated widget tests, contact-change warnings, persistent retry recovery and native validation remain pending. No reminder delivery enabled.

- Reminder consent UI now explicitly tracks successful load and disables channel/permission/evidence/save after load failure. Added widget tests for default-denied/missing evidence, identical command retry after response loss and disabled editing on failed load. Test/analyzer processes running; no reminder dispatch enabled.

## Scheduled continuation 2026-11-06

- Checked pending product-image tests first: all 11 existing catalog tests passed, including signed-link retry, confirmed removal, retained attachment commands, upload lost-response byte verification, optimization and search/scan regression coverage.
- Continued FR-010 private-image retrieval: the mobile product image viewer now renews five-minute signed links after four minutes while open. Renewal pauses on background lifecycle transitions, refreshes on resume, stops when a replacement image is selected, and cancels on disposal. Selected image previews and attachment commands remain unchanged.
- Added a regression proving renewal before expiry, no attachment writes during renewal and no further signing after disposal. Catalog suite now passes all 12 tests; flutter analyze reports no issues. Android debug APK rebuilt successfully at build/app/outputs/flutter-apk/app-debug.apk.
- Source DOCX FR-010 and signed-retrieval requirement checked directly against docs/specification-extracted.txt. Existing work preserved; this directory has no Git repository, so no commit was created.
- Still pending: real-device gallery/storage/permission validation, positive live tenant/role upload tests, persistent image-command recovery and trusted orphan cleanup. Broader unfinished requirements remain tracked above; no release or device acceptance claimed.

- Three reminder-consent widget tests passed: required evidence/default deny, retry identity and failed-load editing block. Migration 054 deployed internal dispatch-time consent eligibility helper. Rollback SQL passed current consent, revocation, outdated consent version, changed recipient and inactive customer checks. Queue/cooldown/delivery still unimplemented; no customer messages sent.

- Drafted staff overdue alert migration 055 locally: shared outstanding-balance helper, bounded 500-invoice generation, active finance-role recipients, outbox deduplication and serialized 24-hour cooldown. Not deployed or SQL-tested. Trusted scheduling/backfill and customer reminder queue/delivery remain pending; no notifications generated against real data.

- Staff overdue migration 055 deployed. Rollback invoice fixture passed outstanding-balance agreement, due-date exclusion, creation, identical retry, rolling 24-hour cooldown, cooldown release and finance-recipient scoping. Generator remains private with no authenticated execute grant. No schedule configured or real notifications generated; paid/returned/refunded edge cases, concurrency validation and customer delivery remain pending.

- Refund reconciliation fixture passed shared outstanding helper versus invoice detail and zero overdue generation for fully settled returned/refunded invoice. All data rolled back. Android consent-controls APK built successfully. Existing notification entity routing already opens sales invoice details for overdue events; added feed refresh on app resume. Notification tests running; scheduler/provider delivery and native end-to-end verification remain pending.

- Drafted customer reminder queue migration 056 locally: finance-role command, overdue/settled checks, current consent/contact validation, organization-lock serialization, customer/channel 24-hour cooldown, audit/retry and read-only queue visibility. Not deployed or tested. Dispatch provider, dispatch-time revalidation/cancellation, entitlement integration and mobile enqueue/history remain pending; no messages sent.

- Customer reminder queue migrations 056/057 deployed. Rollback SQL passed consent-required enqueue, identical retry, duplicate prevention, cooldown, revoked-consent rejection, pending-job cancellation on consent change, direct delivery-state write denial and tenant isolation. Queue remains delivery-disabled; no real jobs created or messages sent. Provider, worker revalidation, entitlement checks, concurrency stress tests and mobile queue UI pending.

- Customer ledger now opens Reminder history, with customer/business-scoped repository reads, paging, statuses, local dates, refresh/retry and resume refresh. UI distinguishes queued from sent. Added history scope/cancelled-state widget test. Analyzer/reminder tests running; enqueue controls, provider delivery and native validation pending.

- Invoice detail now exposes Queue overdue reminder to finance roles from sales navigation, with channel selection, confirmation explicitly stating delivery disabled, busy state and same-channel retry UUID. Server retains all eligibility checks. Reminder history invalidated after queue acknowledgment. Analyzer/reminder tests running; dedicated queue widget test and provider/worker/concurrency/native verification pending.

- Six reminder widget tests passed, including queue confirmation cancellation, explicit delivery-disabled disclosure, and same-command retry after response loss. Android debug build running with consent/history/enqueue UI. End-to-end delivery, provider settings, concurrency and native device validation remain unverified.

- Android reminder enqueue/history APK built successfully. Queue repository now translates server consent/cooldown/not-overdue/settled/access rejections into actionable domain failures; mobile displays specific failure without claiming success. Added consent-rejection widget assertion. Analyzer/reminder suite running; delivery still disabled.


- Full current Flutter regression suite passed: 78 tests across architecture/auth/catalog/inventory/navigation/notifications/platform/purchases/reminders/reports/sales/subscriptions/support/team. Final analyzer running. This does not prove native device behavior, real storage/email/payment roundtrips or complete BRD acceptance.

- Final full-suite analyzer clean (78 Flutter tests passed). Migration 058 deployed internal reminder preparation: locks business/job, rechecks active requester role/business/customer consent/contact and current overdue balance; invalid queued jobs cancel. Rollback tests passed valid preparation, contact-change cancellation and client execute denial. Function neither sends nor marks delivered; provider/claim/lease/idempotency worker and opt-out race handling remain pending.

- Consent reads now include current customer contact via tenant-protected relation. Mobile flags changed contact and shows permission disabled until fresh consent is recorded; does not silently write a revocation. Added changed-contact widget regression. Tests/analyzer running; live PostgREST relation roundtrip and device verification pending.

- Saved proposed trial/Starter/Business prices and quotas in config/proposed-plans.json; not activated or assigned. Migration 059 deployed explicit trial invoice cap and subscription-period counting, avoiding calendar-month resets during trials. Existing lifecycle rollback suite passed. Cross-month invoice fixture and summary display alignment remain pending; enforcement migration 042 still unapplied. All three reminder channels retained; provider delivery disabled.

- Migration 060 deployed trial-aware owner usage summary, matching the entitlement period and explicit trial cap. Cross-month rollback invoice fixture passed: previous-month invoice inside trial still consumes quota, and summary usage/limit match. Mobile trial labels updated; three existing subscription widget tests passed and analyzer was clean before final label-only edit. Real plan activation/payment and concurrency remain pending.

- Platform plan draft/catalog migration 061 deployed. Plans created through the admin command are inactive, audited and retry-safe; no business assignment or billing activation occurs. Rollback SQL passed merchant denial, admin draft creation/retry, inactive flag, catalog visibility and direct-write denial. Mobile platform plan UI and live PostgREST RPC shape verification pending; no real plans drafted.

- Mobile platform Plan catalog connected via dedicated domain/data repository to protected catalog RPC. Includes paged inactive/active price/quota display, empty/error/retry and resume refresh. Widget test passed draft labeling/no activation action and quota expansion; analyzer clean. Draft editing/creation UI, activation/assignment workflow, HTTP shape/native/operator tests and enforcement remain pending.
