-- ============================================================================
-- hammerStrength is a usable exercise_category
--
-- The migration is ADD VALUE alone, because a value added that way cannot
-- be used in the same transaction that adds it. This file runs after every
-- migration has committed, so an insert here is the proof the new value
-- exists and is accepted by the live column.
--
-- No seeded row is retagged. The library refresh is a separate change;
-- this only needs the category to exist so an exercise can be associated
-- with it.
-- ============================================================================

\set ON_ERROR_STOP on

-- User 1111… already exists (01_schema_test). Custom + owned satisfies
-- exercises_custom_iff_owned.

insert into public.exercises (id, user_id, name, body_part, category, is_custom)
values (
  '04000000-0000-0000-0000-000000000001',
  '11111111-1111-1111-1111-111111111111',
  'HS Chest Press',
  'chest',
  'hammerStrength',
  true
);

select tests.assert(
  (select category::text from public.exercises
    where id = '04000000-0000-0000-0000-000000000001') = 'hammerStrength',
  'hammerStrength did not round-trip on exercises.category'
);

select tests.assert(
  exists (
    select 1
      from pg_enum e
      join pg_type t on t.oid = e.enumtypid
     where t.typname = 'exercise_category'
       and e.enumlabel = 'hammerStrength'
  ),
  'hammerStrength is not a value of public.exercise_category'
);

\echo '04_hammer_strength_test: PASS'
