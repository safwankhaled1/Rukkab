# Rukkab architecture

## Repository map

| Directory | Responsibility |
|---|---|
| `apps/mobile/lib/core` | Supabase repository, encrypted mobile session storage, connectivity, localization, GPS and notifications |
| `apps/mobile/lib/features` | Rider search, driver operations, bookings, requests/offers, tracking and account screens |
| `apps/mobile/lib/shared` | Reusable, validated form components |
| `apps/admin/src` | React/TypeScript operations website, admin authentication and MFA, record management |
| `supabase/migrations` | Versioned schema, server rules, RLS, private storage, scheduler and geographic indexes |
| `supabase/functions/send-notifications` | Internal notification outbox worker; Firebase credentials remain server-side |
| `tests` | Executable PostgreSQL rule/security tests and browser regression |
| `docs` | Setup, APIs, security decisions and handover notes |
| `work` | Ignored SDK, package caches, screenshots and development artifacts |

## Trust and data flow

Clients authenticate with Supabase Auth and receive a user-scoped token. Read requests are checked by PostgreSQL row-level security. Mutations go through explicit, allowlisted security-definer RPCs with empty `search_path`, identity checks and row locks. No application client has direct table write privileges. Never ship the service-role key to a browser or mobile binary.

The owner account is bootstrapped manually by a database administrator. User signup metadata cannot choose a privileged role. Staff reads and mutations require `aal2` (verified MFA) in addition to an active staff role stored in PostgreSQL. The website keeps its admin session in sessionStorage, scoped to its browser tab, so reloads during MFA preserve the login. Closing the tab ends normal tab storage; logout removes the stored session. Browser session restoration may restore sessionStorage, so this is not a server-side timeout policy. Staff authorization remains enforced on the server with an active staff role and aal2.

Booking acceptance locks the vehicle, trip and booking. Availability is recomputed inside the transaction; pending requests do not hold seats. Confirmed bookings hold seats, boarded bookings consume those same seats. For scheduled trips, completed bookings continue to consume allocation until the entire trip finishes, preventing seat resale between intermediate stations. Private taxi requests reserve the full vehicle.

Instant requests use 30-second driver leases, with a total 2-minute search lifetime. A server cron ticks every 10 seconds, expires old leases and assigns the next suitable fresh-location vehicle at the previously displayed fare. Posted requests receive driver offers that reference published trips; selecting an offer reserves seats atomically.

The relational route and ordered stops are the permit authority. Both directions are supported. Maps are presentation only and cannot expand a vehicle's approved route. Taxi private service is unrestricted by route; shared taxi service has an approved operating route. No permit legality is inferred from text recognition or map directions.

Driver GPS uploads run only while the driver enables availability. Freshness is checked before instant assignment. Location reads require a confirmed/boarded booking and either an active trip or an instant trip with the driver online; dropping off, cancelling, or awaiting a rescheduled time revokes access. The UI shows update times and warns on stale coordinates. A foreground/background location configuration is included, but physical-device and OS-permission testing is required before release.

## Maintainability and scaling

Passenger and driver accounts have independent onboarding. Only fresh email/password signup can request the driver role, with full name, birth date and phone validated by the Auth insert trigger. Registering a vehicle never promotes an existing rider. Sensitive driver identity fields live in a private RLS table rather than rider-readable profiles. Document renewal does not clear administrative suspension or restore approval automatically; the owner reviews the replacement. Operational expiry is derived in `vehicle_ready`, while the scheduler produces deduplicated reminders and switches vehicles offline.

- Use descriptive English filenames grouped by behavior. Dart is formatted using `dart format`; React is strict TypeScript. Comments explain invariants and tradeoffs.
- Keep monetary amounts as PostgreSQL `numeric`; never authorize a fare from a client field. The server takes prices from the published trip.
- PostgreSQL indexes cover trips, bookings, requests, violation windows and recent events. Hosted PostGIS adds geography/GiST indexes and nearest-stop search.
- Pages in the admin site are fetched in batches of 20. Mobile lists currently have a 100-row bound: this is an intentional v0.1 limit, and cursor pagination should precede large-scale launch.
- Realtime invalidations are debounced. Driver GPS changes do not refetch the mobile home dataset; the tracking screen polls its authorized location separately. Notifications use a durable outbox, leases, bounded retries and private service credentials.
- Split development, staging and production projects. Apply forward migrations, pin package lockfiles, and run all checks before promotion. A schema/API change must remain compatible with installed mobile versions.
- Current dispatch uses SQL spatial filtering and ranking. Benchmark it against expected active fleet size; use indexed nearest-neighbor candidate narrowing or a dedicated dispatch worker if measured latency requires it.

## Operational boundaries

No live cloud project, email provider, map key, Firebase project or signing credentials are created automatically. Local admin demo data is clearly labeled and never touches a production database. Production accounts and documents must not be copied into the demo.

Pickup selection supports approved stations and road points on an administrator-supplied GeoJSON LineString. The line must follow increasing stop sequence. A server proposal projects a point onto the road and snaps it to stable 200-metre meeting points, grouping nearby riders. If geometry is missing, it proposes an approved station. Requests must be within 60 metres of the approved corridor and in the correct direction before the selected destination. Never substitute straight lines between stations for a reviewed road path.

Vehicle updates notify booked riders once when the car is within 300 metres of their pickup point. The authenticated `estimate-arrival` Edge Function calls Google Routes and returns an explicitly estimated duration; it never expands permit authorization. Missing credentials, stale location or unavailable routing produce no invented estimate. Physical route suitability and map accuracy must be tested on pilot lines before enabling estimates for passengers.


## Cancellation consistency and driver review

Migration 021 keeps a confirmed matched request consistent with cancelled/no-show bookings; pending dispatch rejection remains retryable. Review alerts derive cancellation actors from the private audit writer, not user-supplied cancellation reasons. Three impactful driver events in 30 days produce a deduplicated staff notice and audit marker, without automatic permission changes. Admin formatting and prepared push copy share driver-messages.ts; prepared ride push copy lives in ride-messages.ts. Native rollback checks and local rule tests do not prove independent-connection concurrency or external delivery.
