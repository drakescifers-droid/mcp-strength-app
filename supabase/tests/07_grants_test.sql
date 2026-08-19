-- ============================================================================
-- EVERY synced table is reachable by `authenticated`, and none by `anon`
--
-- This file exists because of a live outage on 2026-08-19. `app_settings` was
-- created by `20260818160000`, three days after `20260815120200_rls.sql` ran:
--
--     grant select, insert, update, delete on all tables in schema public
--       to authenticated;
--
-- **`ON ALL TABLES` IS A ONE-TIME SNAPSHOT.** The new table never got the
-- grant, so the first real sync died with `permission denied for table
-- app_settings` — and because that table is FIRST in the push order, the
-- rejected batch aborted the entire run. No other table was attempted and the
-- pull never happened. The app said "Backup could not finish."
--
-- The suite passed the whole time. `00_shim.sql` used to hand every new table
-- full privileges via `alter default privileges`, which is more permissive than
-- the real project — so the harness papered over exactly the difference that
-- caused the bug. A test environment more permissive than production cannot
-- test authorization. The shim no longer does it, and this file asserts the
-- property directly instead of trusting either the shim or a migration.
--
-- The lesson generalises past grants: `... on all tables` in ANY migration is a
-- snapshot, not a rule. If you want it to hold for tables added later, you need
-- `alter default privileges` as well — and 0003 did exactly that for the anon
-- REVOKE while forgetting the mirror-image GRANT.
-- ============================================================================

\set ON_ERROR_STOP on

-- Every table the sync engine touches, in SyncEntity order. Listed explicitly
-- for the same reason the trigger lists are: a table added later must be added
-- here deliberately, and a loop over information_schema would silently accept
-- a new table nobody had thought about.
create temporary table expected_synced_tables (name text primary key);
insert into expected_synced_tables (name) values
  ('app_settings'),
  ('exercises'),
  ('exercise_preferences'),
  ('template_folders'),
  ('templates'),
  ('template_exercises'),
  ('template_sets'),
  ('program_days'),
  ('workouts'),
  ('workout_exercises'),
  ('workout_sets'),
  ('measurement_types'),
  ('measurement_entries');

-- ----------------------------------------------------------------------------
-- The list itself must be complete. A synced table missing from it would make
-- every assertion below pass while proving nothing about that table.
-- ----------------------------------------------------------------------------

select tests.assert(
  not exists (
    select 1
      from information_schema.tables t
     where t.table_schema = 'public'
       and t.table_type = 'BASE TABLE'
       and t.table_name not in (select name from expected_synced_tables)
  ),
  'There is a table in `public` that this test does not know about. Every table '
  'here is synced; add it to expected_synced_tables (and to BOTH trigger lists) '
  'or explain why it is exempt.'
);

-- ----------------------------------------------------------------------------
-- `authenticated` must hold all four verbs on every one of them.
--
-- Checked per VERB rather than "has some privilege", because a table with
-- SELECT but no INSERT fails only on the first push — which is the worst time
-- to find out, and is a state a partial grant can genuinely produce.
-- ----------------------------------------------------------------------------

do $$
declare
  t text;
  v text;
begin
  for t in select name from expected_synced_tables loop
    foreach v in array array['SELECT', 'INSERT', 'UPDATE', 'DELETE'] loop
      if not has_table_privilege('authenticated', format('public.%I', t), v) then
        raise exception
          'authenticated lacks % on public.% — PostgREST answers 403 '
          '"permission denied for table %", and if that table is early in the '
          'push order the whole sync run aborts, pull included. `grant ... on '
          'all tables` is a ONE-TIME SNAPSHOT; a table created by a later '
          'migration needs its own grant, or `alter default privileges`.',
          v, t, t;
      end if;
    end loop;
  end loop;
end;
$$;

-- ----------------------------------------------------------------------------
-- `anon` must hold NOTHING on any of them.
--
-- Nothing in this app is public — no shared workout, no public profile, no
-- unauthenticated read of the exercise library. This is the half 0003 already
-- made durable with `alter default privileges ... revoke`, and it is asserted
-- here so the durability is proven rather than assumed.
-- ----------------------------------------------------------------------------

do $$
declare
  t text;
  v text;
begin
  for t in select name from expected_synced_tables loop
    foreach v in array array['SELECT', 'INSERT', 'UPDATE', 'DELETE'] loop
      if has_table_privilege('anon', format('public.%I', t), v) then
        raise exception
          'anon holds % on public.% — nothing in this app is public, and a '
          'grant without a session is the leak the RLS migration exists to '
          'prevent.',
          v, t;
      end if;
    end loop;
  end loop;
end;
$$;

-- ----------------------------------------------------------------------------
-- The DURABLE half: a table created from here on must inherit both rules.
--
-- This is the assertion that actually prevents a recurrence. The two above
-- describe today; this one describes tomorrow, which is where the bug lived.
-- ----------------------------------------------------------------------------

create table public.grants_canary_tmp (id uuid primary key);

do $$
declare
  v text;
begin
  foreach v in array array['SELECT', 'INSERT', 'UPDATE', 'DELETE'] loop
    if not has_table_privilege('authenticated', 'public.grants_canary_tmp', v) then
      raise exception
        'A NEWLY CREATED table does not grant % to authenticated. `alter default '
        'privileges in schema public grant ... on tables to authenticated` is '
        'missing, so the next table somebody adds will be unreachable and the '
        'first sync touching it will abort the whole run — exactly what '
        'app_settings did on 2026-08-19.',
        v;
    end if;
    if has_table_privilege('anon', 'public.grants_canary_tmp', v) then
      raise exception 'A NEWLY CREATED table grants % to anon.', v;
    end if;
  end loop;
end;
$$;

drop table public.grants_canary_tmp;
