-- ============================================================================
-- 0002 — Sync machinery: server clock, tombstone purge
--
-- THE TWO TIMESTAMPS ARE NOT REDUNDANT. Getting this wrong loses data
-- silently, which is precisely the failure mode docs/02-architecture.md warns
-- about, so it is spelled out here rather than left to a design doc.
--
--   updated_at         The CLIENT's wall clock at the moment of the edit.
--                      The last-write-wins input. It MUST be the client's: an
--                      edit made offline has no server time, and resolving
--                      conflicts on arrival time would make "whoever
--                      reconnected last" win instead of "whoever edited last".
--
--   server_updated_at  The SERVER's clock at the moment the row was written.
--                      The pull cursor, and nothing else.
--
-- Why a client cannot pull on `updated_at`: a device with a slow clock writes
-- a row stamped in the past. Any other device whose cursor has already moved
-- beyond that point will never see it again — no error, no retry, the row just
-- never arrives. `server_updated_at` is monotonic with respect to the server
-- and cannot be moved backwards by a client, so a pull cursor built on it
-- cannot skip a row.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- set_sync_metadata — the trigger every synced table shares
--
-- Responsibilities, in order of how much damage getting them wrong does:
--
--   1. Stamp server_updated_at from the server clock, ALWAYS, ignoring
--      whatever the client sent. A client that could write this field could
--      hide a row from every other device's pull.
--
--   2. Clamp a far-future `updated_at`. A device with a badly-set clock would
--      otherwise win every last-write-wins comparison forever, and each win
--      silently discards the other device's edit. Five minutes is slack for
--      ordinary clock drift; anything beyond it is a broken clock, not a
--      genuinely newer edit. The clamp is deliberately one-sided — a client
--      clock running SLOW only loses its own conflicts, which is recoverable,
--      while a clock running fast poisons every conflict on the account.
--
--   3. Keep created_at immutable. It is server-set on insert and is the only
--      timestamp here a client never has an opinion about.
-- ----------------------------------------------------------------------------
create or replace function public.set_sync_metadata()
returns trigger
language plpgsql
as $$
begin
  new.server_updated_at := now();

  if tg_op = 'INSERT' then
    new.created_at := now();
  else
    new.created_at := old.created_at;
  end if;

  if new.updated_at is null or new.updated_at > now() + interval '5 minutes' then
    new.updated_at := now();
  end if;

  return new;
end;
$$;

comment on function public.set_sync_metadata() is
  'Stamps server_updated_at from the server clock and clamps far-future client '
  'updated_at values. See supabase/migrations/20260815120100_sync.sql.';

-- Attach to every synced table. Listed explicitly rather than looped over
-- information_schema: a table added later must be added here deliberately,
-- and a silent "all tables in public" loop would also catch tables that are
-- not part of the sync set.
do $$
declare
  t text;
begin
  foreach t in array array[
    'exercises',
    'exercise_preferences',
    'template_folders',
    'templates',
    'template_exercises',
    'template_sets',
    'workouts',
    'workout_exercises',
    'workout_sets',
    'program_days',
    'measurement_types',
    'measurement_entries'
  ]
  loop
    execute format(
      'create trigger %I before insert or update on public.%I
         for each row execute function public.set_sync_metadata()',
      t || '_sync_metadata', t
    );
  end loop;
end;
$$;


-- ----------------------------------------------------------------------------
-- purge_tombstones — 90-day tombstone retention
--
-- Tombstones exist so a device that has been offline learns about deletes it
-- never saw. Ninety days is the window in which that is still plausible;
-- beyond it the row is dead weight. A device offline LONGER than the retention
-- window must be reset rather than synced — it can no longer distinguish
-- "deleted while I was away" from "created while I was away", and there is no
-- way to tell those apart from the tombstone table alone.
--
-- Order matters less than it appears: parents are purged first and the
-- foreign keys carry the consequence.
--
--   * CASCADE children (template_sets, workout_sets, ...) are removed with
--     their parent. They were tombstoned at the same time.
--   * SET NULL references are the ones to watch. Purging a deleted template
--     nulls `workouts.template_id` on LIVE workout rows — which is correct,
--     that history must survive its template, and it is exactly why those
--     foreign keys are SET NULL rather than CASCADE. That write fires the sync
--     trigger and bumps server_updated_at, so clients re-pull those workouts
--     and learn the link is gone. It does NOT touch `updated_at`, so it cannot
--     win a conflict against a genuine user edit.
--
-- Not scheduled here. Enabling pg_cron is a project-level action, so the
-- schedule is left to whoever provisions the project; see the commented call
-- at the bottom.
-- ----------------------------------------------------------------------------
create or replace function public.purge_tombstones(retention interval default interval '90 days')
returns table (table_name text, purged bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  t text;
  n bigint;
  cutoff timestamptz := now() - retention;
begin
  -- Parents before children so cascades do the bulk of the work.
  foreach t in array array[
    'workouts',
    'workout_exercises',
    'workout_sets',
    'template_folders',
    'templates',
    'template_exercises',
    'template_sets',
    'program_days',
    'measurement_types',
    'measurement_entries',
    'exercise_preferences',
    'exercises'
  ]
  loop
    execute format(
      'delete from public.%I where deleted_at is not null and deleted_at < $1', t
    ) using cutoff;
    get diagnostics n = row_count;

    table_name := t;
    purged := n;
    return next;
  end loop;
end;
$$;

comment on function public.purge_tombstones(interval) is
  'Hard-deletes rows tombstoned longer than the retention window (default 90 '
  'days). Returns per-table counts. Intended to run daily via pg_cron.';

-- Only the service role runs this; it is never called from a client.
revoke all on function public.purge_tombstones(interval) from public, anon, authenticated;

-- To schedule once pg_cron is enabled on the project:
--
--   create extension if not exists pg_cron;
--   select cron.schedule(
--     'purge-tombstones',
--     '17 4 * * *',
--     $$select public.purge_tombstones()$$
--   );
