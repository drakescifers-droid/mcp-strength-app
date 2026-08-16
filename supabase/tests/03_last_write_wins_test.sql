-- ============================================================================
-- Last-write-wins tests — the server refuses a stale upsert
--
-- Run as the table owner, so RLS is not in the way. The property under test
-- is that an UPDATE whose updated_at is older than the row it would replace
-- does not happen — not the data, and not a bump of the pull cursor.
--
-- Two tables, not one: a DO block that compiled but failed to attach would
-- pass every assertion against a single lucky table.
-- ============================================================================

\set ON_ERROR_STOP on

-- Fixtures -------------------------------------------------------------------
--
-- Users 1111… / 2222… already exist (01_schema_test). Explicit timestamps so
-- "older" / "newer" / "equal" do not depend on now() inside one transaction
-- (now() is transaction-start time, so two now() calls compare equal).

insert into public.workouts (id, user_id, name, started_at, updated_at)
values ('03000000-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111',
        'Current name',
        '2026-06-01 12:00:00+00',
        '2026-06-01 12:00:00+00');

insert into public.templates (id, user_id, name, sort_order, updated_at)
values ('03000000-0000-0000-0000-000000000002',
        '11111111-1111-1111-1111-111111111111',
        'Push A',
        0,
        '2026-06-01 12:00:00+00');


-- workouts: older write is refused ------------------------------------------

do $$
declare
  original_server timestamptz;
begin
  select server_updated_at into original_server
    from public.workouts
    where id = '03000000-0000-0000-0000-000000000001';

  update public.workouts
    set name = 'Stale overwrite',
        updated_at = '2026-06-01 11:00:00+00'
    where id = '03000000-0000-0000-0000-000000000001';

  perform tests.assert(
    (select name from public.workouts
      where id = '03000000-0000-0000-0000-000000000001') = 'Current name',
    'an older updated_at overwrote the workout'
  );

  perform tests.assert(
    (select updated_at from public.workouts
      where id = '03000000-0000-0000-0000-000000000001')
      = '2026-06-01 12:00:00+00',
    'a rejected write moved updated_at'
  );

  -- THE ONE THAT MATTERS: a rejected write must not move the pull cursor.
  -- If it does, the row re-enters every device's pull window for a change
  -- that did not happen, and the stale client retrying makes that permanent.
  perform tests.assert(
    (select server_updated_at from public.workouts
      where id = '03000000-0000-0000-0000-000000000001') = original_server,
    'a rejected write bumped server_updated_at'
  );
end;
$$;


-- workouts: newer write is applied ------------------------------------------

update public.workouts
  set name = 'Won the conflict',
      updated_at = '2026-06-01 14:00:00+00'
  where id = '03000000-0000-0000-0000-000000000001';

select tests.assert(
  (select name from public.workouts
    where id = '03000000-0000-0000-0000-000000000001') = 'Won the conflict',
  'a newer updated_at was not applied'
);

select tests.assert(
  (select updated_at from public.workouts
    where id = '03000000-0000-0000-0000-000000000001')
    = '2026-06-01 14:00:00+00',
  'a newer write left updated_at on the previous value'
);


-- workouts: tombstone with a newer updated_at still applies -----------------
--
-- A soft delete is an ordinary UPDATE. If this fails, deleted rows stay
-- alive on every other device forever.

update public.workouts
  set deleted_at = '2026-06-01 15:00:00+00',
      updated_at = '2026-06-01 15:00:00+00'
  where id = '03000000-0000-0000-0000-000000000001';

select tests.assert(
  (select deleted_at from public.workouts
    where id = '03000000-0000-0000-0000-000000000001')
    = '2026-06-01 15:00:00+00',
  'a tombstone with a newer updated_at was refused'
);


-- workouts: a stale tombstone does not kill a newer live row ----------------
--
-- The mirror of the last check: the guard looks at updated_at, not at
-- whether deleted_at is being set. A delete carrying an older clock is
-- just another stale write.

insert into public.workouts (id, user_id, name, started_at, updated_at)
values ('03000000-0000-0000-0000-000000000003',
        '11111111-1111-1111-1111-111111111111',
        'Still live',
        '2026-06-01 12:00:00+00',
        '2026-06-01 14:00:00+00');

