-- ============================================================================
-- Schema tests — constraints, the sync trigger, and the purge's SET NULL rule
--
-- Run as the table owner, so RLS is not in the way here. Isolation is the next
-- file's job; this one is about whether the schema itself keeps its promises.
--
-- Every check that matters in this file is one that would otherwise be
-- discovered by losing data.
-- ============================================================================

\set ON_ERROR_STOP on

-- `tests.assert` comes from 00_shim.sql, which is also where the roles that
-- need to reach it are created.

-- Fixtures -------------------------------------------------------------------

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@example.test'),
  ('22222222-2222-2222-2222-222222222222', 'b@example.test');

insert into public.template_folders (id, user_id, name, sort_order) values
  ('aaaa0000-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111', 'Q2 2026', 0);

insert into public.templates (id, user_id, name, folder_id, sort_order) values
  ('bbbb0000-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111', 'Push A',
   'aaaa0000-0000-0000-0000-000000000001', 0);

insert into public.template_exercises (id, user_id, template_id, exercise_id, sort_order) values
  ('cccc0000-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111',
   'bbbb0000-0000-0000-0000-000000000001',
   -- Bench Press (Barbell), straight from the seeded library.
   '6aaeeb2d-d324-4999-91fb-ceb5487fd80e', 0);


-- The seeded library is present and global ------------------------------------

-- 301 LIVE global exercises after the 2026-08-20 rebuild
-- (20260820120000_library_rebuild.sql), plus the 10 rows that rebuild retired
-- and TOMBSTONED rather than deleted. 311 rows total, 301 of them live.
select tests.assert(
  (select count(*) from public.exercises
    where user_id is null and deleted_at is null) = 301,
  'expected 301 live global seeded exercises'
);

-- The retired rows must still EXIST, tombstoned. A hard delete cannot reach a
-- device that was offline when it happened, so the row would come back on that
-- device's next pull (AGENTS.md rule 1). Deleting them for tidiness is exactly
-- the mistake this asserts against.
select tests.assert(
  (select count(*) from public.exercises
    where user_id is null and deleted_at is not null) = 10,
  'expected the 10 retired library exercises to be tombstoned, not deleted'
);

-- A retired id specifically: "Lat Pulldown", dropped because it named no
-- equipment while Cable and Machine versions both exist.
select tests.assert(
  (select deleted_at is not null from public.exercises
    where id = '07fc8389-e0d3-45d3-af79-4dd97d777bd2'),
  'the retired generic Lat Pulldown should be tombstoned'
);

select tests.assert(
  (select count(*) from public.measurement_types where user_id is null) = 18,
  'expected 18 global seeded measurement types'
);

-- The permanent-id contract: a known seeded uuid still resolves to its
-- exercise. If this ever fails, every user's history for that movement has
-- detached.
select tests.assert(
  (select name from public.exercises
    where id = '8de7cc2a-06ac-40fd-b99c-e5461f67a107') = 'Chest Fly (Machine)',
  'seeded uuid no longer maps to Chest Fly (Machine)'
);

-- Aliases are deliberately non-unique: a collision produces AMBIGUITY, which
-- the matcher handles by returning candidates and writing nothing.
--
-- **This asserts the SCHEMA permits it, using rows created here — it no longer
-- asserts that the shipped library happens to contain a shared alias.** The old
-- version keyed on "row" being an alias of three seeded exercises; the
-- 2026-08-20 rebuild dropped the bare "row" alias (with ~15 "* Row *" exercises
-- now in the library, aliasing three of them was picking arbitrary winners, and
-- spelling similarity already surfaces them all). That made a test of the DESIGN
-- fail for a change to the DATA — so it now tests the design directly and cannot
-- be broken by an ordinary library edit again.
insert into public.exercises (id, user_id, name, aliases, body_part, category, is_custom) values
  ('eeee0000-0000-0000-0000-00000000000a', null, 'Alias Collision A',
   array['shared alias']::text[], 'back', 'barbell', false),
  ('eeee0000-0000-0000-0000-00000000000b', null, 'Alias Collision B',
   array['shared alias']::text[], 'back', 'dumbbell', false);

