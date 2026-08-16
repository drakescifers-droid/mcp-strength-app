-- ============================================================================
-- 0007 — Last-write-wins guard
--
-- THE SERVER HAD NO OPINION ABOUT WHICH EDIT WINS. `set_sync_metadata`
-- stamps `server_updated_at` and clamps a far-future `updated_at`, and that
-- was the entire extent of the server's relationship with time. An upsert
-- therefore overwrote unconditionally: a device holding a stale edit could
-- destroy a newer edit made on another device, silently, and in direct
-- contradiction of docs/06-sync.md § Conflicts ("the newer edit wins").
--
-- The client-side resolver is the other half of this contract and is not
-- consulted on push — the arriving row is just an upsert. So the server has
-- to refuse a write whose `updated_at` is older than the row it would
-- replace. Without that refusal the conflict table in `06` is a comment.
--
-- Responsibilities, in order of how much damage getting them wrong does:
--
--   1. A suppressed write must NOT bump `server_updated_at`. That column is
--      the pull cursor for every device. If a rejected push still stamps it,
--      the row re-enters every other device's pull window for a change that
--      did not happen; the stale client retries; the cursor moves again;
--      sync looks extremely busy and never settles. Returning OLD from this
--      trigger still performs an UPDATE (and, if this trigger fired first,
--      would hand OLD to `set_sync_metadata`, which stamps `now()` onto it).
--      Returning NULL from a BEFORE UPDATE trigger cancels the row write
--      entirely, so the cursor cannot move. That is the whole reason this
--      is a separate trigger that returns NULL rather than a filter inside
--      `set_sync_metadata`.
--
--   2. Do not block tombstones. A soft delete is an ordinary UPDATE that
--      sets `deleted_at` and carries a newer `updated_at`. It must pass
--      like any other newer edit. A guard that special-cased `deleted_at`,
--      or that compared the wrong timestamp, would leave deleted rows alive
--      on every other device forever — a worse bug than the one this
--      migration fixes. The function looks at `updated_at` and nothing else.
--
--   3. Ties (`new.updated_at = old.updated_at`) are allowed through.
--      Housekeeping writes — the ON DELETE SET NULL that
--      `purge_tombstones` fires on live workouts, and any other server
--      write that must move the pull cursor without outranking a user edit
--      — deliberately leave `updated_at` alone (see 0002). Suppressing
--      equals would swallow those writes: the link would not null, the
--      cursor would not move, and a device that was offline would never
--      learn the template was gone. A genuine same-microsecond edit from
--      two devices is vanishingly rare; last arriver wins, which costs a
--      cursor bump and a re-pull, not a dropped row.
--
-- Trigger order is load-bearing. `set_sync_metadata` rewrites a far-future
-- `updated_at` to `now()`; this guard must see the clamped value, not the
-- client's. If it ran first, a broken clock would always compare as newer,
-- pass the guard, then get rewritten to `now()` — which can be older than
-- the row it just overwrote. The trigger is named `_sync_reject_stale` so
-- it sorts after `_sync_metadata` (same timing, same level, alphabetical).
-- Do not rename it to something that sorts earlier.
-- ============================================================================

create or replace function public.reject_stale_update()
returns trigger
language plpgsql
as $$
begin
  -- Strictly older loses. Equal is a tie and is allowed; see the header.
  if new.updated_at < old.updated_at then
    return null;
  end if;

  return new;
end;
$$;

comment on function public.reject_stale_update() is
  'BEFORE UPDATE: cancels a write whose updated_at is older than the row '
  'it would replace, so a stale client cannot destroy a newer edit. Returns '
  'NULL (not OLD) so a rejected write cannot bump server_updated_at. '
  'See supabase/migrations/20260816140000_last_write_wins.sql.';


-- Attach to every synced table. Listed explicitly rather than looped over
-- information_schema: a table added later must be added here deliberately,
-- and a silent "all tables in public" loop would also catch tables that are
-- not part of the sync set. Same list, same reason, as 0002.
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
    -- `_sync_reject_stale` sorts after `_sync_metadata`. That is not
    -- decorative; the guard has to see the far-future clamp.
    execute format(
      'create trigger %I before update on public.%I
         for each row execute function public.reject_stale_update()',
      t || '_sync_reject_stale', t
    );
  end loop;
end;
$$;
