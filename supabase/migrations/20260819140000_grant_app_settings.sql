-- ----------------------------------------------------------------------------
-- Grant `authenticated` on app_settings — and stop this recurring
--
-- ## What broke
--
-- The first real sync after turning on settings backup failed with a single
-- request:
--
--     POST /rest/v1/app_settings → 403
--
-- and NOTHING else. `app_settings` is first in `SyncEntity.allCases`, so the
-- rejected batch aborted the whole run: no other table was attempted and the
-- pull never happened. The app reported "Backup could not finish."
--
-- ## Why
--
-- `20260815120200_rls.sql` says:
--
--     grant select, insert, update, delete on all tables in schema public
--       to authenticated;
--
-- **`ON ALL TABLES` IS A ONE-TIME SNAPSHOT.** It grants on the tables that
-- exist at the moment it runs, and has no effect on tables created later.
-- `app_settings` was created three days afterwards by `20260818160000`, so
-- `authenticated` could never reach it. RLS was correct and irrelevant — the
-- role could not touch the table at all.
--
-- The same file already understood this problem and solved HALF of it:
--
--     -- Applies the same rule to tables added by later migrations, so a new
--     -- table does not arrive anon-readable by default.
--     alter default privileges in schema public revoke all on tables from anon;
--
-- The `anon` revocation was made durable for future tables. **The mirror-image
-- grant to `authenticated` was not**, so every future table arrives correctly
-- locked down and also unreachable. This migration adds the missing half.
--
-- ## Why the test suite passed anyway — the part worth keeping
--
-- `supabase/tests/00_shim.sql` stands up a throwaway container and does:
--
--     alter default privileges in schema public
--       grant all on tables to anon, authenticated, service_role;
--
-- so in the TEST environment every new table is granted automatically. The
-- suite could not have caught this, because the harness papers over precisely
-- the difference that causes it. That is the same shape as
-- `docs/04-status.md`'s note that tests build their Postgres from the local
-- migration files, so the schema is right there *by construction* — a check
-- whose environment differs from production in exactly the way the bug does.
-- The shim is fixed in the same change as this migration, and
-- `07_grants_test.sql` now asserts the property directly.
-- ----------------------------------------------------------------------------

-- 1. The table that is currently unreachable.
--
-- Written as `on all tables` rather than naming app_settings, so it also
-- repairs any other table added between 0003 and now. Re-granting a privilege
-- that is already held is a no-op.
grant select, insert, update, delete on all tables in schema public to authenticated;

-- 2. The durable half that was missing. From here on a new table in `public`
--    arrives reachable by `authenticated` without anyone remembering.
--
-- Deliberately the same four verbs as the original grant, not `all`: nothing in
-- this app truncates or references its way around RLS, and a narrower default
-- is the one that stays correct when somebody adds a table without thinking
-- about it — which is exactly the case this exists for.
alter default privileges in schema public
  grant select, insert, update, delete on tables to authenticated;

-- 3. Unchanged and repeated for completeness: anon reaches nothing, now or
--    later. Re-stating it here means this file is a complete description of
--    the privilege model rather than a diff against 0003.
revoke all on all tables in schema public from anon;
alter default privileges in schema public revoke all on tables from anon;