select tests.assert(
  (select count(*) from public.exercises where 'shared alias' = any (aliases)) = 2,
  'the schema must allow one alias on more than one exercise'
);

delete from public.exercises
 where id in ('eeee0000-0000-0000-0000-00000000000a',
              'eeee0000-0000-0000-0000-00000000000b');


-- The sync trigger -------------------------------------------------------------

-- A client cannot forge server_updated_at. If it could, it could hide a row
-- from every other device's pull cursor.
insert into public.workouts (id, user_id, name, started_at, server_updated_at)
values ('dddd0000-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111', 'Afternoon Workout',
        now(), '1999-01-01');

select tests.assert(
  (select server_updated_at from public.workouts
    where id = 'dddd0000-0000-0000-0000-000000000001') > now() - interval '1 minute',
  'server_updated_at accepted a client-supplied value'
);

-- A far-future client clock is clamped. Left unclamped, that device wins every
-- last-write-wins comparison on the account forever, and each win silently
-- discards the other device's edit.
insert into public.workouts (id, user_id, name, started_at, updated_at)
values ('dddd0000-0000-0000-0000-000000000002',
        '11111111-1111-1111-1111-111111111111', 'Skewed Clock',
        now(), now() + interval '30 days');

select tests.assert(
  (select updated_at from public.workouts
    where id = 'dddd0000-0000-0000-0000-000000000002') < now() + interval '6 minutes',
  'a far-future client updated_at was not clamped'
);

-- Ordinary drift inside the slack window is left alone — the clamp must not
-- rewrite legitimate timestamps.
insert into public.workouts (id, user_id, name, started_at, updated_at)
values ('dddd0000-0000-0000-0000-000000000003',
        '11111111-1111-1111-1111-111111111111', 'Mild Drift',
        now(), now() + interval '2 minutes');

select tests.assert(
  (select updated_at from public.workouts
    where id = 'dddd0000-0000-0000-0000-000000000003') > now() + interval '1 minute',
  'the clamp rewrote a timestamp inside the tolerated drift window'
);

-- created_at is immutable.
do $$
declare
  original timestamptz;
begin
  select created_at into original from public.workouts
    where id = 'dddd0000-0000-0000-0000-000000000001';

  update public.workouts set created_at = '1999-01-01', name = 'Renamed'
    where id = 'dddd0000-0000-0000-0000-000000000001';

  perform tests.assert(
    (select created_at from public.workouts
      where id = 'dddd0000-0000-0000-0000-000000000001') = original,
    'created_at was rewritten by an update'
  );
end;
$$;


-- Set constraints --------------------------------------------------------------

-- Assisted bodyweight carries NEGATIVE weight (the assistance). A schema that
-- rejected it would reject an entire exercise category.
insert into public.template_sets
  (id, user_id, template_exercise_id, sort_order, weight, reps)
values ('eeee0000-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111',
        'cccc0000-0000-0000-0000-000000000001', 0, -40, 8);

-- A rep range is both ends or neither.
do $$
begin
  begin
    insert into public.template_sets
      (id, user_id, template_exercise_id, sort_order, rep_range_start)
    values (gen_random_uuid(), '11111111-1111-1111-1111-111111111111',
            'cccc0000-0000-0000-0000-000000000001', 1, 6);
    raise exception 'ASSERT FAILED: a half-open rep range was accepted';
  exception when check_violation then null;
  end;
end;
$$;

-- A set is a fixed target OR a range, never both.
do $$
begin
  begin
    insert into public.template_sets
      (id, user_id, template_exercise_id, sort_order, reps, rep_range_start, rep_range_end)
    values (gen_random_uuid(), '11111111-1111-1111-1111-111111111111',
            'cccc0000-0000-0000-0000-000000000001', 2, 5, 6, 8);
    raise exception 'ASSERT FAILED: reps and a rep range were accepted together';
  exception when check_violation then null;
  end;
end;
$$;

-- RPE is 6-10 in half steps. This is the constraint that makes an
-- unrecognised value a loud error instead of a silent coercion.
do $$
begin
  begin
    insert into public.template_sets
      (id, user_id, template_exercise_id, sort_order, reps, rpe)
    values (gen_random_uuid(), '11111111-1111-1111-1111-111111111111',
            'cccc0000-0000-0000-0000-000000000001', 3, 5, 8.3);
    raise exception 'ASSERT FAILED: an off-step RPE was accepted';
  exception when check_violation then null;
  end;
