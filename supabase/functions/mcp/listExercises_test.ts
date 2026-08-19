import { assertEquals } from "jsr:@std/assert@1";
import type { SupabaseClient } from "npm:@supabase/supabase-js";
import { listExercises } from "./listExercises.ts";

type Row = {
  id: string;
  name: string;
  aliases: string[];
  body_part: string;
  category: string;
  is_custom: boolean;
};

function clientWith(rows: Row[]): SupabaseClient {
  return {
    from() {
      return {
        select() {
          return {
            is() {
              return Promise.resolve({ data: rows, error: null });
            },
          };
        },
      };
    },
  } as unknown as SupabaseClient;
}

const library: Row[] = [
  {
    id: "1",
    name: "Bench Press",
    aliases: [],
    body_part: "chest",
    category: "barbell",
    is_custom: false,
  },
  {
    id: "2",
    name: "Leg Press",
    aliases: [],
    body_part: "legs",
    category: "machineOther",
    is_custom: false,
  },
  {
    id: "3",
    name: "Deadlift",
    aliases: [],
    body_part: "back",
    category: "barbell",
    is_custom: false,
  },
];

Deno.test("empty query lists the library, name-sorted", async () => {
  const result = await listExercises(clientWith(library), {});
  const names = (result.structuredContent?.exercises as Array<{ name: string }>)
    .map((e) => e.name);
  assertEquals(names, ["Bench Press", "Deadlift", "Leg Press"]);
});

Deno.test("category is a hard filter", async () => {
  const result = await listExercises(clientWith(library), { category: "barbell" });
  const names = (result.structuredContent?.exercises as Array<{ name: string }>)
    .map((e) => e.name);
  assertEquals(names, ["Bench Press", "Deadlift"]);
});

Deno.test("body_part hint does not drop Deadlift filed under back", async () => {
  const result = await listExercises(clientWith(library), {
    query: "Deadlift",
    body_part: "legs",
  });
  const names = (result.structuredContent?.exercises as Array<{ name: string }>)
    .map((e) => e.name);
  assertEquals(names.includes("Deadlift"), true);
});

Deno.test("unknown fields are rejected by the input schema, not listed as ignored", async () => {
  const { listExercisesInput } = await import("./listExercises.ts");
  const parsed = listExercisesInput.safeParse({ query: "squat", extra: true });
  assertEquals(parsed.success, false);
});
