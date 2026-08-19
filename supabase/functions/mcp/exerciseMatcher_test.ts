import { assertEquals } from "jsr:@std/assert@1";
import { rank, suggest } from "./exerciseMatcher.ts";
import type { BodyPart, ExerciseCategory, LibraryExercise } from "./types.ts";

function make(
  name: string,
  bodyPart: BodyPart,
  opts: { aliases?: string[]; category?: ExerciseCategory; id?: string } = {},
): LibraryExercise {
  return {
    id: opts.id ?? name,
    name,
    aliases: opts.aliases ?? [],
    bodyPart,
    category: opts.category ?? "machineOther",
  };
}

function library(): LibraryExercise[] {
  return [
    make("Chest Fly (Machine)", "chest", { aliases: ["pec deck", "machine fly"] }),
    make("Leg Press", "legs"),
    make("Lateral Raise (Dumbbell)", "shoulders", { category: "dumbbell" }),
    make("Close Grip Bench Press", "arms", { category: "barbell" }),
    make("Deadlift", "back", {
      aliases: ["conventional deadlift"],
      category: "barbell",
    }),
    make("Barbell Row", "back", { aliases: ["row"], category: "barbell" }),
    make("Dumbbell Row", "back", { aliases: ["row"], category: "dumbbell" }),
    make("Seated Cable Row", "back", { aliases: ["row"] }),
  ];
}

Deno.test("dumbbell lateral raise ranks Lateral Raise (Dumbbell) first", () => {
  const results = rank("Dumbbell Lateral Raise", null, library());
  assertEquals(results[0]?.name, "Lateral Raise (Dumbbell)");
});

Deno.test("pec deck resolves to Chest Fly (Machine) via alias", () => {
  const results = rank("Pec Deck", null, library());
  assertEquals(results[0]?.name, "Chest Fly (Machine)");
});

Deno.test("JM Press with arms hint does not rank Leg Press first", () => {
  const results = rank("JM Press", "arms", library());
  assertEquals(results[0]?.name !== "Leg Press", true);
  assertEquals(results[0]?.name, "Close Grip Bench Press");
  assertEquals(results.some((r) => r.name === "Leg Press"), true);
});

Deno.test("legs hint does not filter out Deadlift filed under back", () => {
  const results = rank("Deadlift", "legs", library());
  assertEquals(results.some((r) => r.name === "Deadlift"), true);
});

Deno.test("ambiguous alias returns multiple candidates", () => {
  const results = rank("row", null, library());
  const names = new Set(results.map((r) => r.name));
  assertEquals(names.has("Barbell Row"), true);
  assertEquals(names.has("Dumbbell Row"), true);
  assertEquals(names.has("Seated Cable Row"), true);
  assertEquals(results.length >= 3, true);
});

Deno.test("nonsense query returns no confident match", () => {
  const results = suggest("Zyzzyva", null, library());
  assertEquals(results.length, 0);
});

Deno.test("empty query returns nothing", () => {
  const results = rank("   ", null, library());
  assertEquals(results.length, 0);
});

Deno.test("ties break by name deterministically", () => {
  const a = make("Alpha Press", "chest");
  const b = make("Beta Press", "chest");
  const results = rank("Press", null, [b, a]);
  assertEquals(results.map((r) => r.name), ["Alpha Press", "Beta Press"]);
});
