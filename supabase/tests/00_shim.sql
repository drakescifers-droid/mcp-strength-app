-- ============================================================================
-- Test shim — the parts of Supabase the migrations depend on
--
-- Applied BEFORE the migrations when running against a plain Postgres
-- container. It creates the smallest surface the migrations actually touch:
-- the `auth` schema, an `auth.users` table to hang foreign keys off, an
-- `auth.uid()` that reads the same GUC PostgREST sets, and the three Supabase
-- roles.
--
-- It also reproduces Supabase's DEFAULT PRIVILEGES, which grant new tables in
-- `public` to anon and authenticated. That is not incidental — the RLS
-- migration's `revoke all ... from anon` only means something if there was a
-- grant to revoke, and a shim without it would make that line look correct
-- while testing nothing.
--
-- This file is NOT a migration. It never runs against a real project, where
-- all of this already exists.
-- ============================================================================

create schema if not exists auth;

create table if not exists auth.users (
  id     uuid primary key,
  email  text
);

-- PostgREST puts the JWT's `sub` claim in this GUC on every request.
-- `true` on current_setting means "return null if unset" rather than error,
-- matching the real function's behaviour for an unauthenticated request.
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end;
$$;

grant usage on schema public to anon, authenticated, service_role;
grant usage on schema auth   to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;

-- Supabase's default: new tables in public are reachable by both roles until
-- something says otherwise. The RLS migration is what says otherwise.
alter default privileges in schema public
  grant all on tables to anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- The assertion helper
--
-- Lives here rather than in a test file because the RLS tests call it from
-- INSIDE the restricted roles, which means those roles need reach into this
-- schema. Defining it alongside the roles keeps that grant next to the thing
-- it grants on.
--
-- Deliberately NOT in `public`: the RLS migration revokes anon's access to
-- everything in that schema, and a test helper sitting there would either be
-- caught by the revoke or force an exception to it.
-- ----------------------------------------------------------------------------

create schema if not exists tests;

create or replace function tests.assert(cond boolean, msg text)
returns void language plpgsql as $$
begin
  -- `is not true` rather than `not cond`, so a NULL condition — an assertion
  -- whose subquery matched nothing — fails loudly instead of passing quietly.
  if cond is not true then
    raise exception 'ASSERT FAILED: %', msg;
  end if;
end;
$$;

grant usage on schema tests to anon, authenticated, service_role;
grant execute on function tests.assert(boolean, text) to anon, authenticated, service_role;
