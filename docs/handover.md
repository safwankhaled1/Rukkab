# Developer handover

## Current state: 2026-10-05

This section supersedes older status statements below, which record development history. See current-status.md and design-system.md. Migrations 001–021 are deployed. Native rollback-only checks passed for Arabic driver onboarding, private final-submission notices, rejected application correction, MFA-protected filters, and the ride lifecycle from search through alighting/completion. All fixture records rolled back. The real driver/vehicle remain unapproved.

Validation: 34 Node/database tests, 47 Flutter tests in the latest full run, clean Dart analysis, admin production build, Edge Function type checks, responsive Arabic/English admin and filter/browser checks, and mocked MFA checks passed. The strengthened driver-review widget test also verifies preserving an unsaved Arabic name on refresh. Android debug APK was rebuilt, installed with install -r on emulator-5556 and launched with Status: ok. This is not visual native end-to-end verification or a signed release.

The backend is connected; email provider/domain/worker scheduling, Maps/Routes, Google/Apple OAuth and Firebase/APNs remain unconfigured or unverified. No actual transactional receipt delivery or full rider/driver/admin physical-device journey has been verified. Independent PostgreSQL connection contention and iOS signing remain open. The moved project is Desktop/Projects/Rukkab; the old Desktop/Rukkab path contains build leftovers.


Migration 021 synchronizes cancelled/no-show matched requests, repairs only stranded terminal requests, and raises a staff review alert after three impactful driver cancellation events in 30 days. Empty-trip, rider and staff cancellations do not count. A whole-trip cancellation counts once, not once per rider. The threshold only requests review and never suspends the driver or penalizes affected riders. A private audit marker deduplicates alerts; an advisory transaction lock serializes review calculations. Independent-connection contention still needs verification.

Native cancellation smoke checks passed on Supabase with synthetic accounts and rollback. The admin demo notice is bilingual and links to the correct driver account; all demo mutations remain local. Client notification copy covers rejection, reschedule consent, pickup and completion; the push worker has not been deployed/configured for actual delivery. The latest debug APK installed with Success, launched with Status: ok and process 32338 remained present; targeted AndroidRuntime/flutter logs were empty. The native screenshot remains an anonymous Arabic sign-in screen, not an authenticated ride.

## Checks and release order

1. `npm ci` using the committed lockfile.
2. `npm run check` for the admin build, Edge Function type check and SQL/security tests.
3. Start `npm run dev` and run `npm run test:browser` (Edge by default; set BROWSER_CHANNEL for another installed Chromium browser).
4. Run `scripts/check-mobile.ps1` or equivalent `flutter analyze` and `flutter test` from apps/mobile.
5. Apply migrations to staging, run native PostGIS/pg_cron and independent-connection concurrency checks, then test Android/iOS on physical devices.
6. Promote backward-compatible migrations before clients, then deploy the admin and notification/estimate functions, and release signed mobile builds.

## What is verified locally

- PostgreSQL core rules and RLS, including private document policies against a simulated Storage schema.
- MFA/owner checks, safe admin search, seat accounting, permit directions, expired documents, overlap rejection, suspension and appeal restoration.
- Dispatch lease retry and expiration, posted offers, whole-car taxi allocation, individual no-show wait and notification outbox retry.
- Admin Arabic/English direction, demo mutations/search, responsive navigation and browser-error checks.
- Flutter analyzer, widget/unit tests and a JavaScript web compilation of the complete configured client.
- TypeScript checks for both Edge Functions using a minimal declaration of the Deno runtime API.

## Connected Supabase verification (2026-10-04)

The owner authorized project `hkqookgltexlaoburoya`. The initial 12 migrations were applied atomically to its initially empty public schema; migration history is recorded for future CLI upgrades. Verified: 19 application tables with RLS enabled, a private driver-documents bucket, active rukkab-dispatch cron job, and PostGIS 3.3.7. `supabase/check_deployment.sql` passed against native PostgreSQL/PostGIS and rolled back its fixtures: generated road geometry, projected pickup, out-of-corridor rejection, both route directions, and accepted seat allocation.

The public HTTP API returned 401 for anonymous admin RPC and route-table access. Auth settings confirmed email sign-in and mandatory email confirmation. Client configuration uses a publishable key only; local config files are ignored by Git. This does not verify authenticated live subscriptions, SMTP delivery, or push delivery.

Android debug APK built and installed on emulator-5554 (Pixel 10, x86_64). The Arabic sign-in screen was visually verified and Supabase initialization completed. Build tools used Android SDK 36, NDK 28.2.13676358 and the JDK bundled with Android Studio; plugin dependencies also installed SDK 34/35 and CMake 3.22.1. Password minimum length 12 was saved and visually verified in the hosted Auth settings. Following specific user approval, the three Auth callbacks were saved: io.rukkab.app://login-callback, http://127.0.0.1:5173, and http://localhost:5173. One existing email-confirmed account was promoted to the initial owner using the guarded bootstrap transaction and audit entry. Live administrative access still requires that user to sign in and complete MFA enrollment.

