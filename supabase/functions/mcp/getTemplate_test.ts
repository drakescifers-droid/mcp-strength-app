import { assertEquals } from "jsr:@std/assert@1";
import type { SupabaseClient } from "npm:@supabase/supabase-js";
import { getTemplate, getTemplateInput } from "./getTemplate.ts";

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

function clientWith(db: Record<string, Row[]>): SupabaseClient {
  return {
    from(table: string) {
      return new Query(db[table] ?? []);
    },
  } as unknown as SupabaseClient;
}

const templateId = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const folderId = "dddddddd-dddd-dddd-dddd-dddddddddddd";
const slotId = "11111111-1111-1111-1111-111111111111";
const benchId = "22222222-2222-2222-2222-222222222222";
const setId = "33333333-3333-3333-3333-333333333333";

const db = {
  templates: [
    {
      id: templateId,
      name: "Push Day",
      folder_id: folderId,
      note: "Film the last set",
      sort_order: 0,
      last_performed_at: null,
      deleted_at: null,
    },
  ],
  template_folders: [
    {
      id: folderId,
      name: "Upper",
      kind: "folder",
      sort_order: 0,
      deleted_at: null,
    },
  ],
  template_exercises: [
    {
      id: slotId,
      template_id: templateId,
      exercise_id: benchId,
      sort_order: 0,
      superset_group_id: null,
      note: "elbows tucked",
      sticky_note: "stop one short of failure",
      default_rest_seconds: 150,
      deleted_at: null,
    },
    {
      id: "99999999-9999-9999-9999-999999999999",
      template_id: templateId,
      exercise_id: benchId,
      sort_order: 1,
      superset_group_id: null,
      note: "tombstone",
      sticky_note: null,
      default_rest_seconds: 90,
      deleted_at: "2026-08-01T00:00:00Z",
    },
  ],
  template_sets: [
    {
      id: setId,
      template_exercise_id: slotId,
      sort_order: 0,
      set_type: "dropSet",
      weight: 60,
      reps: null,
      rep_range_start: 6,
      rep_range_end: 8,
      rpe: 8,
      distance: null,
      duration_seconds: null,
      rest_seconds: 150,
      deleted_at: null,
    },
  ],
  exercises: [
    {
      id: benchId,
      name: "Bench Press (Barbell)",
      body_part: "chest",
      category: "barbell",
    },
  ],
};

Deno.test("returns notes, sticky notes, and kilograms", async () => {
  const result = await getTemplate(clientWith(db), { id: templateId });
  assertEquals(result.isError, undefined);
  const template = result.structuredContent?.template as {
    note: string | null;
    weight_unit: string;
    exercises: Array<{
      note: string | null;
      sticky_note: string | null;
      exercise_name: string | null;
      sets: Array<{
        set_type: string;
        weight: number | null;
        weight_unit: string;
        rpe: number | null;
        rep_range_start: number | null;
      }>;
    }>;
  };
  assertEquals(template.note, "Film the last set");
  assertEquals(template.weight_unit, "kg");
  assertEquals(template.exercises.length, 1);
  assertEquals(template.exercises[0].note, "elbows tucked");
  assertEquals(template.exercises[0].sticky_note, "stop one short of failure");
  assertEquals(template.exercises[0].exercise_name, "Bench Press (Barbell)");
  assertEquals(template.exercises[0].sets[0].set_type, "dropSet");
  assertEquals(template.exercises[0].sets[0].weight, 60);
  assertEquals(template.exercises[0].sets[0].weight_unit, "kg");
  assertEquals(template.exercises[0].sets[0].rpe, 8);
  assertEquals(template.exercises[0].sets[0].rep_range_start, 6);
});

Deno.test("a missing id is a tool error that names the id", async () => {
  const result = await getTemplate(clientWith(db), {
    id: "ffffffff-ffff-ffff-ffff-ffffffffffff",
  });
  assertEquals(result.isError, true);
  assertEquals(result.content[0].text.includes("ffffffff-ffff-ffff-ffff-ffffffffffff"), true);
});

Deno.test("unknown fields and name lookups are rejected", () => {
  assertEquals(getTemplateInput.safeParse({ id: templateId, name: "Push" }).success, false);
  assertEquals(getTemplateInput.safeParse({ name: "Push" }).success, false);
});
