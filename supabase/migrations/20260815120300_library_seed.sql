-- ============================================================================
-- 0004 — The seeded library (global rows, user_id IS NULL)
--
-- GENERATED FILE — do not edit by hand.
--   source: MCPStrength/MCPStrength/Resources/{exercise,measurement}-seed.json
--   regenerate: python3 supabase/scripts/generate_library_seed.py
--
-- These rows are the integrity constraint for the whole product. Without a
-- shared library with stable ids, every AI-generated plan invents its own
-- exercise names and a user's history for one movement fragments across
-- "Lateral Raise (Machine)" / "Machine Lateral Raise" / "Lat Raise" — and
-- progress tracking, the entire point, silently breaks.
--
-- THE UUIDS ARE A PERMANENT CONTRACT. They are baked into the seed JSON and
-- copied here verbatim; they are never generated at apply time. Every workout
-- ever logged points at an exercise by id, so a re-seed that hands an existing
-- exercise a NEW uuid detaches every user's history for that movement. There
-- is no good fix afterwards.
--
-- The upserts refresh only the LIBRARY-DEFINED fields (name, body_part,
-- category, aliases), matching ExerciseSeedImporter on the device. Per-user
-- settings live in exercise_preferences and are never touched by a re-seed.
-- ============================================================================

-- 25 exercises
insert into public.exercises
  (id, user_id, name, aliases, body_part, category, is_custom)
values
  ('6aaeeb2d-d324-4999-91fb-ceb5487fd80e', null, 'Bench Press (Barbell)', array['bench press', 'barbell bench press']::text[], 'chest'::public.body_part, 'barbell'::public.exercise_category, false),
  ('9a3540e5-9841-4efe-a09a-7e2509a2e4eb', null, 'Squat (Barbell)', array['back squat', 'barbell squat']::text[], 'legs'::public.body_part, 'barbell'::public.exercise_category, false),
  ('ccd9e6e1-38a5-46d0-bc1b-eca51aed41bc', null, 'Deadlift (Barbell)', array['deadlift', 'conventional deadlift']::text[], 'back'::public.body_part, 'barbell'::public.exercise_category, false),
  ('d8849bdc-f8b4-4c67-ace7-ae04311542fa', null, 'Overhead Press (Barbell)', array['ohp', 'military press', 'shoulder press']::text[], 'shoulders'::public.body_part, 'barbell'::public.exercise_category, false),
  ('5b3e00a2-b1bf-470e-9782-408984ab130e', null, 'Barbell Row', array['bent over row', 'row']::text[], 'back'::public.body_part, 'barbell'::public.exercise_category, false),
  ('2aa0a5f0-2a1b-4e0b-83c8-9e3b1578fa5d', null, 'Lateral Raise (Dumbbell)', array['dumbbell lateral raise', 'side raise']::text[], 'shoulders'::public.body_part, 'dumbbell'::public.exercise_category, false),
  ('8b0b1284-eda2-418d-8991-0de0269a7601', null, 'Bicep Curl (Dumbbell)', array['dumbbell curl', 'db curl']::text[], 'arms'::public.body_part, 'dumbbell'::public.exercise_category, false),
  ('94bdcb4a-9469-448d-af17-b62e68f1abb5', null, 'Dumbbell Row', array['db row', 'row']::text[], 'back'::public.body_part, 'dumbbell'::public.exercise_category, false),
  ('f0504978-717f-443f-9a18-aa5feedfdd58', null, 'Incline Bench Press (Dumbbell)', array['incline db press']::text[], 'chest'::public.body_part, 'dumbbell'::public.exercise_category, false),
  ('8de7cc2a-06ac-40fd-b99c-e5461f67a107', null, 'Chest Fly (Machine)', array['pec deck', 'machine fly']::text[], 'chest'::public.body_part, 'machineOther'::public.exercise_category, false),
  ('99fb367c-8860-467d-8bc3-05e7545312be', null, 'Leg Press', array['leg press']::text[], 'legs'::public.body_part, 'machineOther'::public.exercise_category, false),
  ('07fc8389-e0d3-45d3-af79-4dd97d777bd2', null, 'Lat Pulldown', array['pulldown', 'cable pulldown']::text[], 'back'::public.body_part, 'machineOther'::public.exercise_category, false),
  ('a7d8825a-ed41-49c8-9c49-406db9ea9a36', null, 'Seated Cable Row', array['cable row', 'row']::text[], 'back'::public.body_part, 'machineOther'::public.exercise_category, false),
  ('32b233a3-6633-4d88-94b7-15869ad6fc82', null, 'Leg Extension', array['leg extensions']::text[], 'legs'::public.body_part, 'machineOther'::public.exercise_category, false),
  ('7c4b861c-40ef-4b09-a6f8-25335ad18495', null, 'Leg Curl (Machine)', array['leg curl', 'hamstring curl']::text[], 'legs'::public.body_part, 'machineOther'::public.exercise_category, false),
  ('0f13df5a-edf6-4935-a7dc-a3f08ac6298c', null, 'Triceps Pushdown (Cable)', array['triceps pushdown', 'pushdown']::text[], 'arms'::public.body_part, 'machineOther'::public.exercise_category, false),
  ('7cd2a197-95fe-4ecb-8454-1d163ad5fd41', null, 'Pull Up', array['pullup', 'chin up']::text[], 'back'::public.body_part, 'weightedBodyweight'::public.exercise_category, false),
  ('f32d2257-6616-4b8e-9dbc-2765293a6e50', null, 'Dip', array['dips', 'chest dip']::text[], 'chest'::public.body_part, 'weightedBodyweight'::public.exercise_category, false),
  ('23ba51e7-0b8d-44ba-9a95-f55a6389af0c', null, 'Assisted Pull Up', array['assisted pullup']::text[], 'back'::public.body_part, 'assistedBodyweight'::public.exercise_category, false),
  ('e3e0ddfb-5f39-4a21-ad26-c8f146c5f355', null, 'Assisted Dip', array['assisted dips']::text[], 'arms'::public.body_part, 'assistedBodyweight'::public.exercise_category, false),
  ('186337a0-2a33-4f27-bc65-5a946e8b9646', null, 'Crunch', array['ab crunch']::text[], 'core'::public.body_part, 'repsOnly'::public.exercise_category, false),
  ('30f510b3-91a9-4414-ac39-c58c34d19c4a', null, 'Push Up', array['pushup', 'press up']::text[], 'chest'::public.body_part, 'repsOnly'::public.exercise_category, false),
  ('e66230c3-e9df-41d7-98e7-dce2abeae51e', null, 'Running (Cardio)', array['treadmill run', 'running']::text[], 'cardio'::public.body_part, 'cardio'::public.exercise_category, false),
  ('ddc0ddfd-4ff3-4e47-9c7f-2469f2f7ca84', null, 'Rowing (Cardio)', array['row erg', 'erg']::text[], 'cardio'::public.body_part, 'cardio'::public.exercise_category, false),
  ('3c484e9d-8347-4d1f-bcdf-378ecdc33a23', null, 'Plank', array['front plank', 'plank hold']::text[], 'core'::public.body_part, 'duration'::public.exercise_category, false)
