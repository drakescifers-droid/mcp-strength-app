# Status

A living record of where the project actually is, and what is **deliberately** unfinished.

This is the one document that is expected to go stale, so it is deliberately narrow:

| Question | Where the answer lives |
|---|---|
| What changed, when, and why? | **git log** — commit messages carry the reasoning, not just the diff |
| Why is the schema shaped this way? | `01-data-model.md` |
| Why Supabase, how does sync work, what about observability? | `02-architecture.md` |
| What is the MCP tool contract? | `03-mcp-tools.md` |
| Which worker models are good at what? | `~/ringer/docs/MODEL-NOTES.md` |
| **What is built, what is half-built, and what did we skip on purpose?** | **this file** |

Do not duplicate the other four here. If a design question is genuinely open, it belongs in
`01`/`02`/`03` under their Open questions sections, not in this list.

---

## Where the project is

**Phase 0 — complete.** A throwaway spike proved the transcript→template path works and, more
usefully, proved what it *loses*: every field the schema could not hold was a prescription field.
Findings are in `03-mcp-tools.md`; `spike/` is frozen and is not a starting point.

**Phase 1 — essentially complete.** `MCPStrength/` is a working offline iOS app: workout logging
with a live rest timer, templates with an editor and start-from-template, history with computed
volume and best set, an exercise library with alias/hint/spelling matching, seeded exercise and
measurement libraries, body measurements, a profile with an 8-week chart, a design token layer,
and a five-tab shell.

`02-architecture.md` defined Phase 1 as *"a working app you can train with, no backend."* That is
true today — with the standing caveat that it should **not** hold real training data until Phase 2
provides sync and backup, because a local-only store has no recovery story.

**Phases 2–4 — not started.** Backend and sync, then the real multi-user MCP server, then product.

---

## Deliberately deferred

These are not oversights. Each was cut with a reason, and the reason is the point.

| Deferred | Why |
|---|---|
| **Program UI** (rotation view, "what's next") | Post-launch. Not critical to the app succeeding, and with no plan to train on a half-built app, shipping it early teaches nothing. **The schema still landed in Phase 1** — see the note below. |
| **Personal records / PR counts** | Real feature (compare against all prior history, per exercise, per rep count). Nothing computes them, and a hardcoded "0 PRs" reads as *you set no records* rather than *not implemented*. |
| **Apple Health sync** | Phase 2. `02` decides it is bidirectional and flags an echo-loop trap; doing it half-way is worse than not doing it. The reference's "enable Health" hint is deliberately absent — it would point at a setting that does not exist. |
| **Progression rules beyond linear** | One structured rule (hit all reps → add X) covers most intermediate programs. Percentage-of-training-max, RPE autoregulation and waves turn a field into a small programming language. |
| **RIR** | Same information as RPE on an inverted scale. One scale is easier to coach against than two. |
| **Supersets, plate calculator, exercise artwork, per-exercise overflow menus, calendar view, widget dashboard, accounts/avatars** | Scope. None block the core loop. |

> **The Program schema is the exception worth watching.** Its UI is post-launch, but
> `TemplateFolder.kind` / `ProgramDay` / `cursor` / `totalCycles` shipped in Phase 1 on purpose.
> Because the UI comes *after* launch, letting the schema slide with it would mean adding a table
> to a database that already holds real training history. Additive-by-construction only helps if
> the columns exist before there are users.

---

## Known loose ends

Small, none blocking, roughly in the order I would do them.

1. **Measurement ordering.** The list is alphabetical; the reference is anatomical (Weight first in
   Core; Neck → Shoulders → Chest → … in Body Part). Wants a `sortOrder` field in
   `measurement-seed.json`. Worth doing before the order becomes muscle memory.
2. **Seed call placement.** The exercise seed runs at `ModelContainer` construction; the measurement
   seed runs from `ContentView`. Both work, both are idempotent, but they should live together.
3. **Set-type annotation in the Previous column.** The reference renders a prior drop set as
   `75 lb × 11 (D)`; `PreviousText` currently formats weight and reps only. Small, and now
   reachable — set types can finally *be* something other than normal.
4. **Per-template overflow menu.** The reference gives each template card a `•••` with Edit /
   Rename / Duplicate / Archive / Share / Delete. **There is no way to delete a template at all
   today.** Archive and Share have no schema behind them and would need designing first.
5. **Moving an existing template between folders.** A template can be *created* into a folder, but
   not moved afterwards. The reference has no menu affordance for this either — it appears to be
   drag-to-reorder — so this needs a product decision before it needs code.

> **Set-type editing and folder lifecycle are both done** (they were #1 and #2 here). Set types
> are editable from the badge and working-set numbering excludes lettered sets. Folders can be
> created, renamed, deleted, collapsed, and filled via Add Template; deleting one keeps its
> templates and unfiles them.

> **Lesson from the folder work, worth not relearning.** `Add Template` shipped through a green
> structural check and 125 green tests while filing nothing, because `.sheet(isPresented:)` reads
> companion `@State` that is lost when written from inside a `Menu` action. Two things hid it: a
> check can only assert structure, not presentation-state timing; and the delete test asserted
> `folder == nil` *after* deleting without asserting it was set *before*, so it passed vacuously.
> **Prefer `.sheet(item:)` whenever a sheet needs a value**, and when a test asserts something
> becomes nil, assert it was non-nil first.

---

## Lessons worth not relearning

- **Look at the running app.** Three bugs passed a green test suite and were caught only by
  launching it: a seed importer that nothing ever called, a navigation title rendering black on a
  dark background (system chrome does not read our tokens), and `totalVolume` that nothing computed
  — every history card would have shipped reading `0 lb`.
- **Never display a fabricated zero.** "0 PRs", "0 inches" for an unmeasured body part, or a
  weekly chart that silently drops empty weeks all read as *data* rather than *absence*. Show
  nothing instead.
- **Black-box first, then read the source.** Driving a tool surface as a client shows where a
  caller trips; only the source tells you whether the cause was a schema gap or a description gap.
  They look identical from outside and have completely different fixes.