update public.workouts
  set deleted_at = '2026-06-01 13:00:00+00',
      updated_at = '2026-06-01 13:00:00+00'
  where id = '03000000-0000-0000-0000-000000000003';

select tests.assert(
  (select deleted_at from public.workouts
    where id = '03000000-0000-0000-0000-000000000003') is null,
  'a stale tombstone deleted a newer live row'
);


-- workouts: equal updated_at is allowed through -----------------------------
--
-- Ties pass because housekeeping writes (purge_tombstones' ON DELETE SET
-- NULL, anything else that must bump the cursor without outranking a user
-- edit) leave updated_at alone. Suppressing equals would swallow those.

do $$
declare
  original_server timestamptz;
begin
  select server_updated_at into original_server
    from public.workouts
    where id = '03000000-0000-0000-0000-000000000003';

  update public.workouts
    set name = 'Tie arrives second',
        updated_at = '2026-06-01 14:00:00+00'
    where id = '03000000-0000-0000-0000-000000000003';

  perform tests.assert(
    (select name from public.workouts
      where id = '03000000-0000-0000-0000-000000000003') = 'Tie arrives second',
    'an equal updated_at was refused'
  );

  perform tests.assert(
    (select server_updated_at from public.workouts
      where id = '03000000-0000-0000-0000-000000000003') > original_server,
    'an allowed tie did not bump server_updated_at'
  );
end;
$$;


-- Clamp then guard: a far-future clock cannot defeat last-write-wins --------
--
-- set_sync_metadata rewrites updated_at more than five minutes ahead to
-- now(). The guard must see that clamped value. If it compared first, the
-- far-future timestamp would always win, the write would land, and the
-- clamp would then store now() — which is older than the row it overwrote.

insert into public.workouts (id, user_id, name, started_at, updated_at)
values ('03000000-0000-0000-0000-000000000004',
        '11111111-1111-1111-1111-111111111111',
        'Holds the slack-window stamp',
        now(),
        now() + interval '2 minutes');

update public.workouts
  set name = 'Fast clock, stale data',
      updated_at = now() + interval '30 days'
  where id = '03000000-0000-0000-0000-000000000004';

select tests.assert(
  (select name from public.workouts
    where id = '03000000-0000-0000-0000-000000000004')
    = 'Holds the slack-window stamp',
  'a far-future updated_at overwrote a row that is still ahead of now()'
);

select tests.assert(
  (select updated_at from public.workouts
    where id = '03000000-0000-0000-0000-000000000004')
    > now() + interval '1 minute',
  'the clamp+guard pair rewrote a slack-window updated_at backwards'
);


-- templates: the same attachment, on a second table -------------------------

do $$
declare
  original_server timestamptz;
begin
  select server_updated_at into original_server
    from public.templates
    where id = '03000000-0000-0000-0000-000000000002';

  update public.templates
    set name = 'Stale overwrite',
        updated_at = '2026-06-01 11:00:00+00'
    where id = '03000000-0000-0000-0000-000000000002';

  perform tests.assert(
    (select name from public.templates
      where id = '03000000-0000-0000-0000-000000000002') = 'Push A',
    'an older updated_at overwrote the template'
  );

  perform tests.assert(
    (select server_updated_at from public.templates
      where id = '03000000-0000-0000-0000-000000000002') = original_server,
    'a rejected template write bumped server_updated_at'
  );
end;
$$;

update public.templates
  set name = 'Push A revised',
      updated_at = '2026-06-01 14:00:00+00'
  where id = '03000000-0000-0000-0000-000000000002';

select tests.assert(
  (select name from public.templates
    where id = '03000000-0000-0000-0000-000000000002') = 'Push A revised',
  'a newer updated_at was not applied to the template'
);

update public.templates
  set deleted_at = '2026-06-01 15:00:00+00',
      updated_at = '2026-06-01 15:00:00+00'
  where id = '03000000-0000-0000-0000-000000000002';

select tests.assert(
  (select deleted_at from public.templates
    where id = '03000000-0000-0000-0000-000000000002')
    = '2026-06-01 15:00:00+00',
  'a tombstone with a newer updated_at was refused on templates'
);

\echo '03_last_write_wins_test: PASS'
