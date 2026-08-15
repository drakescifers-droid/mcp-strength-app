-- ============================================================================
-- RLS tests — the isolation the whole authorization model rests on
--
-- These run as the `authenticated` role with a JWT subject set, i.e. the way a
-- real request arrives. Running them as the table owner would pass
-- unconditionally, because the owner bypasses RLS.
--
-- An untested policy is a guess. The failure mode is not an error message; it
-- is one user reading another user's training history and nobody finding out.
-- ============================================================================

\set ON_ERROR_STOP on

\set user_a '11111111-1111-1111-1111-111111111111'
\set user_b '22222222-2222-2222-2222-222222222222'

-- Fixtures, created as owner before dropping into the restricted role.
insert into public.workouts (id, user_id, name, started_at) values
  ('f0000000-0000-0000-0000-00000000000a', :'user_a', 'A: Leg Day',  now()),
  ('f0000000-0000-0000-0000-00000000000b', :'user_b', 'B: Push Day', now());

insert into public.exercises (id, user_id, name, body_part, category, is_custom) values
  ('f1000000-0000-0000-0000-00000000000a', :'user_a', 'A: Reverse Nordic', 'legs',      'repsOnly', true),
  ('f1000000-0000-0000-0000-00000000000b', :'user_b', 'B: Copenhagen Plank', 'core',    'duration', true);


-- ---------------------------------------------------------------------------
-- As user A
-- ---------------------------------------------------------------------------
set role authenticated;
select set_config('request.jwt.claim.sub', :'user_a', false);

-- Stated as "everything visible belongs to me" rather than as a row count.
-- These tests share a database with 01, so a count would be asserting the
-- fixtures of another file; ownership of every visible row is the property RLS
-- actually promises.
select tests.assert(
  not exists (select 1 from public.workouts where user_id <> :'user_a'::uuid),
  'user A can see a workout belonging to someone else'
);

select tests.assert(
  exists (select 1 from public.workouts
           where id = 'f0000000-0000-0000-0000-00000000000a'),
  'user A cannot see their own workout'
);

select tests.assert(
  not exists (select 1 from public.workouts
               where id = 'f0000000-0000-0000-0000-00000000000b'),
  'user A can read user B''s workout'
);

-- Tombstones stay visible: a soft-deleted row is how a device that was offline
-- learns about the delete. Filtering them in RLS would make deletes invisible
-- to exactly the client that needs them.
select tests.assert(
  exists (select 1 from public.workouts
           where user_id = :'user_a'::uuid and deleted_at is not null),
  'tombstoned rows are hidden from their owner'
);

-- The reference-table rule: the shared library plus your own customs, and
-- nobody else's.
select tests.assert(
  (select count(*) from public.exercises where user_id is null) = 25,
  'user A cannot see the seeded library'
);

select tests.assert(
  exists (select 1 from public.exercises
           where id = 'f1000000-0000-0000-0000-00000000000a'),
  'user A cannot see their own custom exercise'
);

select tests.assert(
  not exists (select 1 from public.exercises
               where id = 'f1000000-0000-0000-0000-00000000000b'),
  'user A can read user B''s custom exercise'
);

-- Writing a row for someone else is rejected.
do $$
begin
  begin
    insert into public.workouts (id, user_id, name, started_at)
    values (gen_random_uuid(), '22222222-2222-2222-2222-222222222222',
            'Planted in B''s history', now());
    raise exception 'ASSERT FAILED: user A inserted a workout owned by user B';
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- Writing a GLOBAL library row is rejected. This is the multi-tenancy leak the
-- exercises_insert policy exists to prevent: a null user_id is visible to
-- every user of the product.
do $$
begin
  begin
    insert into public.exercises (id, user_id, name, body_part, category, is_custom)
    values (gen_random_uuid(), null, 'Planted In The Library', 'other', 'barbell', false);
    raise exception 'ASSERT FAILED: user A inserted a global library exercise';
  exception when insufficient_privilege or check_violation then null;
  end;
end;
$$;

-- Editing a seeded library row is rejected. A user renaming "Bench Press
-- (Barbell)" for everyone would corrupt the shared vocabulary the exercise
-- matcher and every AI-generated plan depend on.
do $$
declare
  affected int;
begin
  update public.exercises set name = 'Bench Press (Mine)'
    where id = '6aaeeb2d-d324-4999-91fb-ceb5487fd80e';
  get diagnostics affected = row_count;
  perform tests.assert(affected = 0, 'user A edited a seeded library exercise');
end;
$$;

-- Deleting another user's row silently affects nothing, rather than erroring —
-- RLS filters the row out of the delete's scope entirely.
do $$
declare
  affected int;
begin
  delete from public.workouts where id = 'f0000000-0000-0000-0000-00000000000b';
  get diagnostics affected = row_count;
  perform tests.assert(affected = 0, 'user A deleted user B''s workout');
end;
$$;

-- Reassigning one of your own rows to another user is rejected by WITH CHECK.
do $$
begin
  begin
    update public.workouts
      set user_id = '22222222-2222-2222-2222-222222222222'
      where id = 'f0000000-0000-0000-0000-00000000000a';
    raise exception 'ASSERT FAILED: user A reassigned their workout to user B';
  exception when insufficient_privilege then null;
  end;
end;
$$;


-- ---------------------------------------------------------------------------
-- As user B — the mirror image, so a policy that accidentally hardcoded one
-- subject would still be caught.
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', :'user_b', false);

select tests.assert(
  not exists (select 1 from public.workouts where user_id <> :'user_b'::uuid)
    and exists (select 1 from public.workouts
                 where id = 'f0000000-0000-0000-0000-00000000000b'),
  'user B does not see exactly their own workouts'
);

select tests.assert(
  exists (select 1 from public.exercises
           where id = 'f1000000-0000-0000-0000-00000000000b')
    and not exists (select 1 from public.exercises
                     where id = 'f1000000-0000-0000-0000-00000000000a'),
  'user B''s view of custom exercises is wrong'
);


-- ---------------------------------------------------------------------------
-- With no session at all
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', '', false);

select tests.assert(
  (select count(*) from public.workouts) = 0,
  'workouts are readable with no JWT subject'
);

reset role;


-- ---------------------------------------------------------------------------
-- As anon — no table access whatsoever
--
-- Nothing in this product is public: no shared workout, no public profile, not
-- even the exercise library. Supabase grants new tables in `public` to anon by
-- default, so this asserts the revoke in the RLS migration actually landed.
-- ---------------------------------------------------------------------------
set role anon;

do $$
begin
  begin
    perform 1 from public.workouts;
    raise exception 'ASSERT FAILED: anon can read workouts';
  exception when insufficient_privilege then null;
  end;
end;
$$;

do $$
begin
  begin
    perform 1 from public.exercises;
    raise exception 'ASSERT FAILED: anon can read the exercise library';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;

\echo '02_rls_test: PASS'
