-- ============================================================================
-- Canonical kilograms — the columns that carry a mass
--
-- The conversion itself (migration 0009) cannot be exercised here: it runs as
-- part of the migration pass, against a database that this harness has just
-- created empty, so by the time a test file runs there is nothing left for it
-- to have converted. Asserting on its arithmetic would mean re-running it,
-- which is precisely the double-conversion this project is most afraid of.
--
-- So this tests the thing that WILL go wrong later instead: a new column that
-- holds a weight, added by somebody who did not think about units.
--
-- `workouts.total_volume` is why. It is a `weight × reps` total, it is stored,
-- it is synced, it is what the history list displays — and nothing in its name
-- says "weight". It was nearly missed by the conversion for exactly that
-- reason. The next column like it will be missed the same way unless adding
-- one has to fail this file first.
--
-- The list below is therefore a DECISION, not a description. Adding a column
-- to it means "I have decided this is (or is not) a mass, and if it is, it is
-- stored in kilograms and every reader converts it."
-- ============================================================================

\set ON_ERROR_STOP on

-- Every double precision column on the synced tables, minus the ones already
-- classified. Anything left over is a column nobody has ruled on.
select tests.assert(
  not exists (
    select 1
      from information_schema.columns c
     where c.table_schema = 'public'
       and c.data_type = 'double precision'
       and c.table_name in (
             'workouts', 'workout_exercises', 'workout_sets',
             'templates', 'template_exercises', 'template_sets',
             'exercises', 'exercise_preferences',
             'measurement_types', 'measurement_entries'
           )
       -- Masses, stored in KILOGRAMS and converted by every reader.
       and (c.table_name, c.column_name) not in (
             ('workout_sets',  'weight'),
             ('template_sets', 'weight'),
             ('workouts',      'total_volume')
           )
       -- Not masses, and each for its own reason:
       --   rpe       a 1-10 scale
       --   distance  a length, carried with its own unit setting
       --   value     a body measurement, which carries a unit string per row
       and (c.table_name, c.column_name) not in (
             ('workout_sets',       'rpe'),
             ('template_sets',      'rpe'),
             ('workout_sets',       'distance'),
             ('template_sets',      'distance'),
             ('measurement_entries', 'value')
           )
  ),
  'An unclassified double precision column exists on a synced table. '
  'If it holds a mass it must be stored in KILOGRAMS and converted by every '
  'reader (see migration 0009); either way, add it to 05_weight_units_test.sql.'
);

-- The three mass columns are documented as kilograms. A comment is the only
-- thing a person reading the schema in a SQL client will see, and "double
-- precision" tells them nothing about what the number means.
select tests.assert(
  (select col_description('public.workout_sets'::regclass, c.ordinal_position::int)
     from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = 'workout_sets'
      and c.column_name = 'weight') like '%KILOGRAMS%',
  'workout_sets.weight is not documented as kilograms'
);

select tests.assert(
  (select col_description('public.template_sets'::regclass, c.ordinal_position::int)
     from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = 'template_sets'
      and c.column_name = 'weight') like '%KILOGRAMS%',
  'template_sets.weight is not documented as kilograms'
);

select tests.assert(
  (select col_description('public.workouts'::regclass, c.ordinal_position::int)
     from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = 'workouts'
      and c.column_name = 'total_volume') like '%KILOGRAMS%',
  'workouts.total_volume is not documented as kilograms'
);

-- Negative weights stay legal. Assisted bodyweight stores ASSISTANCE as a
-- negative load (docs/01-data-model.md § ExerciseCategory), and multiplying by
-- a positive constant keeps it negative. Asserted against the CONSTRAINTS
-- rather than by inserting a row, because the thing that would break this is
-- somebody adding a `weight >= 0` check while "tidying up" a units change —
-- and that is visible in the schema whether or not any data exists.
select tests.assert(
  not exists (
    select 1
      from pg_constraint con
      join pg_class rel on rel.oid = con.conrelid
      join pg_namespace ns on ns.oid = rel.relnamespace
     where ns.nspname = 'public'
       and rel.relname in ('workout_sets', 'template_sets')
       and con.contype = 'c'
       and pg_get_constraintdef(con.oid) ilike '%weight%'
  ),
  'a check constraint now mentions weight. Assisted bodyweight sets carry '
  'NEGATIVE assistance, so a non-negative check rejects a whole category '
  '(docs/01-data-model.md).'
);

\echo '05_weight_units_test: PASS'
