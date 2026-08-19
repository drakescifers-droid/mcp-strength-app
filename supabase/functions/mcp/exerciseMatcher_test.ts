import { assertEquals } from "jsr:@std/assert@1";
import { rank, score, suggest } from "./exerciseMatcher.ts";
import type { BodyPart, ExerciseCategory, LibraryExercise } from "./types.ts";

function make(
  name: string,
  bodyPart: BodyPart,
  opts: {
    aliases?: string[];
    category?: ExerciseCategory;
    id?: string;
    secondaryBodyParts?: BodyPart[];
  } = {},
): LibraryExercise {
  return {
    id: opts.id ?? name,
    name,
    aliases: opts.aliases ?? [],
    bodyPart,
    secondaryBodyParts: opts.secondaryBodyParts ?? [],
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
      secondaryBodyParts: ["legs"],
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

Deno.test("legs hint does not filter out Barbell Row, filed under back only", () => {
  const results = rank("Row", "legs", library());
  assertEquals(results.some((r) => r.name === "Barbell Row"), true);
});

// Deadlift's secondaryBodyParts carries "legs" (docs/01-data-model.md §
// Secondary body parts), so a legs hint should BOOST it, not just fail to
// hide it — the stronger claim the case above doesn't make.
Deno.test("legs hint boosts Deadlift via its secondary body part", () => {
  const deadlift = library().find((e) => e.name === "Deadlift")!;
  const unhinted = score("Deadlift", null, deadlift);
  const hinted = score("Deadlift", "legs", deadlift);
  assertEquals(hinted.total > unhinted.total, true);
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
