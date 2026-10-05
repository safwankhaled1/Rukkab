# Server API contract

All mutation calls require an authenticated account and network access. Return errors as stable codes and translate them in clients. JSON inputs are objects passed as the named `p` parameter. IDs are UUIDs, amounts are ILS, and timestamps are ISO 8601 UTC.

| RPC | Inputs | Result / behavior |
|---|---|---|
| `search_trips` | `p`: route, stops, service (`shared`, `private`, `both`), seats, lat/lng, instant flag, optional Palestine calendar day | Matching trips with server-calculated availability, price and distance; no driver location coordinates |
| `publish_trip` | `p`: vehicle_id, route_id for shared, direction ±1, service, origin, destination, starts_at, ends_at, price, seat_limit, instant | Trip UUID; verifies documents, permit, capacity and vehicle time overlap |
| `request_booking` | `p`: trip_id, seats, origin_stop_id, destination_stop_id, origin/destination text | Pending booking UUID |
| `accept_booking` | `bid` | Atomically confirms a driver's pending booking |
| `booking_action` | `bid`, `a`, nullable `reason` | cancel, reject, pickup, arrive, board, alight, no_show, accept_time, decline_time |
| `trip_action` | `tid`, `a`, `p` | start, street (`delta` ±1), finish, cancel, reschedule (starts_at/ends_at) |
| `post_request` | `p`: mode (`instant` or `posted`), origin/destination, shared route/stops, service, seats, lat/lng, requested_at; quoted_price for instant | Request UUID; starts dispatch for instant mode |
| `offer_action` | `p`: action=create + request_id/trip_id; or action=accept + offer_id | Offer or confirmed booking UUID |
| `update_location` | `vid`, `lat`, `lng` | Validates vehicle ownership, online state and approval before updating |
| `account_action` | `a`, `p` | profile, driver_identity, register_vehicle (driver accounts only), document, online, appeal, read_notification, device_token, remove_device_token, cancel_request |
| `admin_overview` | None | Accurate counts and weekly booking series using Asia/Hebron |
| `admin_page` | `tbl`, `query`, `page` | Staff/MFA-only allowlisted, searchable pages of 20 records, with related rider/driver names |
| `admin_action` | `a`, `p` | Verify documents, approve/reject cars, assign/remove routes, save route/stop, suspend/restore/disable account, set staff role, resolve appeal, notify, save non-policy settings |
| `nearest_stops` | `r`, `lat`, `lng` | Three approved route stops ordered by geographic proximity |
| `propose_pickup` | `r`, `lat`, `lng`, `destination` stop UUID | Approved road meeting point and origin anchor; falls back to a route station when road geometry is missing |

`estimate-arrival` is a user-authenticated Edge Function accepting `booking_id`. It checks ownership, active booking/trip and fresh vehicle location, then calls Google Routes. Results include `minutes`, `distance_m` and `created_at`; missing routing returns an error rather than a fabricated time. Server cache entries are separated by booking state so pickup estimates are not reused after boarding.

Internal-only `process_dispatch`, `claim_notifications` and `finish_notification` are not granted to users. Helper functions that mutate audit/notification/violation records are also private.

Independent driver signup uses email/password with metadata `account_type=driver`, `full_name`, `date_of_birth` (YYYY-MM-DD) and E.164 `phone`. The account-creation trigger validates these fields once and creates the driver role. Later metadata edits cannot change the role. Google/Apple accounts are created as riders, and OAuth sessions cannot perform driver account mutations. `driver_details` is readable only by the driver and staff at AAL2; rider-readable profiles do not contain birth dates or phone numbers. `admin_page('profiles',...)` includes these fields for authorized staff only.

`account_action('driver_identity',p)` requires full_name/date_of_birth/phone and resets vehicle approval after identity changes. `register_vehicle` requires existing driver identity and a declared `permit_line` for buses/minibuses; that text never grants a route. Admins separately review documents and assign approved routes. Required dated documents expire at the end of the declared date in Asia/Hebron. Any expired required document pauses new operations for that driver's vehicles; sign-in and renewal upload remain available. `process_document_renewals` is internal-only and runs from the existing dispatch tick: reminders at 30/7/1 days, one expiry notification to driver and staff, deduplicated by document/date/stage. The scheduler processes at most 500 new reminders per tick; direct business guards enforce expiry independently of scheduler timing.

Core error codes: `PERMIT_ROUTE_MISMATCH`, `STOP_ROUTE_MISMATCH`, `DRIVER_NOT_APPROVED`, `TRIP_UNAVAILABLE`, `VEHICLE_TIME_CONFLICT`, `NO_SEATS`, `ACCOUNT_SUSPENDED`, `ACCOUNT_UNAVAILABLE`, `ADMIN_MFA_REQUIRED`, `OWNER_REQUIRED`, `DOCUMENTS_INCOMPLETE`, `WAIT_FIVE_MINUTES`, `REQUEST_EXPIRED`, `OFFER_UNAVAILABLE`, `PASSENGERS_REMAIN`.

Roles: rider and driver for end users; operator for daily operations; owner additionally changes staff roles and disables/suspends accounts. Owner accounts are protected from accidental disable/demotion through the API. Policies are changed through reviewed migrations rather than arbitrary dashboard JSON.

## Operational review constraints (migration 013)

`publish_trip` derives shared endpoints from the approved stop sequence and direction; clients may omit these names but may not supply different names. `trip_action(start)` requires a published trip and no other active trip for the vehicle, regardless of scheduled end time. Cancelling with street riders fails with `PASSENGERS_REMAIN`.

`request_booking` rejects the vehicle's driver (`CANNOT_BOOK_OWN_VEHICLE`). Private scheduled booking requires nonempty origin/destination plus pickup latitude/longitude (`PICKUP_REQUIRED`). `account_action(document)` requires the uploaded private object to exist (`DOCUMENT_UPLOAD_REQUIRED`), JPG/PNG vehicle photos (`DOCUMENT_FORMAT`), and expiry dates for other required documents (`DOCUMENT_EXPIRY_REQUIRED`).
