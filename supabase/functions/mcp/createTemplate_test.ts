import { assertEquals } from "jsr:@std/assert@1";
import type { SupabaseClient } from "npm:@supabase/supabase-js";
import { createTemplate } from "./createTemplate.ts";

type Row = Record<string, unknown>;

class Query {
  rows: Row[];
  constructor(rows: Row[]) {
    this.rows = rows.slice();
  }
  select() {
    return this;
  }
  is(column: string, value: unknown) {
    this.rows = this.rows.filter((row) => (row[column] ?? null) === value);
    return this;
  }
  eq(column: string, value: unknown) {
    this.rows = this.rows.filter((row) => row[column] === value);
    return this;
  }
  in(column: string, values: unknown[]) {
    const allowed = new Set(values);
    this.rows = this.rows.filter((row) => allowed.has(row[column]));
    return this;
  }
  then(
    onFulfilled?: (value: { data: Row[]; error: null }) => unknown,
    onRejected?: (reason: unknown) => unknown,
  ) {
    return Promise.resolve({ data: this.rows, error: null }).then(
      onFulfilled,
      onRejected,
    );
  }
}

function clientWith(
  db: Record<string, Row[]>,
  inserted: Array<{ table: string; rows: Row[] }>,
): SupabaseClient {
  return {
    from(table: string) {
      return {
        select() {
          return new Query(db[table] ?? []);
        },
        insert(payload: Row | Row[]) {
          const rows = Array.isArray(payload) ? payload : [payload];
          inserted.push({ table, rows });
          db[table] = [...(db[table] ?? []), ...rows];
          return Promise.resolve({ data: rows, error: null });
        },
        update() {
          const chain = {
            in() {
              return chain;
            },
            eq() {
              return chain;
            },
            is() {
              return chain;
            },
            then(
              onFulfilled?: (value: { error: null }) => unknown,
              onRejected?: (reason: unknown) => unknown,
            ) {
              return Promise.resolve({ error: null }).then(
                onFulfilled,
                onRejected,
              );
            },
          };
          return chain;
        },
      };
    },
  } as unknown as SupabaseClient;
}

const library = [
  {
    id: "fly",
    name: "Chest Fly (Machine)",
    aliases: ["pec deck"],
    body_part: "chest",
    category: "machineOther",
    deleted_at: null,
  },
];

Deno.test("a unique match inserts the template and does not create an exercise", async () => {
  const inserted: Array<{ table: string; rows: Row[] }> = [];
  const result = await createTemplate(
    clientWith({ templates: [], exercises: library, template_exercises: [], template_sets: [] }, inserted),
    "user-1",
    {
      name: "Push Day",
      weight_unit: "lbs",
      exercises: [{
        exercise_name: "Pec Deck",
        sticky_note: "stop one short",
        sets: [{ weight: 100, reps: 12 }],
      }],
    },
  );
  assertEquals(result.isError, undefined);
  assertEquals(result.structuredContent?.created, true);
  assertEquals(inserted.some((item) => item.table === "exercises"), false);
  assertEquals(inserted.some((item) => item.table === "templates"), true);
  assertEquals(inserted.some((item) => item.table === "template_exercises"), true);
  assertEquals(inserted.some((item) => item.table === "template_sets"), true);
  const set = inserted.find((item) => item.table === "template_sets")!.rows[0];
  assertEquals(typeof set.weight, "number");
  assertEquals(set.weight === 100, false);
});

Deno.test("a name collision writes nothing and returns the existing id", async () => {
  const inserted: Array<{ table: string; rows: Row[] }> = [];
  const existingId = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
  const result = await createTemplate(
    clientWith({
      templates: [{
        id: existingId,
        name: "Push Day",
        folder_id: null,
        sort_order: 0,
        deleted_at: null,
      }],
      exercises: library,
    }, inserted),
    "user-1",
    {
      name: "Push Day",
      exercises: [{ exercise_id: "fly", set_count: 3, reps: 8 }],
    },
  );
  assertEquals(result.isError, true);
  assertEquals(result.structuredContent?.existing_id, existingId);
  assertEquals(inserted.length, 0);
});
