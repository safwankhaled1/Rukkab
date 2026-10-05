import { PGlite } from "@electric-sql/pglite";
import { readFile } from "node:fs/promises";
import { test, before, after } from "node:test";
import assert from "node:assert/strict";

const db = new PGlite();
const ids = {
  owner: "10000000-0000-0000-0000-000000000001",
  driver: "10000000-0000-0000-0000-000000000002",
  driver2: "10000000-0000-0000-0000-000000000005",
  rider: "10000000-0000-0000-0000-000000000003",
  other: "10000000-0000-0000-0000-000000000004",
  vehicle: "20000000-0000-0000-0000-000000000001",
  route: "30000000-0000-0000-0000-000000000001",
  a: "40000000-0000-0000-0000-000000000001",
  b: "40000000-0000-0000-0000-000000000002",
};
const q = (sql, params = []) => db.query(sql, params);
async function expectRejected(action, expected) {
  await db.exec("savepoint expected_failure");
  try {
    await assert.rejects(action, expected);
  } finally {
    await db.exec(
      "rollback to savepoint expected_failure; release savepoint expected_failure",
    );
  }
}
async function identity(user, aal = "aal1") {
  await q(
    "select set_config('test.uid',$1,false),set_config('test.aal',$2,false)",
    [ids[user], aal],
  );
}
async function rpc(name, args) {
  const placeholders = args.map((_, i) => `$${i + 1}`).join(",");
  return (await q(`select public.${name}(${placeholders}) as value`, args))
    .rows[0].value;
}
async function trip(extra = {}, driver = "driver") {
  await identity(driver);
  return rpc("publish_trip", [
    JSON.stringify({
      vehicle_id: ids.vehicle,
      route_id: ids.route,
      service: "shared",
      origin: extra.direction === -1 ? "الخليل" : "السموع",
      destination: extra.direction === -1 ? "السموع" : "الخليل",
      starts_at: new Date(Date.now() + 86400000).toISOString(),
      ends_at: new Date(Date.now() + 90000000).toISOString(),
      price: 15,
      seat_limit: 1,
      ...extra,
    }),
  ]);
}
async function request(t, user = "rider") {
  await identity(user);
  return rpc("request_booking", [
    JSON.stringify({
      trip_id: t,
      origin: "السموع",
      destination: "الخليل",
      pickup_latitude: 31.4,
      pickup_longitude: 35.07,
      seats: 1,
      origin_stop_id: ids.a,
      destination_stop_id: ids.b,
    }),
  ]);
}