## What needs connected staging or native devices

- Real Auth email confirmation/recovery and MFA enrollment against Supabase.
- Real Storage uploads/signed URLs, Realtime delivery, cron ticks and Firebase/APNs delivery.
- Fleet-size spatial performance, proximity notification triggers and repeated road pickup grouping. Generated geometry and a projected pickup have passed a native smoke check.
- Google Maps coverage and Google Routes estimates for actual Palestinian roads.
- Concurrent connections to native PostgreSQL. PGlite uses one serialized connection and cannot prove real lock contention behavior.
- Signed Android release, physical-device background location and battery behavior; iOS build/signing/permissions on Mac. An Android debug build has been verified on the local emulator.

## Conventions

## Account flow and ownership update (in progress)

The mobile authentication flow now has a nested navigator with a dedicated account-type page, separate rider/driver registration routes and a password reset page. Email/password login precedes passenger social login; Apple is displayed only on iOS. Session retention is an explicit checkbox backed by secure storage, including removal of saved sessions and prevention of persistence on token refresh when unchecked. Drivers can switch to passenger booking mode without changing their account role; passenger and operational bookings are separated by rider ownership.

Migration 016 adds independent vehicle-owner and permit-holder names and staff notifications for driver registration/vehicle submission. It was deployed atomically after browser connectivity recovered; the live SQL result confirmed 16 installed migrations. The owner's actual admin session was visibly authenticated and displayed live statistics with zero drivers. Admin notification records have translated registration text and a link to review the corresponding account or vehicle. A real signup/notification test remains pending; database trigger tests alone do not prove UI delivery.

`supabase/check_driver_registration.sql` subsequently passed on native PostgreSQL: email signup metadata created a driver/profile with private details; signup and vehicle submission each created a staff notification; independent owner names appeared in the protected admin vehicle query; the new vehicle remained unavailable before approval; authenticated clients could not call the unguarded legacy RPC or write ownership rows directly. All fixture records and alerts were rolled back. This still does not verify an actual Auth email, mobile signup submission, Realtime presentation, or push delivery.

The owner then completed real driver signup on emulator-5556. The actual admin notification list showed one `driver.registered` notice with the submitted driver name; the corresponding profile displayed driver role, name, phone and birth date. The notification's review button opened this profile, and its read timestamp was present. Native signup UI still showed the email-confirmation message, so email confirmation and an authenticated driver mobile session are not yet verified. No vehicle or documents were approved during this check. A dedicated email-confirmation page was added to the source afterwards to replace the submitted form; that source change is not yet installed on the active emulator and must not interrupt the user's current confirmation/login flow.

The updated APK was installed on emulator-5556 (Medium Phone API 37). The registration page was observed there; account creation/confirmation and notification delivery remain pending. The driver test email was supplied by the owner; the user enters authentication credentials and confirms email directly. Neither Google/Apple provider configuration nor Firebase push credentials are available yet. Migration 016 is the latest verified live schema.

Latest validation: 20 database/Node tests, 17 Flutter tests, a clean Flutter analyzer, Android debug build, admin build/Edge Function type checks, responsive Arabic/English admin browser checks, and the isolated MFA browser fixtures passed. Ownership data is stored in the private `vehicle_ownership` table and joined only in the MFA-protected admin page RPC; an authenticated passenger test verifies that it cannot read these names. The admin bell counts only the current administrator's unread notifications after MFA. These are local/mocked checks, not proof of live SMTP, native iOS, Google/Apple OAuth or Firebase push. The latest SQL review bundle was regenerated on port 5176 before deploying 016; older review servers cache earlier drafts and must not be reused.

Driver account and renewal update (2026-10-04): migrations 014 and 015 were applied to the connected project. There were no existing driver accounts or approved vehicles at preflight. Rider self-promotion is blocked on the server; driver registration is a separate signed-out email flow requiring full name, birth date and international phone. License/insurance/registration/permit expiry remains mandatory, and declared permit text does not replace admin route assignment. Private driver details appear in staff-only account records. The existing server tick now sends deduplicated 30/7/1-day renewal reminders and expiry alerts; expired required documents immediately pause new driver operations, independent of cron. Renewal needs admin approval. Login and document upload stay available. Native PostgreSQL/PostGIS smoke checks passed with fixtures rolled back. Google/Apple buttons are implemented for riders; both providers remain disabled pending external account configuration. The updated notification worker source requires deployment when Firebase is configured.

