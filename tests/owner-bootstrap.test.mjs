import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { PGlite } from "@electric-sql/pglite";

test("initial owner promotion requires a verified account and cannot run twice", async () => {
  const db = new PGlite();
  try {
    await db.exec(`create schema auth;
      create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);
      create table profiles(id uuid primary key,full_name text,role text);
      create table audit_log(actor_id uuid,action text,entity_id uuid,details jsonb);
      insert into auth.users values('10000000-0000-0000-0000-000000000001','owner@example.test',null);
      insert into profiles values('10000000-0000-0000-0000-000000000001','Owner','rider');`);
    // psql substitutes this variable as a quoted SQL literal. No real credentials.
    const sql = (
      await readFile("supabase/bootstrap_owner.sql", "utf8")
    ).replaceAll(":'owner_email'", "'owner@example.test'");
    await assert.rejects(
      db.exec(sql),
      /EXACTLY_ONE_VERIFIED_OWNER_ACCOUNT_REQUIRED/,
    );
    await db.exec("rollback");
    assert.equal(
      (await db.query("select role from profiles")).rows[0].role,
      "rider",
    );
    await db.exec("update auth.users set email_confirmed_at=now()");
    await db.exec(sql);
    assert.equal(
      (await db.query("select role from profiles")).rows[0].role,
      "owner",
    );
    assert.equal(
      (await db.query("select count(*)::integer as n from audit_log")).rows[0]
        .n,
      1,
    );
    await assert.rejects(
      db.exec(sql),
      /OWNER_ALREADY_EXISTS_USE_OWNER_ADMINISTRATION/,
    );
    await db.exec("rollback");
    assert.equal(
      (await db.query("select count(*)::integer as n from audit_log")).rows[0]
        .n,
      1,
    );
  } finally {
    await db.close();
  }
});
