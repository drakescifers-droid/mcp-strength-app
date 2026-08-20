import { assertEquals } from "jsr:@std/assert@1";
import {
  getExerciseProgress,
  getExerciseProgressInput,
} from "./getExerciseProgress.ts";
import { clientWith } from "./testSupport.ts";

const benchId = "22222222-2222-2222-2222-222222222222";
const cableId = "66666666-6666-6666-6666-666666666666";
const machineId = "77777777-7777-7777-7777-777777777777";
const workoutId = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const olderId = "cccccccc-cccc-cccc-cccc-cccccccccccc";
const unfinishedId = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
const slotId = "11111111-1111-1111-1111-111111111111";
const olderSlot = "44444444-4444-4444-4444-444444444444";
const liveSlot = "88888888-8888-8888-8888-888888888888";

const db = {
  exercises: [
    {
      id: benchId,
      name: "Bench Press (Barbell)",
      aliases: ["bench"],
      body_part: "chest",
      secondary_body_parts: [],
      category: "barbell",
    },
    {
      id: cableId,
      name: "Lat Pulldown (Cable)",
      aliases: [],
      body_part: "back",
      secondary_body_parts: [],
      category: "machineOther",
    },
    {
      id: machineId,
      name: "Lat Pulldown (Machine)",
      aliases: [],
      body_part: "back",
      secondary_body_parts: [],
      category: "machineOther",
    },
    {
      id: "deadlift-id-0000-0000-000000000001",
      name: "Deadlift",
      aliases: [],
      body_part: "back",
      secondary_body_parts: ["legs"],
      category: "barbell",
    },
  ],
  workouts: [
    {
      id: workoutId,
      name: "Push Day",
      template_id: null,
      started_at: "2026-08-18T18:00:00.000Z",
      completed_at: "2026-08-18T19:10:00.000Z",
      duration_seconds: 4200,
      note: "focus on tempo",
      summary: "slept badly, everything felt heavy",
      total_volume: 3054.3,
      deleted_at: null,
    },
    {
      id: olderId,
      name: "Push Day",
      template_id: null,
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
      name: "Live",
      template_id: null,
      started_at: "2026-08-20T12:00:00.000Z",
      completed_at: null,
      duration_seconds: 0,
      note: "still going",
      summary: null,
      total_volume: 0,
      deleted_at: null,
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
      id: olderSlot,
      workout_id: olderId,
      exercise_id: benchId,
      sort_order: 0,
      superset_group_id: null,
      note: null,
      sticky_note: null,
      deleted_at: null,
    },
    {
      id: liveSlot,
      workout_id: unfinishedId,
      exercise_id: benchId,
      sort_order: 0,
      superset_group_id: null,
      note: "must not appear",
      sticky_note: null,
      deleted_at: null,
    },
  ],
  workout_sets: [
    {
      id: "33333333-3333-3333-3333-333333333333",
      workout_exercise_id: slotId,
      sort_order: 0,
      set_type: "dropSet",
      weight: 61.235,
      reps: 5,
      rpe: 9,
      distance: null,
      duration_seconds: null,
      rest_seconds: 150,
      is_completed: true,
      deleted_at: null,
    },
    {
      id: "55555555-5555-5555-5555-555555555555",
      workout_exercise_id: olderSlot,
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
    {
      id: "00000000-0000-0000-0000-000000000001",
      workout_exercise_id: liveSlot,
      sort_order: 0,
      set_type: "normal",
      weight: 80,
      reps: 5,
      rpe: null,
      distance: null,
      duration_seconds: null,
      rest_seconds: 90,
      is_completed: false,
      deleted_at: null,
    },
  ],
};

type ProgressPayload = {
  exercise: {
    id: string;
    name: string;
    secondary_body_parts: string[];
  } | null;
  sessions: Array<{
    workout_id: string;
    workout_note: string | null;
    summary: string | null;
    note: string | null;
    sticky_note: string | null;
    sets: Array<{
      set_type: string;
      weight: number | null;
      weight_unit: string;
    }>;
  }>;
  ambiguous: boolean;
  candidates: Array<{ id: string; name: string }>;
  truncated: boolean;
};

Deno.test("returns the session summary and both exercise notes", async () => {
  const result = await getExerciseProgress(clientWith(db), {
    exercise_id: benchId,
  });
  assertEquals(result.isError, undefined);
  const payload = result.structuredContent as ProgressPayload;
  assertEquals(payload.exercise?.name, "Bench Press (Barbell)");
  assertEquals(payload.sessions.map((s) => s.workout_id), [workoutId, olderId]);
  assertEquals(payload.sessions[0].summary, "slept badly, everything felt heavy");
  assertEquals(payload.sessions[0].workout_note, "focus on tempo");
  assertEquals(payload.sessions[0].note, "elbows tucked");
  assertEquals(payload.sessions[0].sticky_note, "stop one short of failure");
  assertEquals(payload.sessions[0].sets[0].set_type, "dropSet");
  assertEquals(payload.sessions[0].sets[0].weight_unit, "kg");
});

Deno.test("an unfinished session is not progress", async () => {
  const result = await getExerciseProgress(clientWith(db), {
    exercise_id: benchId,
  });
  const payload = result.structuredContent as ProgressPayload;
  assertEquals(
    payload.sessions.some((s) => s.workout_id === unfinishedId),
    false,
  );
});

Deno.test("ambiguous library names return candidates and no series", async () => {
  const result = await getExerciseProgress(clientWith(db), {
    exercise_name: "Lat Pulldown",
  });
  assertEquals(result.isError, undefined);
  const payload = result.structuredContent as ProgressPayload;
  assertEquals(payload.ambiguous, true);
  assertEquals(payload.sessions.length, 0);
  assertEquals(
    payload.candidates.map((c) => c.name).sort(),
    ["Lat Pulldown (Cable)", "Lat Pulldown (Machine)"],
  );
});

Deno.test("a unique name resolves and a missing id names the id", async () => {
  const hit = await getExerciseProgress(clientWith(db), {
    exercise_name: "Bench Press (Barbell)",
  });
  const payload = hit.structuredContent as ProgressPayload;
  assertEquals(payload.ambiguous, false);
  assertEquals(payload.exercise?.id, benchId);
  assertEquals(payload.sessions.length, 2);

  const miss = await getExerciseProgress(clientWith(db), {
    exercise_id: "ffffffff-ffff-ffff-ffff-ffffffffffff",
  });
  assertEquals(miss.isError, true);
  assertEquals(
    miss.content[0].text.includes("ffffffff-ffff-ffff-ffff-ffffffffffff"),
    true,
  );
});

Deno.test("unknown fields and a missing selector are rejected", () => {
  assertEquals(
    getExerciseProgressInput.safeParse({ extra: true }).success,
    false,
  );
});

Deno.test("supplying neither id nor name is a tool error", async () => {
  const result = await getExerciseProgress(clientWith(db), {});
  assertEquals(result.isError, true);
});