Admin MFA recovery (2026-10-04): authentication now persists in tab-scoped sessionStorage, so refreshing during setup does not discard the session. Auth broadcasts from another tab cannot grant a session to this tab. Missing sessions clear stale MFA state and offer a return to sign-in. Enrollment also offers a manual authenticator setup key for same-phone use, and verification accepts Arabic digits. Verified factors remain intact. Server role and AAL2 checks remain mandatory. `npm run test:mfa` covers these paths with entirely synthetic Auth fixtures; actual owner MFA enrollment still requires the user.

Keep descriptive English names and feature-oriented directories. Comments explain why a rule exists; domain behavior belongs in reviewed server RPCs. Add regression tests for changed invariants. Do not edit an already-deployed migration: append a new one. Use configuration files for public client settings and server secrets for private credentials. Never commit data exports, uploaded documents, service keys or signing material.

Road geometry is an operations input, not a default invented map. Review it with local drivers, keep coordinates in longitude/latitude order, and align it with the approved stop sequence. A routing provider's suggested route must never grant a permit.

## Remaining scale work before a broad public launch

- Add cursor pagination for terminal history and requests. Route/stop catalogs and active bookings now load every page; booking history retains the most recent 100 rows. Home Realtime refreshes now fetch only dependent resources, coalesce repeated events, and retain events arriving during an in-flight fetch. GPS is handled by tracking without reloading home lists.
- Benchmark spatial dispatch against fleet size; add indexed candidate narrowing if measured latency warrants it.
- Instrument server timing, scheduler health, stale GPS and exhausted push retries. Add centralized crash/error reporting after selecting an account/provider.
- Agree on document/GPS retention and deletion processes, verify backup restoration, and run a security review on deployed configuration.

## Operational and design review (2026-10-04)

Migration 013 was applied to the connected project after regression checks. Shared journey endpoints now come from the approved stops; misleading supplied names are rejected. A partial unique index and vehicle lock keep one physically active trip per vehicle even when scheduled times no longer overlap. Cancellation is blocked while street riders remain. Private scheduled booking requires a real pickup and addresses; drivers cannot book their own vehicles. Document registration requires an existing private Storage object, an image for vehicle photos, and expiry dates for required documents.

Mobile search clears old results when criteria change and discards delayed results from older searches. Shared fares show the total for selected seats. Pickup has no invented coordinate fallback. Known failures are localized without displaying database internals. A central app theme improves contrast, field spacing, touch targets and card consistency; sign-in includes a branded header and password visibility control. Admin focus styling and reduced-motion support were refined.

The project still needs production SMTP, Google/Firebase project configuration, real approved route geometry, and signed releases before a public launch. The initial owner and development Auth callbacks are now configured; actual owner MFA enrollment and a live admin session remain to be completed by the user. These account inputs cannot be invented. Independent native database concurrency, real-device background location and iOS signing remain unverified.