before(async () => {
  await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
 create schema auth; create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz default now(),raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{"provider":"email"}');
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
 create function auth.jwt() returns jsonb language sql stable as $$select jsonb_build_object('aal',current_setting('test.aal',true),'amr',coalesce(nullif(current_setting('test.amr',true),'')::jsonb,'[]'::jsonb))$$;
 grant usage on schema auth to authenticated,anon; grant execute on all functions in schema auth to authenticated,anon;
 create schema storage;
 create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
 create table storage.objects(id uuid primary key default gen_random_uuid(),name text not null,bucket_id text not null references storage.buckets(id));
 alter table storage.objects enable row level security;
 create function storage.foldername(text) returns text[] language sql as $$select (string_to_array($1,'/'))[1:array_length(string_to_array($1,'/'),1)-1]$$;
 grant usage on schema storage to authenticated;grant select,insert on storage.objects to authenticated;grant execute on function storage.foldername(text) to authenticated;
 create publication supabase_realtime;`);
  for (const name of [
    "core",
    "operations",
    "security_admin",
    "storage",
    "overview",
    "worker",
    "hardening",
    "admin_page",
    "home_realtime",
    "operational_review",
    "driver_accounts",
    "renewal_holds",
    "ownership",
    "applications",
    "admin_filters",
    "driver_draft_capacity",
    "offer_capacity_guards",
    "cancellation_consistency",
  ]) {
    const files = {
      core: "202610040001_core",
      operations: "202610040002_operations",
      security_admin: "202610040003_security_admin",
      overview: "202610040006_admin_overview",
      storage: "202610040004_storage_realtime",
      worker: "202610040008_notification_worker",
      hardening: "202610040009_hardening",
      admin_page: "202610040011_admin_page",
      home_realtime: "202610040012_home_realtime",
      operational_review: "202610040013_operational_review",
      driver_accounts: "202610040014_driver_accounts_and_renewals",
      renewal_holds: "202610040015_document_renewal_holds",
      ownership: "202610040016_driver_ownership_and_registration_alerts",
      applications: "202610040017_completed_driver_applications",
      admin_filters: "202610050018_admin_filters",
      driver_draft_capacity: "202610050019_driver_draft_capacity",
      offer_capacity_guards: "202610050020_offer_capacity_guards",
      cancellation_consistency: "202610050021_cancellation_consistency",
    };
    await db.exec(
      await readFile(`supabase/migrations/${files[name]}.sql`, "utf8"),
    );
  }
  await q(
    `insert into auth.users(id,email,raw_user_meta_data) values($1,'owner@example.test','{"full_name":"Owner"}'),($2,'driver@example.test','{"full_name":"Driver"}'),($3,'rider@example.test','{"full_name":"Rider"}'),($4,'other@example.test','{"full_name":"Other"}')`,
    [ids.owner, ids.driver, ids.rider, ids.other],
  );
  await q("update profiles set role='owner' where id=$1", [ids.owner]);
  await q(
    "update profiles set role='driver',full_name='Test Driver' where id=$1",
    [ids.driver],
  );
  await q(
    "insert into driver_details(user_id,date_of_birth,phone) values($1,'1990-01-01','+970599000001')",
    [ids.driver],
  );
  await q(
    "insert into routes(id,name_ar,name_en,governorate) values($1,'السموع – الخليل','As Samu – Hebron','Hebron')",
    [ids.route],
  );
  await q(
    "insert into stops(id,route_id,name_ar,name_en,sequence,latitude,longitude) values($1,$3,'السموع','As Samu',0,31.4,35.07),($2,$3,'الخليل','Hebron',1,31.53,35.09)",
    [ids.a, ids.b, ids.route],
  );
  await q(
    "insert into vehicles(id,driver_id,plate,kind,capacity,approved) values($1,$2,'TEST-1','minibus',7,true)",
    [ids.vehicle, ids.driver],
  );
  await q("insert into vehicle_routes values($1,$2)", [ids.vehicle, ids.route]);
  for (const kind of [
    "license",
    "permit",
    "insurance",
    "registration",
    "vehicle_photo",
  ])
    await q(
      "insert into documents(vehicle_id,kind,storage_path,expires_on,verified) values($1,$2,$3,current_date+365,true)",
      [ids.vehicle, kind, `${ids.driver}/${ids.vehicle}/${kind}.pdf`],
    );
});

test("vehicle ownership accepts distinct people, remains private, and saves without draft alerts", async () => {
  await db.exec("begin");
  try {
    await identity("driver");
    const payload = {
      plate: "OWNERS-TEST",
      kind: "minibus",
      capacity: 7,
      permit_line: "السموع – الخليل",
      vehicle_owner_name: "Vehicle Owner",
      permit_holder_name: "Permit Holder",
    };
    await expectRejected(
      () =>
        rpc("account_action", [
          "register_vehicle",
          JSON.stringify({ ...payload, vehicle_owner_name: "" }),
        ]),
      /VEHICLE_OWNER_REQUIRED/,
    );
    await expectRejected(
      () =>
        rpc("account_action", [
          "register_vehicle",
          JSON.stringify({ ...payload, permit_holder_name: "" }),
        ]),
      /PERMIT_HOLDER_REQUIRED/,
    );
    const result = await rpc("account_action", [
      "register_vehicle",
      JSON.stringify(payload),
    ]);
    const vehicle = (
      await q(
        "select v.*,o.vehicle_owner_name,o.permit_holder_name from vehicles v join vehicle_ownership o on o.vehicle_id=v.id where v.id=$1",
        [result.id],
      )
    ).rows[0];
    assert.equal(vehicle.vehicle_owner_name, "Vehicle Owner");
    assert.equal(vehicle.permit_holder_name, "Permit Holder");
    assert.equal(vehicle.driver_id, ids.driver);
    assert.equal(vehicle.approved, false);
    const notices = (
      await q(
        "select * from notifications where user_id=$1 and kind='driver.vehicle_submitted'",
        [ids.owner],
      )
    ).rows;
    assert.equal(notices.length, 0);
    await db.exec("set role authenticated");
    await expectRejected(
      () =>
        rpc("notify_driver_review", [ids.driver, "driver.registered", null]),
      /permission denied/,
    );
    await expectRejected(
      () =>
        rpc("account_action_before_ownership", [
          "register_vehicle",
          JSON.stringify(payload),
        ]),
      /permission denied/,
    );
    await identity("rider");
    assert.equal(
      (
        await q("select * from vehicle_ownership where vehicle_id=$1", [
          result.id,
        ])
      ).rows.length,
      0,
    );
    await db.exec("reset role");
    await identity("owner", "aal2");
    const page = await rpc("admin_page", ["vehicles", "Permit Holder", 0]);
    assert.equal(page.count, 1);
    assert.equal(page.rows[0].vehicle_owner_name, "Vehicle Owner");
  } finally {
    await db.exec("rollback");
  }
});

test("Arabic driver drafts submit only when complete and notify staff and queue email once", async () => {
  await db.exec("begin");
  try {
    const user = "10000000-0000-0000-0000-000000000099";
    await q(
      "insert into auth.users(id,email,raw_user_meta_data) values($1,'arabic-driver@example.test',$2)",
      [
        user,
        JSON.stringify({
          account_type: "driver",
          full_name: "صفوان خالد الرواشدة",
          phone: "٠٥٩٢٢٠٨١٣٣",
          date_of_birth: "١٩٩٠-٠١-٠١",
        }),
      ],
    );
    assert.equal(
      (await q("select phone from driver_details where user_id=$1", [user]))
        .rows[0].phone,
      "+970592208133",
    );
    assert.equal(
      (
        await q(
          "select count(*)::int as count from notifications where kind='driver.registered' and body::jsonb->>'driver_id'=$1",
          [user],
        )
      ).rows[0].count,
      0,
    );
    await q(
      "select set_config('test.uid',$1,false),set_config('test.aal','aal1',false)",
      [user],
    );
    const vehicle = (
      await rpc("account_action", [
        "register_vehicle",
        JSON.stringify({
          plate: "تجربة-١٩",
          kind: "medium_bus",
          capacity: "١٩",
          permit_line: "السموع – الخليل",
          vehicle_owner_name: "مالك السيارة",
          permit_holder_name: "صاحب البيرميت",
        }),
      ])
    ).id;
    assert.equal(
      (await q("select capacity from vehicles where id=$1", [vehicle])).rows[0]
        .capacity,
      19,
    );
    await expectRejected(
      () => rpc("submit_driver_application", [vehicle]),
      /DOCUMENTS_INCOMPLETE/,
    );
    await identity("owner", "aal2");
    await expectRejected(
      () =>
        rpc("admin_action", [
          "approve_vehicle",
          JSON.stringify({ id: vehicle, capacity: 19 }),
        ]),
      /APPLICATION_NOT_SUBMITTED/,
    );
    await q(
      "select set_config('test.uid',$1,false),set_config('test.aal','aal1',false)",
      [user],
    );
    for (const kind of [
      "license",
      "insurance",
      "registration",
      "vehicle_photo",
      "permit",
    ]) {
      const path = `${user}/${vehicle}/${kind}.${kind === "vehicle_photo" ? "jpg" : "pdf"}`;
      await q(
        "insert into storage.objects(name,bucket_id) values($1,'driver-documents')",
        [path],
      );
      await rpc("account_action", [
        "document",
        JSON.stringify({
          vehicle_id: vehicle,
          kind,
          storage_path: path,
          expires_on: "2099-01-01",
        }),
      ]);
    }
    assert.equal(
      (
        await q(
          "select count(*)::int as count from notifications where kind='driver.application_submitted' and body::jsonb->>'driver_id'=$1",
          [user],
        )
      ).rows[0].count,
      0,
    );
    await db.exec("set role authenticated");
    assert.equal(
      (await rpc("submit_driver_application", [vehicle])).state,
      "submitted",
    );
    assert.equal(
      (await rpc("submit_driver_application", [vehicle])).already_submitted,
      true,
    );
    await expectRejected(
      () =>
        rpc("account_action", [
          "driver_identity",
          JSON.stringify({
            full_name: "اسم آخر",
            phone: "٠٥٩٢٢٠٨١٣٣",
            date_of_birth: "1990-01-01",
          }),
        ]),
      /APPLICATION_ALREADY_SUBMITTED/,
    );
    await expectRejected(
      () =>
        rpc("account_action_before_applications", ["register_vehicle", "{}"]),
      /permission denied/,
    );
    await db.exec("reset role");
    const notices = (
      await q(
        "select * from notifications where user_id=$1 and kind='driver.application_submitted' and body::jsonb->>'driver_id'=$2",
        [ids.owner, user],
      )
    ).rows;
    assert.equal(notices.length, 1);
    assert.equal(JSON.parse(notices[0].body).phone, undefined);
    assert.equal(
      (
        await q("select * from driver_application_emails where vehicle_id=$1", [
          vehicle,
        ])
      ).rows.length,
      1,
    );
    await db.exec("set role authenticated");
    await expectRejected(
      () => rpc("claim_driver_application_emails", []),
      /permission denied/,
    );
    await db.exec("reset role; set role service_role");
    const jobs = await rpc("claim_driver_application_emails", []);
    assert.equal(jobs.length, 1);
    assert.equal(jobs[0].email, "arabic-driver@example.test");
    assert.equal((await rpc("claim_driver_application_emails", [])).length, 0);
    await rpc("finish_driver_application_email", [
      jobs[0].id,
      "00000000-0000-0000-0000-000000000000",
      true,
    ]);
    await db.exec("reset role");
    assert.equal(
      (
        await q(
          "select delivered_at from driver_application_emails where id=$1",
          [jobs[0].id],
        )
      ).rows[0].delivered_at,
      null,
    );
    await rpc("finish_driver_application_email", [
      jobs[0].id,
      jobs[0].lease,
      false,
    ]);
    await q(
      "update driver_application_emails set available_at=now() where id=$1",
      [jobs[0].id],
    );
    const retry = (await rpc("claim_driver_application_emails", []))[0];
    assert.notEqual(retry.lease, jobs[0].lease);
    await rpc("finish_driver_application_email", [retry.id, retry.lease, true]);
    assert.equal((await rpc("claim_driver_application_emails", [])).length, 0);
    assert.equal(
      (await q("select approved from vehicles where id=$1", [vehicle])).rows[0]
        .approved,
      false,
    );
  } finally {
    await db.exec("rollback");
  }
});
test("private storage policies enforce owner paths and admin MFA, and disabled accounts lose access", async () => {
  const path = `${ids.driver}/${ids.vehicle}/test.pdf`;
  await identity("driver");
  await db.exec("set role authenticated");
  await q(
    "insert into storage.objects(name,bucket_id) values($1,'driver-documents')",
    [path],
  );
  assert.equal((await q("select * from storage.objects")).rows.length, 1);
  await db.exec("reset role");
  await identity("other");
  await db.exec("set role authenticated");
  assert.equal((await q("select * from storage.objects")).rows.length, 0);
  await assert.rejects(
    () =>
      q(
        "insert into storage.objects(name,bucket_id) values($1,'driver-documents')",
        [path],
      ),
    /row-level security/,
  );
  await assert.rejects(
    () => rpc("claim_notifications", []),
    /permission denied/,
  );
  await assert.rejects(() => rpc("process_dispatch", []), /permission denied/);
  await assert.rejects(
    () => rpc("notify_user", [ids.other, "fake", "fake", null]),
    /permission denied/,
  );
  await db.exec("reset role");
  await identity("owner", "aal1");
  await db.exec("set role authenticated");
  assert.equal((await q("select * from storage.objects")).rows.length, 0);
  await db.exec("reset role");
  await identity("owner", "aal2");
  await db.exec("set role authenticated");
  assert.equal((await q("select * from storage.objects")).rows.length, 1);
  const overview = await rpc("admin_overview", []);
  assert.equal(overview.drivers, 1);
  await db.exec("reset role");
  await q("update profiles set disabled=true where id=$1", [ids.driver]);
  await identity("driver");
  await db.exec("set role authenticated");
  assert.equal((await q("select * from documents")).rows.length, 0);
  assert.equal((await q("select * from storage.objects")).rows.length, 0);
  await db.exec("reset role");
  await q("update profiles set disabled=false where id=$1", [ids.driver]);
});
after(() => db.close());

test("admin search is MFA protected, allowlisted, and includes readable driver names", async () => {
  await identity("owner", "aal1");
  await assert.rejects(
    () => rpc("admin_page", ["vehicles", "", 0]),
    /ADMIN_MFA_REQUIRED/,
  );
  await identity("owner", "aal2");
  const page = await rpc("admin_page", ["vehicles", "Driver", 0]);
  assert.equal(page.count, 1);
  assert.equal(page.rows[0].driver_id_label, "Test Driver");
  await assert.rejects(
    () => rpc("admin_page", ["profiles; drop table profiles", "", 0]),
    /INVALID_PAGE_QUERY/,
  );
  assert.equal((await rpc("admin_page", ["vehicles", "%", 0])).count, 0);
});

test("notification outbox leases jobs once and retries failed deliveries", async () => {
  await q("delete from notification_jobs");
  await identity("owner", "aal2");
  await rpc("admin_action", [
    "notify_user",
    JSON.stringify({ id: ids.rider, body: "Test notification" }),
  ]);
  await db.exec("set role service_role");
  const jobs = await rpc("claim_notifications", []);
  assert.equal(jobs.length, 1);
  assert.equal(jobs[0].attempts, 1);
  assert.equal((await rpc("claim_notifications", [])).length, 0);
  await rpc("finish_notification", [jobs[0].id, false, "test failure"]);
  assert.equal((await rpc("claim_notifications", [])).length, 0);
  await db.exec("reset role");
  await q(
    "update notification_jobs set available_at=now()-interval '1 second'",
  );
  await db.exec("set role service_role");
  const retried = await rpc("claim_notifications", []);
  assert.equal(retried.length, 1);
  assert.equal(retried[0].attempts, 2);
  await rpc("finish_notification", [retried[0].id, true, null]);
  assert.equal((await rpc("claim_notifications", [])).length, 0);
  await db.exec("reset role");
});

test("permit enforcement, reverse direction and intermediate stops", async () => {
  await assert.rejects(
    () => trip({ route_id: "30000000-0000-0000-0000-000000000099" }),
    /PERMIT_ROUTE_MISMATCH/,
  );
  assert.equal(
    await rpc("route_pair_valid", [ids.route, ids.a, ids.b, 1]),
    true,
  );
  assert.equal(
    await rpc("route_pair_valid", [ids.route, ids.b, ids.a, -1]),
    true,
  );
  assert.equal(
    await rpc("route_pair_valid", [ids.route, ids.a, ids.b, -1]),
    false,
  );
});
test("last seat is accepted once; requests do not reserve seats", async () => {
  const t = await trip();
  const a = await request(t);
  const b = await request(t, "other");
  assert.equal(await rpc("available_seats", [t]), 1);
  await identity("driver");
  const results = await Promise.allSettled([
    rpc("accept_booking", [a]),
    rpc("accept_booking", [b]),
  ]);
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
  assert.match(
    results.find((r) => r.status === "rejected").reason.message,
    /NO_SEATS/,
  );
  assert.equal(await rpc("available_seats", [t]), 0);
  await rpc("trip_action", [t, "cancel", "{}"]);
});
test("unapproved/expired drivers and overlapping trips cannot operate", async () => {
  await q("update vehicles set approved=false where id=$1", [ids.vehicle]);
  await assert.rejects(() => trip(), /DRIVER_NOT_APPROVED/);
  await q("update vehicles set approved=true where id=$1", [ids.vehicle]);
  await q(
    "update documents set expires_on=current_date-1 where kind='insurance'",
  );
  await assert.rejects(() => trip(), /DRIVER_NOT_APPROVED/);
  await q(
    "update documents set expires_on=current_date+365 where kind='insurance'",
  );
  await assert.rejects(() => trip(), /DRIVER_NOT_APPROVED/);
  await identity("owner", "aal2");
  await rpc("admin_action", [
    "approve_vehicle",
    JSON.stringify({ id: ids.vehicle, capacity: 7 }),
  ]);
  const t = await trip();
  await assert.rejects(() => trip(), /VEHICLE_TIME_CONFLICT/);
  await rpc("trip_action", [t, "cancel", "{}"]);
});
test("boarding does not deduct twice; street passengers cannot take reservations", async () => {
  const t = await trip({
    starts_at: new Date(Date.now() + 5000).toISOString(),
    ends_at: new Date(Date.now() + 3600000).toISOString(),
    instant: true,
  });
  const b = await request(t);
  await identity("driver");
  await rpc("accept_booking", [b]);
  await rpc("trip_action", [t, "start", "{}"]);
  await assert.rejects(
    () => rpc("trip_action", [t, "street", '{"delta":1}']),
    /NO_SEATS/,
  );
  await rpc("booking_action", [b, "board", null]);
  assert.equal(await rpc("available_seats", [t]), 0);
  await rpc("booking_action", [b, "alight", null]);
  assert.equal(await rpc("available_seats", [t]), 1);
  await rpc("trip_action", [t, "street", '{"delta":1}']);
  await rpc("trip_action", [t, "street", '{"delta":-1}']);
  await assert.rejects(
    () => rpc("trip_action", [t, "street", '{"delta":-1}']),
    /NO_SEATS/,
  );
  await rpc("trip_action", [t, "finish", "{}"]);
});
test("scheduled seat is not resold after a partial ride; change requires consent", async () => {
  const t = await trip();
  const b = await request(t);
  await identity("driver");
  await rpc("accept_booking", [b]);
  await rpc("trip_action", [
    t,
    "reschedule",
    JSON.stringify({
      starts_at: new Date(Date.now() + 172800000).toISOString(),
      ends_at: new Date(Date.now() + 176400000).toISOString(),
    }),
  ]);
  assert.equal(
    (await q("select state from bookings where id=$1", [b])).rows[0].state,
    "reschedule_pending",
  );
  await identity("rider");
  await rpc("booking_action", [b, "decline_time", null]);
  assert.equal(await rpc("available_seats", [t]), 1);
  assert.equal(
    (await q("select count(*)::integer n from violations")).rows[0].n,
    0,
  );
  await identity("driver");
  await rpc("trip_action", [t, "cancel", "{}"]);
});
test("suspension warning, third violation and owner appeal restoration", async () => {
  for (let i = 0; i < 3; i++) {
    const t = await trip({
      instant: true,
      starts_at: new Date(Date.now() + 5000).toISOString(),
      ends_at: new Date(Date.now() + 3600000).toISOString(),
    });
    const b = await request(t);
    await identity("driver");
    await rpc("accept_booking", [b]);
    await rpc("trip_action", [t, "start", "{}"]);
    await rpc("booking_action", [b, "pickup", null]);
    await identity("rider");
    await rpc("booking_action", [b, "cancel", "test"]);
    await identity("driver");
    await rpc("trip_action", [t, "cancel", "{}"]);
  }
  const t = await trip();
  await assert.rejects(() => request(t), /ACCOUNT_SUSPENDED/);
  const violations = (
    await q("select id from violations where user_id=$1", [ids.rider])
  ).rows;
  await identity("rider");
  await rpc("account_action", [
    "appeal",
    JSON.stringify({
      violation_id: violations[0].id,
      message: "Please review this cancellation",
    }),
  ]);
  const appeal = (await q("select id from appeals")).rows[0].id;
  await identity("owner");
  await assert.rejects(
    () =>
      rpc("admin_action", ["restore_user", JSON.stringify({ id: ids.rider })]),
    /ADMIN_MFA_REQUIRED/,
  );
  await identity("owner", "aal2");
  await rpc("admin_action", [
    "resolve_appeal",
    JSON.stringify({ id: appeal, accepted: true, resolution: "Reviewed" }),
  ]);
  assert.equal(
    (await q("select suspended_until from profiles where id=$1", [ids.rider]))
      .rows[0].suspended_until,
    null,
  );
  await identity("driver");
  await rpc("trip_action", [t, "cancel", "{}"]);
});
test("RLS prevents PII access, privilege escalation and unauthorized tracking", async () => {
  const t = await trip({
    instant: true,
    starts_at: new Date(Date.now() + 5000).toISOString(),
    ends_at: new Date(Date.now() + 3600000).toISOString(),
  });
  const b = await request(t);
  await identity("driver");
  await rpc("accept_booking", [b]);
  await rpc("account_action", [
    "online",
    JSON.stringify({ vehicle_id: ids.vehicle, online: true }),
  ]);
  await rpc("update_location", [ids.vehicle, 31.4, 35.07]);
  await identity("rider");
  await db.exec("set role authenticated");
  assert.equal((await q("select * from vehicle_locations")).rows.length, 1);
  await db.exec("reset role");
  await identity("driver");
  await rpc("trip_action", [t, "start", "{}"]);
  await rpc("account_action", [
    "online",
    JSON.stringify({ vehicle_id: ids.vehicle, online: true }),
  ]);
  await rpc("update_location", [ids.vehicle, 31.4, 35.07]);
  await identity("other");
  await db.exec("set role authenticated");
  assert.equal((await q("select * from documents")).rows.length, 0);
  assert.equal((await q("select * from vehicle_locations")).rows.length, 0);
  await assert.rejects(
    () => q("update profiles set role='owner' where id=$1", [ids.other]),
    /permission denied/,
  );
  await db.exec("reset role");
  await identity("rider");
  await db.exec("set role authenticated");
  assert.equal((await q("select * from vehicle_locations")).rows.length, 1);
  await db.exec("reset role");
  await identity("driver");
  await rpc("booking_action", [b, "board", null]);
  await rpc("booking_action", [b, "alight", null]);
  await identity("rider");
  await db.exec("set role authenticated");
  assert.equal((await q("select * from vehicle_locations")).rows.length, 0);
  await db.exec("reset role");
  await identity("driver");
  await rpc("trip_action", [t, "finish", "{}"]);
});
test("dispatch chooses nearest fresh car, retries after timeout, and expires after two minutes", async () => {
  const vehicle2 = "20000000-0000-0000-0000-000000000002";
  await q(
    "insert into auth.users(id,email,raw_user_meta_data) values($1,'driver2@example.test','{\"full_name\":\"Second driver\"}')",
    [ids.driver2],
  );
  await q("update profiles set role='driver' where id=$1", [ids.driver2]);
  await q(
    "insert into driver_details(user_id,date_of_birth,phone) values($1,'1990-01-01','+970599000002')",
    [ids.driver2],
  );
  await q(
    "insert into vehicles(id,driver_id,plate,kind,capacity,approved,online) values($1,$2,'TEST-2','minibus',7,true,true)",
    [vehicle2, ids.driver2],
  );
  await q("insert into vehicle_routes values($1,$2)", [vehicle2, ids.route]);
  await q(
    "insert into documents(vehicle_id,kind,storage_path,expires_on,verified) select $1,kind,storage_path,expires_on,verified from documents where vehicle_id=$2",
    [vehicle2, ids.vehicle],
  );
  const starts_at = new Date(Date.now() + 5000).toISOString(),
    ends_at = new Date(Date.now() + 3600000).toISOString();
  const a = await trip({ instant: true, starts_at, ends_at });
  const b = await trip(
    {
      vehicle_id: vehicle2,
      instant: true,
      starts_at,
      ends_at,
    },
    "driver2",
  );
  await identity("driver");
  await rpc("account_action", [
    "online",
    JSON.stringify({ vehicle_id: ids.vehicle, online: true }),
  ]);
  await rpc("update_location", [ids.vehicle, 31.4, 35.07]);
  await identity("driver2");
  await rpc("update_location", [vehicle2, 31.5, 35.08]);
  await identity("other");
  const rid = await rpc("post_request", [
    JSON.stringify({
      mode: "instant",
      origin: "السموع",
      destination: "الخليل",
      origin_stop_id: ids.a,
      destination_stop_id: ids.b,
      route_id: ids.route,
      service: "shared",
      seats: 1,
      latitude: 31.4,
      longitude: 35.07,
      requested_at: starts_at,
      quoted_price: 15,
    }),
  ]);
  let booking = (
    await q("select * from bookings where request_id=$1 and state='pending'", [
      rid,
    ])
  ).rows[0];
  assert.equal(booking.trip_id, a);
  await q(
    "update bookings set dispatch_deadline=now()-interval '1 second' where id=$1",
    [booking.id],
  );
  await rpc("process_dispatch", []);
  booking = (
    await q("select * from bookings where request_id=$1 and state='pending'", [
      rid,
    ])
  ).rows[0];
  assert.equal(booking.trip_id, b);
  await q(
    "update ride_requests set created_at=now()-interval '3 minutes' where id=$1",
    [rid],
  );
  await q(
    "update bookings set dispatch_deadline=now()-interval '1 second' where id=$1",
    [booking.id],
  );
  await rpc("process_dispatch", []);
  assert.equal(
    (await q("select state from ride_requests where id=$1", [rid])).rows[0]
      .state,
    "expired",
  );
  await identity("driver");
  await rpc("trip_action", [a, "cancel", "{}"]);
  await identity("driver2");
  await rpc("trip_action", [b, "cancel", "{}"]);
});
test("posted request offers reserve only once when rider chooses, with no extra driver approval", async () => {
  const starts_at = new Date(Date.now() + 86400000).toISOString();
  const t = await trip();
  await identity("other");
  const rid = await rpc("post_request", [
    JSON.stringify({
      mode: "posted",
      origin: "السموع",
      destination: "الخليل",
      origin_stop_id: ids.a,
      destination_stop_id: ids.b,
      route_id: ids.route,
      service: "shared",
      seats: 1,
      latitude: 31.4,
      longitude: 35.07,
      requested_at: starts_at,
    }),
  ]);
  await identity("driver");
  const offer = await rpc("offer_action", [
    JSON.stringify({ action: "create", request_id: rid, trip_id: t }),
  ]);
  assert.equal(await rpc("available_seats", [t]), 1);
  await identity("other");
  const bid = await rpc("offer_action", [
    JSON.stringify({ action: "accept", offer_id: offer }),
  ]);
  assert.equal(
    (await q("select state from bookings where id=$1", [bid])).rows[0].state,
    "confirmed",
  );
  await assert.rejects(
    () =>
      rpc("offer_action", [
        JSON.stringify({ action: "accept", offer_id: offer }),
      ]),
    /OFFER_UNAVAILABLE/,
  );
  await identity("driver");
  await rpc("trip_action", [t, "cancel", "{}"]);
});
test("private taxi reserves the whole car and no-show requires the individual pickup wait", async () => {
  const taxi = "20000000-0000-0000-0000-000000000003";
  await q(
    "insert into vehicles(id,driver_id,plate,kind,capacity,approved) values($1,$2,'TEST-3','taxi',4,true)",
    [taxi, ids.driver],
  );
  await q(
    "insert into documents(vehicle_id,kind,storage_path,expires_on,verified) select $1,kind,storage_path,expires_on,verified from documents where vehicle_id=$2 and kind<>'permit'",
    [taxi, ids.vehicle],
  );
  const t = await trip({
    vehicle_id: taxi,
    service: "private",
    route_id: null,
    instant: true,
    seat_limit: 1,
    starts_at: new Date(Date.now() + 5000).toISOString(),
    ends_at: new Date(Date.now() + 3600000).toISOString(),
  });
  await identity("other");
  await assert.rejects(
    () => rpc("request_booking", [JSON.stringify({ trip_id: t, seats: 1 })]),
    /PICKUP_REQUIRED/,
  );
  const b = await request(t, "other");
  await identity("driver");
  await rpc("accept_booking", [b]);
  assert.equal(
    (await q("select seats,total_price from bookings where id=$1", [b])).rows[0]
      .seats,
    4,
  );
  assert.equal(
    Number(
      (await q("select total_price from bookings where id=$1", [b])).rows[0]
        .total_price,
    ),
    15,
  );
  assert.equal(await rpc("available_seats", [t]), 0);
  await rpc("trip_action", [t, "start", "{}"]);
  await assert.rejects(
    () => rpc("booking_action", [b, "no_show", null]),
    /WAIT_FIVE_MINUTES/,
  );
  await rpc("booking_action", [b, "arrive", null]);
  await assert.rejects(
    () => rpc("booking_action", [b, "no_show", null]),
    /WAIT_FIVE_MINUTES/,
  );
  await rpc("trip_action", [t, "cancel", "{}"]);
});

test("operational review rejects forged endpoints, own bookings and unuploaded documents", async () => {
  await assert.rejects(
    () => trip({ destination: "رام الله" }),
    /PERMIT_ROUTE_MISMATCH/,
  );
  await identity("driver");
  const existing = (
    await q(
      "select id from trips where vehicle_id=$1 and state='published' limit 1",
      [ids.vehicle],
    )
  ).rows[0];
  if (existing)
    await assert.rejects(
      () => request(existing.id, "driver"),
      /CANNOT_BOOK_OWN_VEHICLE/,
    );
  await identity("driver");
  await assert.rejects(
    () =>
      rpc("account_action", [
        "document",
        JSON.stringify({
          vehicle_id: ids.vehicle,
          kind: "license",
          storage_path: `${ids.driver}/${ids.vehicle}/missing.pdf`,
          expires_on: "2027-10-04",
        }),
      ]),
    /DOCUMENT_UPLOAD_REQUIRED/,
  );
  const uploaded = `${ids.driver}/${ids.vehicle}/uploaded.pdf`;
  await q(
    "insert into storage.objects(name,bucket_id) values($1,'driver-documents')",
    [uploaded],
  );
  await assert.rejects(
    () =>
      rpc("account_action", [
        "document",
        JSON.stringify({
          vehicle_id: ids.vehicle,
          kind: "license",
          storage_path: uploaded,
        }),
      ]),
    /DOCUMENT_EXPIRY_REQUIRED/,
  );
  await assert.rejects(
    () =>
      rpc("account_action", [
        "document",
        JSON.stringify({
          vehicle_id: ids.vehicle,
          kind: "vehicle_photo",
          storage_path: uploaded,
        }),
      ]),
    /DOCUMENT_FORMAT/,
  );
});

test("a delayed active trip keeps the vehicle exclusive and street riders prevent cancellation", async () => {
  await q("update trips set state='cancelled' where vehicle_id=$1", [
    ids.vehicle,
  ]);
  const first = await trip({
    starts_at: new Date(Date.now() - 60000).toISOString(),
    ends_at: new Date(Date.now() + 60000).toISOString(),
    seat_limit: 7,
  });
  const second = await trip({
    starts_at: new Date(Date.now() + 120000).toISOString(),
    ends_at: new Date(Date.now() + 3600000).toISOString(),
    seat_limit: 7,
  });
  await assert.rejects(
    () => request(first, "driver"),
    /CANNOT_BOOK_OWN_VEHICLE/,
  );
  await rpc("trip_action", [first, "start", "{}"]);
  await assert.rejects(
    () => rpc("trip_action", [second, "start", "{}"]),
    /VEHICLE_ALREADY_ON_TRIP/,
  );
  await rpc("trip_action", [first, "street", '{"delta":1}']);
  await assert.rejects(
    () => rpc("trip_action", [first, "cancel", "{}"]),
    /PASSENGERS_REMAIN/,
  );
  await rpc("trip_action", [first, "street", '{"delta":-1}']);
  await rpc("trip_action", [first, "cancel", "{}"]);
  await rpc("trip_action", [second, "start", "{}"]);
  await rpc("trip_action", [second, "cancel", "{}"]);
});

test("driver signup is independent, immutable for riders, and social signup stays rider", async () => {
  await db.exec("begin");
  try {
    const newId = "10000000-0000-0000-0000-000000000010";
    const metadata = {
      full_name: "أحمد خالد",
      account_type: "driver",
      phone: "+970599123456",
      date_of_birth: "1990-02-03",
    };
    await expectRejected(
      () =>
        q(
          "insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)",
          [
            newId,
            "new-driver@example.test",
            JSON.stringify({ ...metadata, phone: "0599" }),
          ],
        ),
      /DRIVER_IDENTITY_REQUIRED/,
    );
    await expectRejected(
      () =>
        q(
          "insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)",
          [
            newId,
            "new-driver@example.test",
            JSON.stringify({ ...metadata, date_of_birth: "2100-01-01" }),
          ],
        ),
      /DRIVER_IDENTITY_REQUIRED/,
    );
    await q(
      "insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)",
      [newId, "new-driver@example.test", JSON.stringify(metadata)],
    );
    assert.equal(
      (await q("select role from profiles where id=$1", [newId])).rows[0].role,
      "driver",
    );
    assert.equal(
      (await q("select phone from driver_details where user_id=$1", [newId]))
        .rows[0].phone,
      metadata.phone,
    );
    await q(
      "insert into auth.users(id,email,raw_user_meta_data,raw_app_meta_data) values($1,'social@example.test',$2,'{\"provider\":\"google\"}')",
      ["10000000-0000-0000-0000-000000000011", JSON.stringify(metadata)],
    );
    assert.equal(
      (
        await q(
          "select role from profiles where id='10000000-0000-0000-0000-000000000011'",
        )
      ).rows[0].role,
      "rider",
    );
    await identity("rider");
    await q("update auth.users set raw_user_meta_data=$1 where id=$2", [
      JSON.stringify(metadata),
      ids.rider,
    ]);
    await db.exec("set role authenticated");
    await expectRejected(
      () =>
        rpc("account_action", [
          "register_vehicle",
          JSON.stringify({ plate: "FORGED", kind: "taxi", capacity: 4 }),
        ]),
      /DRIVER_ACCOUNT_REQUIRED/,
    );
    await expectRejected(
      () =>
        rpc("account_action", ["driver_identity", JSON.stringify(metadata)]),
      /DRIVER_ACCOUNT_REQUIRED/,
    );
    await expectRejected(
      () =>
        rpc("account_action_before_driver_accounts", [
          "register_vehicle",
          "{}",
        ]),
      /permission denied/,
    );
    assert.equal(
      (await q("select role from profiles where id=$1", [ids.rider])).rows[0]
        .role,
      "rider",
    );
    assert.equal((await q("select * from driver_details")).rows.length, 0);
    await db.exec("reset role");
    await identity("owner", "aal2");
    const page = await rpc("admin_page", ["profiles", metadata.phone, 0]);
    assert.equal(page.count, 1);
    assert.equal(page.rows[0].phone, metadata.phone);
    await identity("driver");
    await db.exec("set role authenticated");
    assert.equal((await q("select * from driver_details")).rows.length, 1);
    await db.exec("reset role");
    await q("select set_config('test.amr','[{\"method\":\"oauth\"}]',false)");
    await expectRejected(
      () => rpc("account_action", ["register_vehicle", "{}"]),
      /SOCIAL_SIGNIN_RIDERS_ONLY/,
    );
  } finally {
    await db.exec("rollback");
  }
});

test("document renewal reminders deduplicate, suspend expired driver work, and require review to resume", async () => {
  await db.exec("begin");
  try {
    await q("delete from notification_jobs");
    await q("delete from notifications");
    await q("delete from document_reminders");
    const today = (
      await q("select (now() at time zone 'Asia/Hebron')::date::text as value")
    ).rows[0].value;
    const secondCar = "20000000-0000-0000-0000-000000000020";
    await q(
      "insert into vehicles(id,driver_id,plate,kind,capacity,approved) values($1,$2,'TEST-SECOND-CAR','taxi',4,true)",
      [secondCar, ids.driver],
    );
    await q(
      "insert into documents(vehicle_id,kind,storage_path,expires_on,verified) select $1,kind,'test-only',current_date+365,true from unnest(array['license','insurance','registration','vehicle_photo']) kind",
      [secondCar],
    );
    assert.equal(await rpc("vehicle_ready", [secondCar]), true);
    const license = (
      await q(
        "select id from documents where vehicle_id=$1 and kind='license'",
        [ids.vehicle],
      )
    ).rows[0].id;
    for (const days of [30, 7, 1]) {
      await q("update documents set expires_on=$2::date+$3::int where id=$1", [
        license,
        today,
        days,
      ]);
      await rpc("process_dispatch", []);
      await rpc("process_dispatch", []);
      assert.equal(
        (
          await q(
            "select count(*)::int n from document_reminders where document_id=$1 and stage=$2",
            [license, days],
          )
        ).rows[0].n,
        1,
      );
    }
    await q("update vehicles set online=true where id=$1", [ids.vehicle]);
    await q("update documents set expires_on=$2::date-1 where id=$1", [
      license,
      today,
    ]);
    assert.equal(
      await rpc("vehicle_ready", [ids.vehicle]),
      false,
      "Expiry blocks operations before any scheduler run",
    );
    await identity("driver");
    await expectRejected(
      () =>
        rpc("account_action", [
          "online",
          JSON.stringify({ vehicle_id: ids.vehicle, online: true }),
        ]),
      /DRIVER_NOT_APPROVED/,
    );
    await rpc("process_dispatch", []);
    await rpc("process_dispatch", []);
    assert.equal(
      (await q("select online from vehicles where id=$1", [ids.vehicle]))
        .rows[0].online,
      false,
    );
    assert.equal(
      (
        await q(
          "select count(*)::int n from notifications where user_id=$1 and kind='document.expired'",
          [ids.driver],
        )
      ).rows[0].n,
      1,
    );
    assert.equal(
      (
        await q(
          "select count(*)::int n from notifications where user_id=$1 and kind='document.expired_admin'",
          [ids.owner],
        )
      ).rows[0].n,
      1,
    );
    const path = `${ids.driver}/${ids.vehicle}/renewed-license.pdf`;
    await q(
      "insert into storage.objects(name,bucket_id) values($1,'driver-documents')",
      [path],
    );
    await rpc("account_action", [
      "document",
      JSON.stringify({
        vehicle_id: ids.vehicle,
        kind: "license",
        storage_path: path,
        expires_on: "2030-01-01",
      }),
    ]);
    assert.equal(
      await rpc("vehicle_ready", [ids.vehicle]),
      false,
      "Upload alone cannot restore operations",
    );
    assert.equal(
      await rpc("vehicle_ready", [secondCar]),
      false,
      "An unreviewed renewal must keep the entire driver fleet paused",
    );
    await identity("owner", "aal2");
    await rpc("admin_action", [
      "verify_document",
      JSON.stringify({ id: license, verified: true }),
    ]);
    assert.equal(
      await rpc("vehicle_ready", [secondCar]),
      false,
      "Verification alone does not replace vehicle reapproval",
    );
    await rpc("admin_action", [
      "approve_vehicle",
      JSON.stringify({ id: ids.vehicle, capacity: 7 }),
    ]);
    assert.equal(await rpc("vehicle_ready", [ids.vehicle]), true);
    assert.equal(await rpc("vehicle_ready", [secondCar]), true);
    await q("update driver_details set date_of_birth=null where user_id=$1", [
      ids.driver,
    ]);
    assert.equal(await rpc("vehicle_ready", [ids.vehicle]), false);
    await expectRejected(
      () =>
        rpc("admin_action", [
          "approve_vehicle",
          JSON.stringify({ id: ids.vehicle, capacity: 7 }),
        ]),
      /DRIVER_IDENTITY_REQUIRED/,
    );
    await identity("rider");
    await db.exec("set role authenticated");
    await expectRejected(
      () => rpc("process_document_renewals", []),
      /permission denied/,
    );
    await expectRejected(
      () =>
        q(
          "insert into document_reminders(document_id,expires_on,stage) values($1,current_date,30)",
          [license],
        ),
      /permission denied/,
    );
  } finally {
    await db.exec("rollback");
  }
});

test("admin filters apply before pagination, enforce MFA and reject unsafe criteria", async () => {
  await db.exec("begin");
  try {
    await q(
      "insert into vehicles(id,driver_id,plate,kind,capacity,approved,created_at) select gen_random_uuid(),$1,'FILTER-'||n,'medium_bus',n,false,'2026-10-04T21:30:00Z' from generate_series(1,25) n",
      [ids.driver],
    );
    await identity("rider");
    await expectRejected(
      () =>
        rpc("admin_page_filtered", ["vehicles", "FILTER-", 0, "{}", "newest"]),
      /ADMIN_MFA_REQUIRED/,
    );
    await identity("owner", "aal2");
    const filters = JSON.stringify({
      approved: false,
      kind: "medium_bus",
      from: "2026-10-05",
      to: "2026-10-05",
    });
    const first = await rpc("admin_page_filtered", [
      "vehicles",
      "FILTER-",
      0,
      filters,
      "capacity",
    ]);
    assert.equal(first.count, 25);
    assert.equal(first.rows.length, 20);
    assert.equal(first.rows[0].capacity, 25);
    const second = await rpc("admin_page_filtered", [
      "vehicles",
      "FILTER-",
      1,
      filters,
      "capacity",
    ]);
    assert.equal(second.rows.length, 5);
    assert.equal(second.rows[0].capacity, 5);
    assert.equal(
      (
        await rpc("admin_page_filtered", [
          "vehicles",
          "FILTER-",
          0,
          JSON.stringify({ approved: true }),
          "newest",
        ])
      ).count,
      0,
    );
    assert.equal(
      (
        await rpc("admin_page_filtered", [
          "vehicles",
          "FILTER-",
          0,
          JSON.stringify({ to: "2026-10-04" }),
          "newest",
        ])
      ).count,
      0,
    );
    await expectRejected(
      () =>
        rpc("admin_page_filtered", [
          "vehicles",
          "",
          0,
          JSON.stringify({ phone: "private" }),
          "newest",
        ]),
      /INVALID_ADMIN_FILTER/,
    );
    await expectRejected(
      () =>
        rpc("admin_page_filtered", [
          "vehicles",
          "",
          0,
          JSON.stringify({ approved: "false" }),
          "newest",
        ]),
      /INVALID_ADMIN_FILTER/,
    );
    await expectRejected(
      () =>
        rpc("admin_page_filtered", [
          "vehicles",
          "",
          0,
          JSON.stringify({ from: "2026-10-05", to: "2026-10-04" }),
          "newest",
        ]),
      /INVALID_ADMIN_DATE/,
    );
    await expectRejected(
      () =>
        rpc("admin_page_filtered", [
          "vehicles",
          "",
          0,
          "{}",
          "capacity; select 1",
        ]),
      /INVALID_ADMIN_SORT/,
    );
  } finally {
    await db.exec("rollback");
  }
});

test("Rejected applications can be corrected and submitted as one new review revision", async () => {
  await db.exec("begin");
  try {
    const user = "10000000-0000-0000-0000-000000000098";
    await q(
      "insert into auth.users(id,email,raw_user_meta_data) values($1,'revision@example.test',$2)",
      [
        user,
        JSON.stringify({
          account_type: "driver",
          full_name: "Revision Driver",
          phone: "+970599000000",
          date_of_birth: "1990-01-01",
        }),
      ],
    );
    await q(
      "select set_config('test.uid',$1,false),set_config('test.aal','aal1',false)",
      [user],
    );
    const vehicle = (
      await rpc("account_action", [
        "register_vehicle",
        JSON.stringify({
          plate: "REVISION-1",
          kind: "taxi",
          capacity: 4,
          vehicle_owner_name: "Vehicle Owner",
        }),
      ])
    ).id;
    for (const kind of [
      "license",
      "insurance",
      "registration",
      "vehicle_photo",
    ]) {
      const storage_path = user + "/" + vehicle + "/" + kind + ".jpg";
      await q(
        "insert into storage.objects(name,bucket_id) values($1,'driver-documents')",
        [storage_path],
      );
      await rpc("account_action", [
        "document",
        JSON.stringify({
          vehicle_id: vehicle,
          kind,
          storage_path,
          expires_on: "2099-01-01",
        }),
      ]);
    }
    await rpc("submit_driver_application", [vehicle]);
    await identity("owner", "aal2");
    await rpc("admin_action", [
      "reject_vehicle",
      JSON.stringify({ id: vehicle, note: "Clarify ownership" }),
    ]);
    assert.equal(
      (
        await q("select state from driver_applications where vehicle_id=$1", [
          vehicle,
        ])
      ).rows[0].state,
      "rejected",
    );
    await q(
      "select set_config('test.uid',$1,false),set_config('test.aal','aal1',false)",
      [user],
    );
    await rpc("account_action", [
      "update_vehicle_draft",
      JSON.stringify({
        vehicle_id: vehicle,
        plate: "REVISION-1",
        kind: "taxi",
        capacity: 4,
        vehicle_owner_name: "Corrected Owner",
      }),
    ]);
    await rpc("submit_driver_application", [vehicle]);
    await rpc("submit_driver_application", [vehicle]);
    assert.equal(
      (
        await q(
          "select revision from driver_applications where vehicle_id=$1",
          [vehicle],
        )
      ).rows[0].revision,
      2,
    );
    assert.equal(
      (
        await q(
          "select count(*)::int as n from driver_application_emails where vehicle_id=$1",
          [vehicle],
        )
      ).rows[0].n,
      2,
    );
    assert.equal(
      (
        await q(
          "select count(*)::int as n from notifications where user_id=$1 and kind='driver.application_submitted' and body::jsonb->>'vehicle_id'=$2",
          [ids.owner, vehicle],
        )
      ).rows[0].n,
      2,
    );
  } finally {
    await db.exec("rollback");
  }
});

test("Private taxi offers reject oversized groups and a driver cannot offer their own vehicle to themselves", async () => {
  await db.exec("begin");
  try {
    const user = "10000000-0000-0000-0000-000000000099";
    await q(
      "insert into auth.users(id,email,raw_user_meta_data) values($1,'offer-guard@example.test',$2)",
      [
        user,
        JSON.stringify({
          account_type: "driver",
          full_name: "Offer Guard Driver",
          phone: "+970599000001",
          date_of_birth: "1990-01-01",
        }),
      ],
    );
    await q(
      "select set_config('test.uid',$1,false),set_config('test.aal','aal1',false)",
      [user],
    );
    const vehicle = (
      await rpc("account_action", [
        "register_vehicle",
        JSON.stringify({
          kind: "taxi",
          capacity: 4,
          plate: "OFFER-GUARD-1",
          vehicle_owner_name: "Fixture Owner",
        }),
      ])
    ).id;
    await q("update vehicles set approved=true where id=$1", [vehicle]);
    for (const kind of [
      "license",
      "insurance",
      "registration",
      "vehicle_photo",
    ])
      await q(
        "insert into documents(vehicle_id,kind,storage_path,expires_on,verified) values($1,$2,'fixture-only','2099-01-01',true)",
        [vehicle, kind],
      );
    const trip = await rpc("publish_trip", [
      JSON.stringify({
        vehicle_id: vehicle,
        service: "private",
        origin: "Fixture pickup",
        destination: "Fixture destination",
        starts_at: new Date(Date.now() + 600000).toISOString(),
        ends_at: new Date(Date.now() + 7200000).toISOString(),
        price: 42.5,
        seat_limit: 4,
      }),
    ]);
    const requestParameters = {
      mode: "posted",
      service: "private",
      origin: "Fixture pickup",
      destination: "Fixture destination",
      latitude: 31.4,
      longitude: 35.07,
      requested_at: new Date(Date.now() + 600000).toISOString(),
    };
    await identity("rider");
    const oversized = await rpc("post_request", [
      JSON.stringify({ ...requestParameters, seats: 5 }),
    ]);
    await q(
      "select set_config('test.uid',$1,false),set_config('test.aal','aal1',false)",
      [user],
    );
    await expectRejected(
      () =>
        rpc("offer_action", [
          JSON.stringify({
            action: "create",
            request_id: oversized,
            trip_id: trip,
          }),
        ]),
      /INVALID_CAPACITY/,
    );
    const oversizedOffer = (
      await q(
        "insert into offers(request_id,trip_id) values($1,$2) returning id",
        [oversized, trip],
      )
    ).rows[0].id;
    await identity("rider");
    await expectRejected(
      () =>
        rpc("offer_action", [
          JSON.stringify({ action: "accept", offer_id: oversizedOffer }),
        ]),
      /INVALID_CAPACITY/,
    );
    await q(
      "select set_config('test.uid',$1,false),set_config('test.aal','aal1',false)",
      [user],
    );
    const own = await rpc("post_request", [
      JSON.stringify({ ...requestParameters, seats: 2 }),
    ]);
    await expectRejected(
      () =>
        rpc("offer_action", [
          JSON.stringify({ action: "create", request_id: own, trip_id: trip }),
        ]),
      /CANNOT_BOOK_OWN_VEHICLE/,
    );
    const ownOffer = (
      await q(
        "insert into offers(request_id,trip_id) values($1,$2) returning id",
        [own, trip],
      )
    ).rows[0].id;
    await expectRejected(
      () =>
        rpc("offer_action", [
          JSON.stringify({ action: "accept", offer_id: ownOffer }),
        ]),
      /CANNOT_BOOK_OWN_VEHICLE/,
    );
    await identity("rider");
    const valid = await rpc("post_request", [
      JSON.stringify({ ...requestParameters, seats: 2 }),
    ]);
    await q(
      "select set_config('test.uid',$1,false),set_config('test.aal','aal1',false)",
      [user],
    );
    const offer = await rpc("offer_action", [
      JSON.stringify({ action: "create", request_id: valid, trip_id: trip }),
    ]);
    await identity("rider");
    const booking = await rpc("offer_action", [
      JSON.stringify({ action: "accept", offer_id: offer }),
    ]);
    const actual = (
      await q("select seats,total_price,state from bookings where id=$1", [
        booking,
      ])
    ).rows[0];
    assert.equal(actual.seats, 4);
    assert.equal(Number(actual.total_price), 42.5);
    assert.equal(actual.state, "confirmed");
  } finally {
    await db.exec("rollback");
  }
});

test("Driver seat overview can read every allocation while a passenger only reads their own bookings", async () => {
  await db.exec("begin");
  try {
    const vehicle = (
      await q(
        "insert into vehicles(driver_id,plate,kind,capacity) values($1,'SEAT-OVERVIEW','minibus',7) returning id",
        [ids.driver],
      )
    ).rows[0].id;
    const trip = (
      await q(
        "insert into trips(vehicle_id,route_id,service,origin,destination,starts_at,ends_at,price,seat_limit,street_passengers) values($1,$2,'shared','السموع','الخليل',now()+interval '1 day',now()+interval '25 hours',15,7,1) returning id",
        [vehicle, ids.route],
      )
    ).rows[0].id;
    await q(
      "insert into bookings(trip_id,rider_id,seats,total_price,state) values($1,$2,2,30,'confirmed'),($1,$3,1,15,'boarded'),($1,$2,1,15,'completed'),($1,$3,4,60,'cancelled')",
      [trip, ids.rider, ids.other],
    );
    await identity("driver");
    await db.exec("set local role authenticated");
    const overview = (
      await q(
        "select b.state,b.seats from trips t join bookings b on b.trip_id=t.id where t.vehicle_id=$1 order by b.state",
        [vehicle],
      )
    ).rows;
    assert.equal(overview.length, 4);
    assert.deepEqual(overview.map((row) => row.state).sort(), [
      "boarded",
      "cancelled",
      "completed",
      "confirmed",
    ]);
    const totals = (
      await q(
        "select t.street_passengers + coalesce(sum(b.seats) filter(where b.state='boarded'),0) as occupied,coalesce(sum(b.seats) filter(where b.state in ('confirmed','reschedule_pending')),0) as reserved,coalesce(sum(b.seats) filter(where b.state='completed'),0) as retained,public.available_seats(t.id) as available from trips t left join bookings b on b.trip_id=t.id where t.vehicle_id=$1 group by t.id",
        [vehicle],
      )
    ).rows[0];
    assert.deepEqual(
      Object.fromEntries(
        Object.entries(totals).map(([key, value]) => [key, Number(value)]),
      ),
      { occupied: 2, reserved: 2, retained: 1, available: 2 },
    );
    await identity("rider");
    const own = (
      await q(
        "select b.rider_id,b.state from trips t join bookings b on b.trip_id=t.id where t.vehicle_id=$1",
        [vehicle],
      )
    ).rows;
    assert.equal(own.length, 2);
    assert.ok(own.every((row) => row.rider_id === ids.rider));
  } finally {
    await db.exec("rollback");
  }
});

test("Confirmed posted requests follow trip cancellation, schedule decline and no-show terminal states", async () => {
  for (const outcome of ["trip_cancel", "decline_time", "no_show"]) {
    await db.exec("begin");
    try {
      await q("update trips set state='cancelled' where vehicle_id=$1", [
        ids.vehicle,
      ]);
      await q(
        "update profiles set disabled=false,suspended_until=null where id in ($1,$2)",
        [ids.driver, ids.rider],
      );
      const tid = await trip({ seat_limit: 3 });
      await identity("rider");
      const rid = await rpc("post_request", [
        JSON.stringify({
          mode: "posted",
          origin: "السموع",
          destination: "الخليل",
          origin_stop_id: ids.a,
          destination_stop_id: ids.b,
          route_id: ids.route,
          service: "shared",
          seats: 1,
          latitude: 31.4,
          longitude: 35.07,
          requested_at: new Date(Date.now() + 86400000).toISOString(),
        }),
      ]);
      await identity("driver");
      const offer = await rpc("offer_action", [
        JSON.stringify({ action: "create", request_id: rid, trip_id: tid }),
      ]);
      await identity("rider");
      const bid = await rpc("offer_action", [
        JSON.stringify({ action: "accept", offer_id: offer }),
      ]);
      assert.equal(
        (await q("select state from ride_requests where id=$1", [rid])).rows[0]
          .state,
        "booked",
      );
      await identity("driver");
      if (outcome === "trip_cancel")
        await rpc("trip_action", [tid, "cancel", "{}"]);
      else if (outcome === "decline_time") {
        await rpc("trip_action", [
          tid,
          "reschedule",
          JSON.stringify({
            starts_at: new Date(Date.now() + 172800000).toISOString(),
            ends_at: new Date(Date.now() + 176400000).toISOString(),
          }),
        ]);
        await identity("rider");
        await rpc("booking_action", [bid, "decline_time", null]);
      } else {
        await q(
          "update trips set starts_at=now()-interval '10 minutes',ends_at=now()+interval '1 hour' where id=$1",
          [tid],
        );
        await rpc("trip_action", [tid, "start", "{}"]);
        await rpc("booking_action", [bid, "arrive", null]);
        await q(
          "update bookings set arrived_at=now()-interval '6 minutes' where id=$1",
          [bid],
        );
        await rpc("booking_action", [bid, "no_show", null]);
      }
      assert.equal(
        (await q("select state from ride_requests where id=$1", [rid])).rows[0]
          .state,
        "cancelled",
        outcome,
      );
      assert.equal(
        (await q("select state from bookings where id=$1", [bid])).rows[0]
          .state,
        outcome === "no_show" ? "no_show" : "cancelled",
      );
      assert.equal(await rpc("available_seats", [tid]), 3);
      const violations = (
        await q(
          "select count(*)::integer n from violations where booking_id=$1",
          [bid],
        )
      ).rows[0].n;
      assert.equal(violations, outcome === "no_show" ? 1 : 0);
    } finally {
      await db.exec("rollback");
    }
  }
});

test("Repeated driver cancellations notify staff once while rider and staff cancellations do not count", async () => {
  await db.exec("begin");
  try {
    const user = (
      await q(
        "insert into auth.users(id,email,raw_user_meta_data) values(gen_random_uuid(),'cancellation-review@example.test','{\"full_name\":\"سائق فحص الإلغاء\"}') returning id",
      )
    ).rows[0].id;
    await q("update profiles set role='driver' where id=$1", [user]);
    await q(
      "insert into driver_details(user_id,date_of_birth,phone) values($1,'1990-01-01','+970599000007')",
      [user],
    );
    const vehicle = (
      await q(
        "insert into vehicles(driver_id,plate,kind,capacity,approved) values($1,'CANCEL-REVIEW','taxi',4,true) returning id",
        [user],
      )
    ).rows[0].id;
    for (const kind of [
      "license",
      "insurance",
      "registration",
      "vehicle_photo",
    ])
      await q(
        "insert into documents(vehicle_id,kind,storage_path,expires_on,verified) values($1,$2,'fixture-only',$3,true)",
        [
          vehicle,
          kind,
          kind === "vehicle_photo"
            ? null
            : new Date(Date.now() + 31536000000).toISOString().slice(0, 10),
        ],
      );
    const setDriver = () =>
      q(
        "select set_config('test.uid',$1,false),set_config('test.aal','aal1',false)",
        [user],
      );
    let index = 0;
    const book = async (withRider = true) => {
      const starts_at = new Date(Date.now() + ++index * 86400000).toISOString();
      const ends_at = new Date(Date.parse(starts_at) + 3600000).toISOString();
      await setDriver();
      const tid = await rpc("publish_trip", [
        JSON.stringify({
          vehicle_id: vehicle,
          service: "private",
          origin: "السموع",
          destination: "الخليل",
          seat_limit: 4,
          price: 45,
          starts_at,
          ends_at,
        }),
      ]);
      if (!withRider) return { tid };
      await identity("other");
      const rid = await rpc("post_request", [
        JSON.stringify({
          mode: "posted",
          origin: "السموع",
          destination: "الخليل",
          service: "private",
          seats: 2,
          latitude: 31.4,
          longitude: 35.07,
          requested_at: starts_at,
        }),
      ]);
      await setDriver();
      const offer = await rpc("offer_action", [
        JSON.stringify({ action: "create", request_id: rid, trip_id: tid }),
      ]);
      await identity("other");
      const bid = await rpc("offer_action", [
        JSON.stringify({ action: "accept", offer_id: offer }),
      ]);
      return { tid, bid, rid };
    };
    const notices = async () =>
      (
        await q(
          "select * from notifications where user_id=$1 and kind='driver.cancellation_review' and body::jsonb->>'driver_id'=$2",
          [ids.owner, user],
        )
      ).rows;
    const empty = await book(false);
    await setDriver();
    await rpc("trip_action", [empty.tid, "cancel", "{}"]);
    const rider = await book();
    await identity("other");
    await rpc("booking_action", [rider.bid, "cancel", "driver_cancelled"]);
    const staff = await book();
    await identity("owner", "aal2");
    await rpc("booking_action", [staff.bid, "cancel", null]);
    assert.equal((await notices()).length, 0);
    for (let i = 0; i < 4; i++) {
      const booked = await book();
      await setDriver();
      if (i === 1) await rpc("booking_action", [booked.bid, "cancel", null]);
      else await rpc("trip_action", [booked.tid, "cancel", "{}"]);
      const alerts = await notices();
      assert.equal(alerts.length, i < 2 ? 0 : 1);
      if (i >= 2) {
        const body = JSON.parse(alerts[0].body);
        assert.equal(body.count, 3);
        assert.equal(body.window_days, 30);
        assert.equal(body.driver_id, user);
      }
      assert.equal(
        (
          await q(
            "select count(*)::integer n from violations where booking_id=$1",
            [booked.bid],
          )
        ).rows[0].n,
        0,
      );
    }
    const profile = (
      await q("select suspended_until,disabled from profiles where id=$1", [
        user,
      ])
    ).rows[0];
    assert.equal(profile.suspended_until, null);
    assert.equal(profile.disabled, false);
    assert.equal(
      (
        await q(
          "select count(*)::integer n from audit_log where action='driver.cancellation_review' and entity_id=$1",
          [user],
        )
      ).rows[0].n,
      1,
    );
  } finally {
    await db.exec("rollback");
  }
});