on conflict (id) do update set
  name      = excluded.name,
  body_part = excluded.body_part,
  category  = excluded.category,
  aliases   = excluded.aliases;


-- 18 measurement types
--
-- The seed JSON also carries a `unit` per type. There is no column for it:
-- MeasurementType has no unit in the SwiftData model either — the unit is
-- recorded per ENTRY, because a user can switch units and the entries already
-- written keep the unit they were taken in. The JSON field seeds the default
-- offered in the UI, which is a client concern.
insert into public.measurement_types
  (id, user_id, name, group_kind, sort_order)
values
  ('d4982888-f08b-4e32-892c-4a7c36658311', null, 'Weight', 'core'::public.measurement_group, 0),
  ('5725b6bb-91e7-4ce9-a68f-5f9584f43649', null, 'Body Fat %', 'core'::public.measurement_group, 1),
  ('e701352b-95d1-4623-b293-e001dc0d70dc', null, 'Caloric Intake', 'core'::public.measurement_group, 2),
  ('fc17fc4a-6e88-4176-9c90-c7d9c3d847fe', null, 'Neck', 'bodyPart'::public.measurement_group, 0),
  ('6232ba5a-0236-498b-9a9b-d7da38b3a714', null, 'Shoulders', 'bodyPart'::public.measurement_group, 1),
  ('41bb7a68-8487-4288-8673-c313bb440a84', null, 'Chest', 'bodyPart'::public.measurement_group, 2),
  ('3b25f841-1bb0-477d-bd4d-8d157da1a0ea', null, 'Left Bicep', 'bodyPart'::public.measurement_group, 3),
  ('f5de2228-8486-4818-bebb-90a75f589dc8', null, 'Right Bicep', 'bodyPart'::public.measurement_group, 4),
  ('2e1f4c6e-1151-42b8-9d8c-6baa5d87a1d8', null, 'Left Forearm', 'bodyPart'::public.measurement_group, 5),
  ('4a8c8735-88a4-438e-90ee-72fd9fe540b0', null, 'Right Forearm', 'bodyPart'::public.measurement_group, 6),
  ('41d8d884-838a-402f-b9b9-69c8d2de964c', null, 'Upper Abs', 'bodyPart'::public.measurement_group, 7),
  ('6cc45dde-f100-48a4-852b-7d85e9d722a4', null, 'Waist', 'bodyPart'::public.measurement_group, 8),
  ('0b82e5cd-5f8e-4140-a46c-8f59559ec67c', null, 'Lower Abs', 'bodyPart'::public.measurement_group, 9),
  ('292bc726-919d-4225-857e-c491422a3753', null, 'Hips', 'bodyPart'::public.measurement_group, 10),
  ('9f991297-b3a4-4e1b-9d56-e586d78d3e95', null, 'Left Thigh', 'bodyPart'::public.measurement_group, 11),
  ('e45093de-707e-4539-b0c6-50a5c799246a', null, 'Right Thigh', 'bodyPart'::public.measurement_group, 12),
  ('6ad35d18-fcb1-46cd-85f1-05dafd8672fd', null, 'Left Calf', 'bodyPart'::public.measurement_group, 13),
  ('c3761154-115c-47cd-82d8-3bceed3063a7', null, 'Right Calf', 'bodyPart'::public.measurement_group, 14)
on conflict (id) do update set
  name       = excluded.name,
  group_kind = excluded.group_kind,
  sort_order = excluded.sort_order;
