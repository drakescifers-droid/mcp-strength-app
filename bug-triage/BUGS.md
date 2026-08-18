# Bug log — found by using the app on a real device

Not fixed yet. Logging as found, triaging as a batch. Each entry: what's wrong,
where it likely lives in code, and a severity guess (to be revised at triage).

---

## 1. [FIXED] "Update Rest Timers" only affects new sets, not existing ones

**Screen:** Template editor, exercise options menu ("Assisted Dip" example)

**Expected:** Changing the rest timer for an exercise updates every set under
it, including sets that already exist.

**Actual:** Only new sets added via "+ Add Set" pick up the new default. Sets
already in the list keep their old rest time.

**Likely cause:** The options menu is probably writing `defaultRestSeconds` on
the exercise (which only seeds *new* sets going forward) without also looping
over the exercise's existing sets and updating each `restSeconds`.

**Severity guess:** Medium — confusing but not data-destructive. Worth
confirming whether this is template-editor-only or also present on the live
workout screen (same shared menu component).

**Related — the label lies too.** After changing the rest timer, "+ Add Set"
shows the NEW time in its own label (e.g. "1:00") but the set it actually
inserts carries the OLD time (e.g. 2:00 rest). So the button is reading a
different value than the one it writes — two places compute or cache
"default rest" and they've gone out of sync. This is a second symptom of the
same underlying miss, not a separate root cause, but worth confirming once
the fix for #1 is in: does fixing where existing sets get updated also fix
what a NEW set inherits, or are there really two write sites.

## 2. [FIXED] Rest timer progress bar shrinks from both sides instead of right-to-left

**Screen:** Active workout, the blue rest bar that replaces a set's divider
while resting.

**Expected:** The bar should look like a progress/depletion bar — full width
at the start of rest, shrinking from the right edge only, so it reads as
draining away.

**Actual:** It shrinks from both ends toward the center simultaneously.

**Confirmed root cause** (read the code, not a guess): `RestProgressBar` in
`Views/ActiveWorkoutScreen.swift`. The accent-fill `Rectangle` sits in a
`ZStack` with no alignment specified, so SwiftUI centers it by default.
Shrinking `.frame(width:)` on a centered view removes width from both edges
equally — that's the "converging to the center" look.

**Fix shape (not yet applied):** anchor the fill to the leading edge, e.g.
`ZStack(alignment: .leading) { ... }` on the outer ZStack, or an explicit
`.frame(width: ..., alignment: .leading)` and top-level `HStack` in place of
the ZStack. Purely a layout fix — the underlying `progress` value and timing
are correct, only the anchor is missing.

**Severity guess:** Low-medium — cosmetic, but the rest timer is looked at on
every set of every workout, so it's a high-visibility polish item.

## 3. No notification when the rest timer finishes

**Screen:** Active workout, rest timer.