Schedules and booking displays now use Asia/Hebron through the embedded IANA database from [timezone](https://pub.dev/packages/timezone). Date fields display civil time with an explicit Palestine label and serialize UTC for the server. Summer/winter round-trip regression tests cover this conversion. Keep the dependency current when Palestinian daylight-saving rules change.

Final review checks: 17 Node/database tests, 11 Flutter tests, clean Dart analysis, admin production build and Edge Function type checks, and Edge browser verification. The updated Android debug build was installed and launched successfully on the existing emulator; the client restored the existing signed-in rider session. Owner activation was completed subsequently after specific approval. Native PostGIS smoke fixtures were rolled back after PASS on migration 013. These are development checks, not a signed production release or proof of independent database connection contention.

Validation for this update: 19 Node/database tests and 15 Flutter tests passed; clean Flutter analysis, admin build, Edge Function type checks, admin browser regressions and native PostgreSQL/PostGIS renewal smoke checks passed. The final Android debug build was installed on emulator-5554, and the signed-in rider account was visually verified without any vehicle-registration or role-conversion button. Persisted renewal holds cover multi-vehicle drivers and cannot be cleared by uploading or merely verifying a replacement: vehicle reapproval is required.

## Resume on 2026-10-05

The project was moved to Desktop/Projects/Rukkab. Regenerate Flutter package configuration using the moved local SDK and PUB_CACHE before analysis/build. Migration 017 was successfully deployed in the preceding session (SQL result: 17 installed migrations). Draft creation no longer generates new review alerts; one completed submission creates one staff alert and one email job. Existing driver and vehicle records remain intact. The mail provider is explicitly not configured; the owner asked to prepare integration and explain activation requirements. See application-email-setup.md.

Mobile now has explicit passenger/driver login modes, separate personal-details and credentials registration pages, Arabic/Persian number normalization, embedded Cairo typography, and a resumable driver onboarding screen. Both initial and additional vehicle registration use the onboarding flow. Vehicle creation consumes the RPC-returned ID instead of querying by plate. The email worker and leased job handling are implemented; delivery and scheduled operation remain unverified until credentials are configured. Native manual UI checks remain needed in this resumed session because computer/browser control tools are currently unavailable.

Validation in the resumed session: 21 database/Node tests passed, including mail-job access, exclusive leasing, stale-token rejection and retry completion; 20 Flutter tests passed; final Flutter analysis was clean. Admin production build, all Edge Function type checks, responsive Arabic/English browser tests and mocked MFA regression tests passed. Android debug APK was rebuilt successfully from the moved project. Native manual onboarding and actual receipt-mail delivery are not verified by these tests. The newly added check_driver_applications.sql is a rollback-only native smoke check prepared for the next connected SQL-editor session; it was not executed in this session.

The rebuilt APK was installed with adb install -r on emulator-5556 successfully, preserving app data. The package process was observed running after launch. The emulator reported a launch wait timeout under load; the process observation is not a visual confirmation of the onboarding page. No AndroidRuntime fatal exception was present in the filtered log at the check. Native manual UI review still requires available computer-use tools or the user's feedback.

## Offer and booking experience review (2026-10-05)

Migration 020 is deployed and tested on native PostgreSQL: oversized private groups and self-booking are rejected both at creation and acceptance, including legacy offers. Valid private acceptance reserves the whole car once at the published fare. A native shared offer for three seats at 12.5 booked at 37.5 and left one seat. All fixtures rolled back. No real vehicle/documents were approved.

Mobile offers now resolve their referenced trip IDs directly in bounded batches, show the total for the passenger group and prevent booking when the fare cannot be resolved. The driver booking UI hides arrival/boarding controls before trip start and uses a small dedicated no-show countdown. Server checks remain authoritative. Confirmation for a changed departure time explains the no-penalty refusal path. Tests cover quote calculations, unknown-price offers, RPC payloads, pre-start controls, the wait gate, busy state and a 205-ID mocked HTTP query. Native server proof does not verify UI Realtime synchronization or external message delivery.

The rebuilt debug APK was installed with preserved app data on emulator-5556, launched with Status: ok and had a running process. No fatal AndroidRuntime output was found at the check. External provider configuration and real-device/end-to-end tests listed in current-status.md remain incomplete.


## Offer experience continuation (2026-10-05)

Driver offer choices now load all unexpired published trips belonging to their vehicles, in bounded pages, ordered by earliest departure. This removes the public newest-100-trip limitation. The mock HTTP regression retrieves 105 owned trips; it does not verify a real authenticated session. Offer cards distinguish selected, unselected and unavailable offers; private requests cannot be offered back to their own driver in the UI. Arabic/English route arrows and concise Palestine-time dates are applied. Empty lists retain pull-to-refresh.

Home controls live in shared/home_app_bar.dart: notifications remain visible; account mode, language and refresh are in the accessible overflow menu. Only driver accounts receive the passenger/driver mode switch. Widget checks passed at 280px/150% text scaling for the driver toolbar and 320px/150% for Arabic offers. All 36 Flutter tests and analysis passed before rebuilding/installing the debug APK. No additional database migration was required; latest deployed migration remains 020.


## Driver seat and schedule review (2026-10-05)

TripSeats and TripSeatSummary show reserved, occupied, available and retained scheduled allocations. These are display calculations over the last loaded snapshot; server transactions still authorize all writes. vehicleTrips embeds only bookings(seats,state), pages all live trips, and retains at most 100 terminal trips. RLS permits the driver to read all bookings on their own trip, while a passenger reads only their own rows; a new PGlite regression checks both scopes and server availability. HTTP mocks check query composition and the 101st live trip; they do not verify a live authenticated PostgREST call.

Driver load revisions prevent a late response from replacing a different selected vehicle. Private taxis have no street controls. Trip cancellation prompts before calling the server, and actions unavailable in the loaded state are disabled. Rescheduling preserves both existing dates and times, avoids an unchanged client submission, and shows old/new departure to the passenger. A 320px/150% Arabic widget check covers reschedule decline. Turning off availability stops the local GPS stream before contacting the server; a service double proves call ordering when the network request fails, not physical-device background behavior.

All 45 Flutter tests, clean analysis, all 28 Node/database checks, admin production build and Edge type checks passed. The debug APK was rebuilt/installed, and emulator PID 21947 plus a resumed activity were verified. Actual Android screenshots show Arabic/English sign-in and both account choices; Google disappears for the driver choice. The emulator was signed out throughout this visual review and restored to Arabic/passenger selection. No password was entered, account created, or real document approved. Latest deployed migration remains 020. Full rider/driver/admin journey, device location permissions, external services and independent-connection contention remain unverified.