end;
$$;

-- ... and every legal half step is accepted.
insert into public.template_sets
  (id, user_id, template_exercise_id, sort_order, reps, rpe)
select gen_random_uuid(), '11111111-1111-1111-1111-111111111111',
       'cccc0000-0000-0000-0000-000000000001', 10 + row_number() over (), 5, v
from unnest(array[6, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10]::double precision[]) as v;

-- An unknown enum value is rejected outright rather than coerced to a
-- neighbour. This is the Phase 0 lesson encoded: the spike quietly turned an
-- unrecognised set_type into 'normal' and reported success.
do $$
begin
  begin
    insert into public.template_sets
      (id, user_id, template_exercise_id, sort_order, set_type, reps)
    values (gen_random_uuid(), '11111111-1111-1111-1111-111111111111',
            'cccc0000-0000-0000-0000-000000000001', 30, 'myotatic', 5);
    raise exception 'ASSERT FAILED: an unknown set_type was accepted';
  exception when invalid_text_representation then null;
  end;
end;
$$;

-- A global exercise cannot be user-owned, and a custom one cannot be global.
do $$
begin
  begin
    insert into public.exercises (id, user_id, name, body_part, category, is_custom)
    values (gen_random_uuid(), '11111111-1111-1111-1111-111111111111',
            'Ghost Raise', 'shoulders', 'dumbbell', false);
    raise exception 'ASSERT FAILED: a user-owned non-custom exercise was accepted';
  exception when check_violation then null;
  end;
end;
$$;


-- Delete rules: the ones that decide whether history survives ------------------

-- Tombstone a template, then purge past the retention window.
update public.templates
  set deleted_at = now() - interval '100 days'
  where id = 'bbbb0000-0000-0000-0000-000000000001';

insert into public.workouts (id, user_id, name, template_id, started_at)
values ('dddd0000-0000-0000-0000-000000000009',
        '11111111-1111-1111-1111-111111111111', 'Push A',
        'bbbb0000-0000-0000-0000-000000000001', now());

select public.purge_tombstones();

-- THE ONE THAT MATTERS: purging a deleted template must not delete the
-- workouts performed from it. The workout survives, keeps the name it copied
-- at start, and simply loses the link.
select tests.assert(
  exists (select 1 from public.workouts
           where id = 'dddd0000-0000-0000-0000-000000000009'),
  'purging a template destroyed the workout performed from it'
);

select tests.assert(
  (select template_id from public.workouts
    where id = 'dddd0000-0000-0000-0000-000000000009') is null,
  'the purged template left a dangling template_id'
);

select tests.assert(
  (select name from public.workouts
    where id = 'dddd0000-0000-0000-0000-000000000009') = 'Push A',
  'the workout lost the name it copied from its template'
);

-- The nulling write is a server write, so it must move the pull cursor
-- (clients need to learn the link is gone) WITHOUT moving updated_at, which
-- would let a housekeeping job outrank a real user edit.
select tests.assert(
  (select server_updated_at > updated_at from public.workouts
    where id = 'dddd0000-0000-0000-0000-000000000009'),
  'the purge did not move the pull cursor, or moved updated_at with it'
);

-- Children of the purged template went with it.
select tests.assert(
  not exists (select 1 from public.template_exercises
               where id = 'cccc0000-0000-0000-0000-000000000001'),
  'template_exercises survived the purge of their template'
);

select tests.assert(
  not exists (select 1 from public.template_sets
               where id = 'eeee0000-0000-0000-0000-000000000001'),
  'template_sets survived the purge of their template'
);

-- A live tombstone inside the window is NOT purged — that is the whole point
-- of retention.
update public.workouts set deleted_at = now() - interval '10 days'
  where id = 'dddd0000-0000-0000-0000-000000000003';
select public.purge_tombstones();
select tests.assert(
  exists (select 1 from public.workouts
           where id = 'dddd0000-0000-0000-0000-000000000003'),
  'a tombstone inside the retention window was purged'
);

\echo '01_schema_test: PASS'
