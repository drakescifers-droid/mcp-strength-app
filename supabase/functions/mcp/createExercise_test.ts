import { assertEquals } from "jsr:@std/assert@1";
import type { SupabaseClient } from "npm:@supabase/supabase-js";
import { createExercise, createExerciseInput } from "./createExercise.ts";

type Row = {
  id: string;
  name: string;
  aliases: string[];
  body_part: string;
  category: string;
  is_custom: boolean;
};

function clientWith(rows: Row[], inserted: unknown[] = []): SupabaseClient {
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
        insert(row: unknown) {
          inserted.push(row);
          return {
            select() {
              return {
                single() {
                  const r = row as Record<string, unknown>;
                  return Promise.resolve({
                    data: {
                      id: r.id,
                      name: r.name,
                      aliases: r.aliases,
                      body_part: r.body_part,
                      category: r.category,
                      is_custom: r.is_custom,
                    },
                    error: null,
                  });
                },
              };
            },
          };
        },
      };
    },
  } as unknown as SupabaseClient;
}

const library: Row[] = [
  {
    id: "fly",
    name: "Chest Fly (Machine)",
    aliases: ["pec deck", "machine fly"],
    body_part: "chest",
    category: "machineOther",
    is_custom: false,
  },
  {
    id: "bar-row",
    name: "Barbell Row",
    aliases: ["row"],
    body_part: "back",
    category: "barbell",
    is_custom: false,
  },
  {
    id: "db-row",
    name: "Dumbbell Row",
    aliases: ["row"],
    body_part: "back",
    category: "dumbbell",
    is_custom: false,
  },
];

Deno.test("pec deck returns the existing Chest Fly and does not insert", async () => {
  const inserted: unknown[] = [];
  const result = await createExercise(clientWith(library, inserted), "user-1", {
    name: "Pec Deck",
  });
  assertEquals(inserted.length, 0);
  assertEquals(result.structuredContent?.created, false);
  const exercise = result.structuredContent?.exercise as { name: string };
  assertEquals(exercise.name, "Chest Fly (Machine)");
  assertEquals(
    result.structuredContent?.matched_to_existing,
    ["Pec Deck -> Chest Fly (Machine)"],
  );
});

Deno.test("ambiguous alias writes nothing and returns candidates", async () => {
  const inserted: unknown[] = [];
  const result = await createExercise(clientWith(library, inserted), "user-1", {
    name: "row",
  });
  assertEquals(inserted.length, 0);
  assertEquals(result.structuredContent?.ambiguous, true);
  const candidates = result.structuredContent?.candidates as Array<{ name: string }>;
  assertEquals(candidates.length >= 2, true);
});

Deno.test("no match without body_part and category is a tool error, not a silent create", async () => {
  const inserted: unknown[] = [];
  const result = await createExercise(clientWith(library, inserted), "user-1", {
    name: "Jefferson Curl",
  });
  assertEquals(inserted.length, 0);
  assertEquals(result.isError, true);
});

Deno.test("no match with body_part and category inserts a custom row", async () => {
  const inserted: unknown[] = [];
  const result = await createExercise(clientWith(library, inserted), "user-1", {
    name: "Jefferson Curl",
    body_part: "core",
    category: "barbell",
  });
  assertEquals(inserted.length, 1);
  assertEquals(result.structuredContent?.created, true);
  const row = inserted[0] as { user_id: string; is_custom: boolean };
  assertEquals(row.user_id, "user-1");
  assertEquals(row.is_custom, true);
});

Deno.test("unknown fields are rejected", () => {
  const parsed = createExerciseInput.safeParse({
    name: "Squat",
    extra: true,
  });
  assertEquals(parsed.success, false);
});
