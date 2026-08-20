-- ============================================================================
-- restPause is a usable set_type
--
-- The migration is ADD VALUE alone, because a value added that way cannot
-- be used in the same transaction that adds it. This file runs after every
-- migration has committed, so an insert here is the proof the new value
-- exists and is accepted by both live columns (template_sets and
-- workout_sets share public.set_type).
--
-- rest_pause and myoRep must still be rejected. The Phase 0 lesson: a
-- plausible spelling that is silently coerced produces a confident wrong
-- conclusion about what the product can do.
-- ============================================================================

\set ON_ERROR_STOP on

-- User 1111… already exists (01_schema_test). The Push A template that
-- file used was tombstoned and purged, so this builds its own chain.

insert into public.templates (id, user_id, name, sort_order) values
  ('08000000-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111', 'Rest-pause proof', 1);

insert into public.template_exercises
  (id, user_id, template_id, exercise_id, sort_order)
values (
  '08000000-0000-0000-0000-000000000002',
  '11111111-1111-1111-1111-111111111111',
  '08000000-0000-0000-0000-000000000001',
  -- Bench Press (Barbell), same seeded uuid 01_schema_test uses.
  '6aaeeb2d-d324-4999-91fb-ceb5487fd80e',
  0
);

insert into public.template_sets
  (id, user_id, template_exercise_id, sort_order, set_type, reps)
values (
  '08000000-0000-0000-0000-000000000003',
  '11111111-1111-1111-1111-111111111111',
  '08000000-0000-0000-0000-000000000002',
  0,
  'restPause',
  12
);

select tests.assert(
  (select set_type::text from public.template_sets
    where id = '08000000-0000-0000-0000-000000000003') = 'restPause',
  'restPause did not round-trip on template_sets.set_type'
);

select tests.assert(
  exists (
    select 1
      from pg_enum e
      join pg_type t on t.oid = e.enumtypid
     where t.typname = 'set_type'
       and e.enumlabel = 'restPause'
  ),
  'restPause is not a value of public.set_type'
);

do $$
begin
  begin
    insert into public.template_sets
      (id, user_id, template_exercise_id, sort_order, set_type, reps)
    values (
      '08000000-0000-0000-0000-000000000004',
      '11111111-1111-1111-1111-111111111111',
      '08000000-0000-0000-0000-000000000002',
      1,
      'rest_pause',
      8
    );
    raise exception 'ASSERT FAILED: rest_pause was accepted as a set_type';
  exception when invalid_text_representation then null;
  end;
end;
$$;

do $$
begin
  begin
    insert into public.template_sets
      (id, user_id, template_exercise_id, sort_order, set_type, reps)
    values (
      '08000000-0000-0000-0000-000000000005',
      '11111111-1111-1111-1111-111111111111',
      '08000000-0000-0000-0000-000000000002',
      2,
      'myoRep',
      8
    );
    raise exception 'ASSERT FAILED: myoRep was accepted as a set_type';
  exception when invalid_text_representation then null;
  end;
end;
$$;

\echo '08_rest_pause_test: PASS'
