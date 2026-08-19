import { assertEquals } from "jsr:@std/assert@1";
import {
  buildTemplateRows,
  collisionInFolder,
  createTemplateInput,
} from "./templateWrite.ts";
import { kilogramsFrom, KILOGRAMS_PER_POUND } from "./types.ts";
import type { LibraryExercise } from "./types.ts";

const library: LibraryExercise[] = [
  {
    id: "bench",
    name: "Bench Press (Barbell)",
    aliases: [],
    bodyPart: "chest",
    category: "barbell",
  },
  {
    id: "fly",
    name: "Chest Fly (Machine)",
    aliases: ["pec deck"],
    bodyPart: "chest",
    category: "machineOther",
  },
  {
    id: "squat-bar",
    name: "Squat (Barbell)",
    aliases: ["squat"],
    bodyPart: "legs",
    category: "barbell",
  },
  {
    id: "front",
    name: "Front Squat (Barbell)",
    aliases: ["squat"],
    bodyPart: "legs",
    category: "barbell",
  },
];

const ids = ["t", "e1", "s1", "s2", "s3", "g1"];
function newId() {
  return ids.shift() ?? crypto.randomUUID();
}

Deno.test("135 lbs is stored as kilograms, matching WeightUnits.swift", () => {
  assertEquals(kilogramsFrom(135, "lbs"), 135 * KILOGRAMS_PER_POUND);
  assertEquals(kilogramsFrom(60, "kg"), 60);
});

Deno.test("pec deck matches Chest Fly and is not left as a new name", () => {
  const built = buildTemplateRows(
    {
      name: "Push",
      weight_unit: "lbs",
      exercises: [{
        exercise_name: "Pec Deck",
        note: "elbows tucked",
        sticky_note: "stop one short",
        sets: [{ weight: 100, reps: 10 }],
      }],
    },
    library,
    {
      userId: "user-1",
      templateId: "t",
      sortOrder: 0,
      now: "now",
      newId,
    },
  );
  if (!built.ok) throw new Error(built.content);
  assertEquals(built.exercises[0].exercise_id, "fly");
  assertEquals(built.exercises[0].note, "elbows tucked");
  assertEquals(built.exercises[0].sticky_note, "stop one short");
  assertEquals(built.matched_to_existing, ["Pec Deck -> Chest Fly (Machine)"]);
  assertEquals(built.sets[0].weight, 100 * KILOGRAMS_PER_POUND);
});

Deno.test("ambiguous squat writes nothing", () => {
  const built = buildTemplateRows(
    {
      name: "Legs",
      exercises: [{
        exercise_name: "Squat",
        set_count: 3,
        reps: 5,
      }],
    },
    library,
    {
      userId: "user-1",
      templateId: "t",
      sortOrder: 0,
      now: "now",
      newId: () => "x",
    },
  );
  assertEquals(built.ok, false);
  if (built.ok) return;
  assertEquals(built.reason, "unresolved_exercises");
  const unresolved = built.extra?.unresolved as Array<{ candidates: unknown[] }>;
  assertEquals(unresolved[0].candidates.length >= 2, true);
});

Deno.test("set_count+reps expands to that many normal sets", () => {
  const built = buildTemplateRows(
    {
      name: "Push",
      exercises: [{
        exercise_id: "bench",
        set_count: 3,
        reps: 5,
      }],
    },
    library,
    {
      userId: "user-1",
      templateId: "t",
      sortOrder: 0,
      now: "now",
      newId: () => crypto.randomUUID(),
    },
  );
  if (!built.ok) throw new Error(built.content);
  assertEquals(built.sets.length, 3);
  assertEquals(built.sets.every((set) => set.reps === 5 && set.set_type === "normal"), true);
});

Deno.test("weight without weight_unit is an error, not assumed pounds", () => {
  const built = buildTemplateRows(
    {
      name: "Push",
      exercises: [{
        exercise_id: "bench",
        sets: [{ weight: 135, reps: 5 }],
      }],
    },
    library,
    {
      userId: "user-1",
      templateId: "t",
      sortOrder: 0,
      now: "now",
      newId: () => "x",
    },
  );
  assertEquals(built.ok, false);
  if (built.ok) return;
  assertEquals(built.reason, "missing_weight_unit");
});

Deno.test("drop_set is rejected, not coerced to dropSet or normal", () => {
  const parsed = createTemplateInput.safeParse({
    name: "Push",
    weight_unit: "lbs",
    exercises: [{
      exercise_id: "bench",
      sets: [{ set_type: "drop_set", reps: 8 }],
    }],
  });
  assertEquals(parsed.success, false);
});

Deno.test("same name in the same folder collides; different folder does not", () => {
  const rows = [
    { id: "1", name: "Push Day", folder_id: null },
    { id: "2", name: "Push Day", folder_id: "folder" },
  ];
  assertEquals(collisionInFolder(rows, "Push Day", null)?.id, "1");
  assertEquals(collisionInFolder(rows, "Push Day", "folder")?.id, "2");
  assertEquals(collisionInFolder(rows, "Push Day", null, "1"), null);
});
