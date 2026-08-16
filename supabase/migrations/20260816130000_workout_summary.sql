-- ============================================================================
-- 0006 — workouts gains `summary`
--
-- `note` and `summary` are NOT two names for the same field. They differ in
-- author, direction and moment:
--
--   note     INSTRUCTIONS GOING IN. Written by the plan (copied from the
--            template when a workout starts) or by the MCP server. Read before
--            and during the session.
--   summary  FEEDBACK COMING OUT. Written by the user at the end, read later by
--            the AI. "Slept badly, everything felt heavy."
--
-- Collapsing them would leave a reporting tool unable to tell its own
-- instruction from the user's report of how it went — and that report is
-- precisely what distinguishes a bad night from a downward trend. An AI that
-- cannot make that distinction gives confidently wrong coaching advice, which
-- is the failure mode docs/03-mcp-tools.md is most concerned with.
--
-- Nullable, like `note`: most sessions will have neither, and an empty string
-- would be a worse way of saying "there isn't one".
--
-- Free to add today — no training data, nothing synced, no second device. The
-- same column after Phase 2 ships is an ALTER against rows the user cares
-- about.
-- ============================================================================

alter table public.workouts
  add column summary text;

comment on column public.workouts.summary is
  'The user''s closing note about how the session went. Distinct from `note`, '
  'which carries instructions INTO the session. Both must be returned by the '
  'MCP read tools — see docs/03-mcp-tools.md.';
