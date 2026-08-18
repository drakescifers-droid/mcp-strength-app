-- ============================================================================
-- 0009 — Stored weights become canonical KILOGRAMS
--
-- Every weight in this database was written by a client that stored what the
-- user typed, and the only user typed pounds. Storage is now canonical
-- kilograms (docs/01-data-model.md § Units decision), so those numbers mean
-- nothing until they are multiplied by the definition of a pound.
--
-- 0.45359237 is EXACT. The international avoirdupois pound has been defined as
-- exactly 0.45359237 kg since 1959, so this is a definition rather than a
-- measurement — the same constant as `WeightUnits.kilogramsPerPound` on the
-- client, and the two must never drift.
--
-- ## Three columns, and the third is the one that hides
--
--   workout_sets.weight    the load actually lifted
--   template_sets.weight   the prescribed load
--   workouts.total_volume  a CACHED `weight × reps` total
--
-- `total_volume` has no "weight" in its name, nothing recomputes it on read
-- (the client writes it once at Finish), and it is the number the history list
-- actually displays. Convert the sets and not the total and every finished
-- session reports 2.2× the sets printed underneath it. A volume is a sum of
-- products of weights, so it scales by exactly the same factor.
--
-- `pr_count` is a count and `distance` is a distance; neither is a mass.
--
-- ## Why this is safe to do as a bulk UPDATE
--
-- **The sync triggers are left ON deliberately.** `set_sync_metadata` will
-- stamp a new `server_updated_at` on every converted row, which is correct and
-- useful: the values genuinely changed, so every device should learn about it
-- on its next pull. That also makes this self-healing — a client that somehow
-- missed its own local conversion is handed the right numbers.
--
-- `updated_at` is deliberately NOT touched. It is the last-write-wins key, and
-- bumping it would let this migration outrank a newer edit sitting unpushed on
-- a device. Leaving it equal also means `reject_stale_update` passes the write
-- through: ties are allowed (migration 0007, responsibility 3).
--
-- ## Ordering, and it is the one dangerous thing here
--
-- **Apply this BEFORE running a build of the new client against this project.**
-- The client converts its own store without marking rows dirty, so it will not
-- re-push what it converted — with one exception: rows that were ALREADY dirty
-- when it converted. Those push kilograms. If this migration has not run yet,
-- it would then convert them a second time and halve them. Applying this first
-- closes that window entirely.
--
-- Tombstoned rows are converted too. They are invisible to every screen, but a
-- table where the live weights are kilograms and the deleted ones are pounds
-- has two meanings for one column.
-- ============================================================================

update public.workout_sets
   set weight = weight * 0.45359237
 where weight is not null;

update public.template_sets
   set weight = weight * 0.45359237
 where weight is not null;

update public.workouts
   set total_volume = total_volume * 0.45359237
 where total_volume <> 0;

comment on column public.workout_sets.weight is
  'Load lifted, in KILOGRAMS. Canonical storage — the client converts to the '
  'user''s display unit on read and back on write (docs/01-data-model.md '
  '§ Units decision). Nullable: bodyweight and reps-only sets carry no load, '
  'and negative values are legitimate assistance.';

comment on column public.template_sets.weight is
  'Prescribed load, in KILOGRAMS. Same canonical storage as '
  'workout_sets.weight, and nullable for the same reasons — plenty of '
  'prescriptions carry only a rep range.';

comment on column public.workouts.total_volume is
  'Cached sum of weight x reps over the workout''s completed sets, in '
  'KILOGRAMS. Written once by the client at Finish and never recomputed on '
  'read, so it has to be converted alongside the sets it was computed from.';
