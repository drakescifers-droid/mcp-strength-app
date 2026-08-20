import { assertEquals } from "jsr:@std/assert@1";
import { getWorkoutHistory, getWorkoutHistoryInput } from "./getWorkoutHistory.ts";
import { parseLimit, parseTimeBound } from "./workoutRead.ts";
import { clientWith } from "./testSupport.ts";

const workoutId = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const unfinishedId = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
const olderId = "cccccccc-cccc-cccc-cccc-cccccccccccc";
const slotId = "11111111-1111-1111-1111-111111111111";
const benchId = "22222222-2222-2222-2222-222222222222";
const setId = "33333333-3333-3333-3333-333333333333";
const tombstoneSlot = "99999999-9999-9999-9999-999999999999";
const templateId = "dddddddd-dddd-dddd-dddd-dddddddddddd";

const db = {
  workouts: [
    {
      id: workoutId,
      name: "Push Day",
      template_id: templateId,
      started_at: "2026-08-18T18:00:00.000Z",
      completed_at: "2026-08-18T19:10:00.000Z",
      duration_seconds: 4200,
      note: "focus on tempo, you are deloading",
      summary: "slept badly, everything felt heavy",
      total_volume: 3054.3,
      deleted_at: null,
    },
    {
      id: olderId,
      name: "Push Day",
      template_id: templateId,
      started_at: "2026-08-11T18:00:00.000Z",
      completed_at: "2026-08-11T19:00:00.000Z",
      duration_seconds: 3600,
      note: null,
      summary: null,
      total_volume: 2800,
      deleted_at: null,
    },
    {
      id: unfinishedId,
      name: "Live session",
      template_id: null,
      started_at: "2026-08-20T12:00:00.000Z",
      completed_at: null,
      duration_seconds: 0,
      note: "should never appear",
      summary: null,
      total_volume: 0,
      deleted_at: null,
    },
    {
      id: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",
      name: "Gone",
      template_id: null,
      started_at: "2026-08-01T12:00:00.000Z",
      completed_at: "2026-08-01T13:00:00.000Z",
      duration_seconds: 3600,
      note: null,
      summary: null,
      total_volume: 0,
      deleted_at: "2026-08-02T00:00:00.000Z",
    },
  ],
  workout_exercises: [
    {
      id: slotId,
      workout_id: workoutId,
      exercise_id: benchId,
      sort_order: 0,
      superset_group_id: null,
      note: "elbows tucked",
      sticky_note: "stop one short of failure",
      deleted_at: null,
    },
    {
      id: tombstoneSlot,
      workout_id: workoutId,
      exercise_id: benchId,
      sort_order: 1,
      superset_group_id: null,
      note: "tombstone",
      sticky_note: null,
      deleted_at: "2026-08-18T19:00:00.000Z",
    },
    {
      id: "44444444-4444-4444-4444-444444444444",
      workout_id: olderId,
      exercise_id: benchId,
      sort_order: 0,
      superset_group_id: null,
      note: null,
      sticky_note: null,
      deleted_at: null,
    },
  ],
  workout_sets: [
    {
      id: setId,
      workout_exercise_id: slotId,
      sort_order: 0,
      set_type: "dropSet",
      weight: 61.235,
      reps: 5,
      rpe: 8,
      distance: null,
      duration_seconds: null,
      rest_seconds: 150,
      is_completed: true,
      deleted_at: null,
    },
    {
      id: "55555555-5555-5555-5555-555555555555",
      workout_exercise_id: "44444444-4444-4444-4444-444444444444",
      sort_order: 0,
      set_type: "normal",
      weight: 60,
      reps: 5,
      rpe: null,
      distance: null,
      duration_seconds: null,
      rest_seconds: 90,
      is_completed: true,
      deleted_at: null,
    },
  ],
  exercises: [
    {
      id: benchId,
      name: "Bench Press (Barbell)",
      body_part: "chest",
      secondary_body_parts: [],
      category: "barbell",
    },
  ],
};

