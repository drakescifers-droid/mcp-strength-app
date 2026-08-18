-- ============================================================================
-- 0010 — Repair ten rows that migration 0009 converted TWICE
--
-- **This is the failure 0009's own comment warned about, arriving by a route
-- nobody watched.** That comment says: apply the SQL migration BEFORE running
-- a build of the new client against this project, because rows that were
-- already dirty when the client converted its own store push KILOGRAMS, and a
-- server that has not converted yet would convert them a second time.
--
-- That is exactly what happened, in that order, on 2026-08-18:
--
--   ~20:44 CDT (17th)  the UI-preview fixture rows are pushed, in POUNDS
--   13:3x CDT          the new client converts its local store to kilograms
--   13:35:05 CDT       something pushes those rows again, now in KILOGRAMS
--   13:40:14 CDT       migration 0009 runs and converts them a SECOND time
--
-- ## How the affected rows were identified — not by guessing
--
-- Dividing the stored value by 0.45359237 twice returns EXACTLY the pounds the
-- fixture generator writes (95, 185, 155, 135, 35 lb, and a 6730 lb session
-- volume). One division returns 43.09, 83.91, 15.88 — numbers no gym stocks
-- and no fixture contains. Two divisions landing on round plate loads across
-- ten independent rows is not a coincidence; it is the signature.
--
-- The two rows from the real sync round trip (Bench Press 135x5, Deadlift
-- 225x3) divide ONCE to 135 and 225 and are correct. They are not touched
-- here, and that asymmetry is the evidence: they were pushed on the 17th,
-- before the client had anything to convert, so 0009 was their first and only
-- pass.
--
-- Rows are listed BY ID rather than matched by a predicate. A predicate over
-- `updated_at` would work today and is one careless edit away from matching
-- the correct rows too, and the whole class of bug being repaired here is a
-- conversion applied to something that had already had it. An explicit list
-- cannot over-match, and on any database that does not contain these ids —
-- including the throwaway container behind `supabase/tests/run.sh` — every
-- statement is a no-op.
--
-- ## What is NOT fixed here
--
-- **The push at 13:35 is unexplained and that matters more than these ten
-- rows.** Both sync triggers are guarded by `!UIPreviewMode.isEnabled`, and a
-- controlled relaunch in preview mode moved no `server_updated_at` at all, so
-- preview mode is not it. The app's own `lastSyncedAt` still reads the 17th,
-- meaning whatever pushed never completed a full run. The leading hypothesis
-- is the XCTest host: `xcodebuild test` launches the app itself, with no
-- `-uiPreview` argument and with a real session in the keychain, so running the
-- unit suite would sync a developer's simulator into the live project. That is
-- a hypothesis, not a finding — see docs/04-status.md.
-- ============================================================================

update public.workout_sets
   set weight = weight / 0.45359237
 where id in (
   '5059cd9e-49bd-4d5d-8a77-aea18647ce07',  -- warmup   95 lb x 10
   'a2d64afd-cc35-4968-a34c-58ec627244e6',  -- warmup  135 lb x 5
   'a5f99226-5ddd-4000-8565-603b07c8144f',  -- normal  185 lb x 8
   '67b7b873-27ee-44a0-9803-7c6c731c0528',  -- normal  185 lb x 7
   '26df5f17-ce18-4073-b733-deb0f5faefce',  -- normal  185 lb x 6 (skipped)
   'dfd33481-96d4-4c54-8f90-801d0d3a8753',  -- dropSet 155 lb x 6
   'ce99e882-7e10-4fd0-a4b7-09ff64973224',  -- normal   35 lb x 15
   '2fe8391e-840b-450e-ba77-2661f466baf3',  -- normal   35 lb x 13
   '5c5bbf77-2d62-4248-b449-a8dfdff36dc0'   -- normal   35 lb x 12
 )
   and weight is not null;

-- The fixture session's cached volume, 6730 lb. The other two workouts carry
-- 306.17485 (675 lb) and are correct.
update public.workouts
   set total_volume = total_volume / 0.45359237
 where id = '179c4cf9-6241-4f06-be3f-abdcecf1c0aa'
   and total_volume <> 0;
