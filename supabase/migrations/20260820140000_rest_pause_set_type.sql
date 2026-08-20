-- ============================================================================
-- restPause on set_type
--
-- Rest-pause (and myo-reps, which are a rest-pause protocol) is a fifth set
-- type alongside normal / warmup / dropSet / failure. The Swift raw value
-- is restPause — camelCase, character for character the column value
-- (docs/05-database.md § Naming). rest_pause and myoRep are not values;
-- a mapping table is how Phase 0 silently rewrote an unknown set_type.
--
-- ADD VALUE only. The type is referenced by live columns on a project that
-- already has rows, so drop-and-recreate would require rewriting both set
-- tables and would fail. A value added this way cannot be USED in the same
-- transaction that adds it; the proof insert lives in
-- supabase/tests/08_rest_pause_test.sql, which runs after every migration
-- has committed.
-- ============================================================================

alter type public.set_type add value if not exists 'restPause';