type HistoryPayload = {
  workouts: Array<{
    id: string;
    note: string | null;
    summary: string | null;
    weight_unit: string;
    total_volume: number;
    exercises: Array<{
      note: string | null;
      sticky_note: string | null;
      exercise_name: string | null;
      sets: Array<{
        set_type: string;
        weight: number | null;
        weight_unit: string;
        rpe: number | null;
      }>;
    }>;
  }>;
  truncated: boolean;
  ignored_fields: string[];
};

Deno.test("returns notes, summary, sticky notes, and kilograms", async () => {
  const result = await getWorkoutHistory(clientWith(db), { id: workoutId });
  assertEquals(result.isError, undefined);
  const payload = result.structuredContent as HistoryPayload;
  assertEquals(payload.workouts.length, 1);
  const workout = payload.workouts[0];
  assertEquals(workout.note, "focus on tempo, you are deloading");
  assertEquals(workout.summary, "slept badly, everything felt heavy");
  assertEquals(workout.weight_unit, "kg");
  assertEquals(workout.exercises.length, 1);
  assertEquals(workout.exercises[0].note, "elbows tucked");
  assertEquals(workout.exercises[0].sticky_note, "stop one short of failure");
  assertEquals(workout.exercises[0].exercise_name, "Bench Press (Barbell)");
  assertEquals(workout.exercises[0].sets[0].set_type, "dropSet");
  assertEquals(workout.exercises[0].sets[0].weight, 61.235);
  assertEquals(workout.exercises[0].sets[0].weight_unit, "kg");
  assertEquals(workout.exercises[0].sets[0].rpe, 8);
});

Deno.test("lists completed sessions newest first and hides unfinished ones", async () => {
  const result = await getWorkoutHistory(clientWith(db), {});
  const payload = result.structuredContent as HistoryPayload;
  assertEquals(result.isError, undefined);
  assertEquals(payload.workouts.map((w) => w.id), [workoutId, olderId]);
});

Deno.test("date window is inclusive and date-only covers the UTC day", async () => {
  const result = await getWorkoutHistory(clientWith(db), {
    from: "2026-08-18",
    to: "2026-08-18",
  });
  const payload = result.structuredContent as HistoryPayload;
  assertEquals(payload.workouts.map((w) => w.id), [workoutId]);
});

Deno.test("a missing id is a tool error that names the id", async () => {
  const result = await getWorkoutHistory(clientWith(db), {
    id: "ffffffff-ffff-ffff-ffff-ffffffffffff",
  });
  assertEquals(result.isError, true);
  assertEquals(
    result.content[0].text.includes("ffffffff-ffff-ffff-ffff-ffffffffffff"),
    true,
  );
});

Deno.test("unfinished id lookup is a miss, not an empty success", async () => {
  const result = await getWorkoutHistory(clientWith(db), { id: unfinishedId });
  assertEquals(result.isError, true);
  assertEquals(result.content[0].text.includes(unfinishedId), true);
});

Deno.test("from after to is a tool error", async () => {
  const result = await getWorkoutHistory(clientWith(db), {
    from: "2026-08-20",
    to: "2026-08-01",
  });
  assertEquals(result.isError, true);
  assertEquals(result.content[0].text.includes("from must be on or before to"), true);
});

Deno.test("unknown fields are rejected and drop_set is not a set_type", () => {
  assertEquals(
    getWorkoutHistoryInput.safeParse({ extra: true }).success,
    false,
  );
  assertEquals(
    getWorkoutHistoryInput.safeParse({ limit: 0 }).success,
    false,
  );
});

Deno.test("parseTimeBound accepts a date or an ISO timestamp", () => {
  const from = parseTimeBound("2026-08-18", "from");
  const to = parseTimeBound("2026-08-18", "to");
  assertEquals("iso" in from && from.iso, "2026-08-18T00:00:00.000Z");
  assertEquals("iso" in to && to.iso, "2026-08-18T23:59:59.999Z");
  const stamped = parseTimeBound("2026-08-18T18:00:00Z", "from");
  assertEquals("iso" in stamped, true);
  const bad = parseTimeBound("next Tuesday", "from");
  assertEquals("error" in bad, true);
});

Deno.test("parseLimit defaults to 20 and rejects zero", () => {
  assertEquals(parseLimit(undefined), { limit: 20 });
  assertEquals("error" in parseLimit(0), true);
  assertEquals("error" in parseLimit(51), true);
});