**Report (Drake's words):** "There is no notification when the timer is
done — we'll need a push notification for that."

**Confirmed:** Checked the whole codebase — there is genuinely nothing.
`RestTimer.isFinished(at:)` exists and is correct, but nothing observes it to
fire a sound, haptic, or notification. When rest ends, the progress bar
(bug #2's bar) just stops being shown; that's the entire signal today. If your
phone is in your pocket or the screen is off, you have no way to know rest is
over except checking.

**One correction on the ask: this wants a LOCAL notification, not a push
one**, and the distinction matters for scope. A push notification requires a
server round-trip (APNs, a device token, something on `mcp-strength` to send
it) — none of that exists and none of it is needed here. A LOCAL notification
is scheduled by the app itself for a future time ("fire in 90 seconds") and
needs no server, no entitlement beyond notification permission, and no
network. Also checked: no entitlements file and no background modes are
configured yet, so this is a from-scratch feature, not a tweak — first
launch would need to ask permission (`UNUserNotificationCenter` authorization
request), and the timer would need to schedule/reschedule a local
notification whenever rest starts, pauses, or the duration is edited.

**Severity guess:** High-value, not urgent — nobody is blocked by it, but
it's core to actually training with the app instead of watching a screen.
Bigger than #1/#2: this is new capability (permission flow + scheduling),
not a fix to existing behavior. Worth a design pass rather than a quick
patch — e.g., should pausing cancel the pending notification, should editing
the rest time reschedule it, does Finishing early cancel it.

## 4. [BUILT] No way to delete a single set — add swipe-to-delete on set rows

**Screens:** Both the active workout screen and the template editor (shared
`SetRow` component).

**Request (Drake's words):** Swipe right-to-left on a set row to reveal a
delete option. Sets only — NOT on exercise rows (deleting an exercise already
has its own path via the exercise's `⋯` menu, "Remove Exercise").

**Confirmed:** Checked both screens — there is currently NO way to delete a
single set at all, by any gesture or menu. The only code that ever calls
`markDeleted()` on a `WorkoutSet` is warm-up regeneration replacing its own
generated rows; a normal set, once added, cannot be removed except by
discarding it unticked at Finish. This is a new capability, not a second
path alongside an existing delete.

**Scope note:** two screens, two different delete mechanics.
- **Workout screen** — a real, synced `WorkoutSet`. Per AGENTS.md rule 1, this
  MUST be a soft delete (`markDeleted()`), never `context.delete`, so the
  removal can reach a device that was offline when it happened.
- **Template editor** — value-type `DraftSet` drafts, nothing persisted until
  Save (same shape as the warm-up regeneration in that file). Removal there
  is just dropping it from the local array; `TemplateSaveDiff` works out the
  tombstone on Save, same as it does for warm-ups today.

Also: sets are reordered by drag-to-move on this screen already (title-drag
collapses the list) — need to confirm a leading/trailing swipe gesture
doesn't fight with anything else attached to the row (tap-to-edit weight/reps
fields, the set-type badge menu).

**Severity guess:** Genuine feature gap — right now the only way to walk back
an accidental "+ Add Set" is to leave it blank and let Finish silently drop
it (workout screen only; templates have no such discard). Worth building.

## 5. [FIXED] No rest divider after the final set of an exercise

**Screen:** Active workout.

**Report (Drake's words):** "Timer doesn't show after the final set when the
final set is incomplete, but if the final set is completed the timer starts."

**Confirmed, and it is intentional today.** `ExerciseBlock` renders a divider
between sets only (`if index < sortedSets.count - 1`); for the LAST set it
renders the running progress bar and nothing else. So an unfinished last set
shows no rest row at all, and ticking it makes the bar appear. That is exactly
what was reported.

**I claimed the reference agreed with the current behaviour. IT DOES NOT, and
Drake produced the screenshot that disproves it** — an F Shoulders exercise
ending set 3 with a 2:00 divider before "+ Add Set". The claim came from
`Workout screen/bottom of workout buttons and options.PNG`, where two exercises
do end without a divider; both of those happen to end on a DROP SET. One
sample, generalised into a rule about every exercise, and used to argue against
making a change. The reference has more states than any single screenshot
shows — read several before claiming what it "does".

**So the question is what problem it is actually causing.** Two readings, and
they want different fixes:

1. **"I can't see/edit the last set's rest."** Mostly solved by #1 already:
   every set now shares the exercise's rest, and "+ Add Set (1:30)" displays
   it. The gap left is that tapping to EDIT still requires a divider, and the
   last set has none.
2. **"It looks inconsistent."** Every set has a rest row except the last one,
   which only grows one while resting. If that is the complaint, the fix is to
   always render the divider after the last set — a deliberate divergence from
   the reference, and a small one.

**FIXED.** Every set now renders its rest row on both screens, last one
included. Two reasons beyond matching the reference: the rest after an
exercise's final set is the rest before the NEXT EXERCISE, which is a real rest
somebody takes; and editing a set's rest goes through tapping its divider, so a
set without one had a value that could be displayed but never changed.

**Severity guess:** was logged Low. Understated — it was hiding an edit
affordance, not just a line.

## 6. Reordering exercises gives no live feedback about where the drop lands

**Screen:** Active workout, dragging an exercise by its title.

**Report:** The exercises collapse down correctly when a drag starts, but
nothing moves while dragging. The other exercises do not shift up or open a
gap, so there is no indication where the dragged exercise will land until it
is dropped.

**Likely cause (not yet confirmed):** the reorder is built on
`.draggable` + `.dropDestination`, which is a DROP-based API — it reports a
drop, not continuous position. `ListOrdering` computes the new order after the
fact. The insertion point exists only at the moment of the drop, so there is
nothing driving an in-between layout. The `isTargeted:` callback fires per
drop target and is currently used only to collapse the list, not to open a
gap.

**Shape of a fix:** use `isTargeted` to insert a visible gap/placeholder above
or below the targeted exercise, so the row that is about to move makes room.
That is a real piece of work rather than a tweak, and it is pure interaction
polish — the kind that can only be judged by dragging it, not by a test.

**Severity guess:** Medium. Reordering WORKS; it is just blind while in
progress. Annoying with more than three exercises.

## 7. Templates cannot be dragged between folders

**Screen:** Start Workout tab, template grid.

**Report:** Unable to drag a template from one folder into another.

**Status: contradicts the docs, so it needs confirming before fixing.**
`docs/04-status.md` claims this is done — "Templates can be dragged between
folders and reordered within one", with `TemplateOrdering` owning the move
rule and cards themselves acting as drop targets. Either it regressed, it
never worked on a device, or it works only under conditions that are not
obvious (e.g. the destination folder must be expanded, or the drop must land
on a CARD rather than on the folder header).

**First step is to reproduce and find out which**, because "documented as
working" and "does not work in the hand" is exactly the pattern that produced
the `Add Template` bug recorded in 04-status.md — shipped through a green
check and 125 green tests while filing nothing.

**Severity guess:** Medium-high if genuinely broken — folders are the only
organisation the templates tab has.

---

# Status

- **#1 FIXED.** Two separate causes, not one. The template editor wrote the
  exercise default without touching existing sets. The workout screen was
  worse: `defaultRestSeconds` was HARDCODED to `90`, so the menu was ignored
  entirely there — the Add Set button always said 1:30 and always appended a
  90-second set. Both now write the default AND rewrite every set under the
  exercise. The sheet's wording changed to match ("Every set in X will use
  this"), and the scope case was renamed `.wholeExercise` so the type says what
  it does.
  - The "added a set and it had 2:00" symptom was a THIRD thing and is now
    moot: the divider *below* a set shows that set's rest, so adding a set
    revealed a new divider carrying the PREVIOUS set's old value. Nothing was
    wrong with the new set. With every set sharing one rest, it cannot recur.
- **#2 FIXED.** One word: `ZStack(alignment: .leading)`.
- **#4 BUILT**, and verified by driving it —
  `SwipeToDeleteSetWalkthroughTests` swipes a row open, taps Delete, and
  asserts the set count dropped. Hand-built gesture because `.swipeActions`
  needs a `List` and this app has none.
  - **Open question for Drake:** the row slides 88pt to expose Delete, which
    clips the set number and the Previous column off the leading edge — the
    two things you would want while deciding whether to delete that set. This
    matches how iOS swipe rows behave, so it may be fine. Flagged rather than
    changed.
- **#5 FIXED.** Every set gets a rest row now, on both screens.
- **#6, #7 LOGGED** — both are drag-and-drop, both need a real thumb to judge.
- **#3 IN PROGRESS** — the local notification. Largest of the four: needs a
  permission prompt, scheduling, and cancel/reschedule rules on pause, edit,
  skip and finish.
