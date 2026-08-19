import { assertEquals } from "jsr:@std/assert@1";
import type { SupabaseClient } from "npm:@supabase/supabase-js";
import { getTemplates, getTemplatesInput } from "./getTemplates.ts";

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

const pushId = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const pullId = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
const extraId = "cccccccc-cccc-cccc-cccc-cccccccccccc";
const folderId = "dddddddd-dddd-dddd-dddd-dddddddddddd";

const db = {
  templates: [
    {
      id: pushId,
      name: "Push Day",
      folder_id: folderId,
      note: "Elbows tucked",
      sort_order: 0,
      last_performed_at: null,
      deleted_at: null,
    },
    {
      id: pullId,
      name: "Pull Day",
      folder_id: folderId,
      note: null,
      sort_order: 1,
      last_performed_at: "2026-08-18T12:00:00Z",
      deleted_at: null,
    },
    {
      id: extraId,
      name: "Push Day",
      folder_id: null,
      note: "Unfiled duplicate name",
      sort_order: 0,
      last_performed_at: null,
      deleted_at: null,
    },
    {
      id: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",
      name: "Gone",
      folder_id: null,
      note: null,
      sort_order: 0,
      last_performed_at: null,
      deleted_at: "2026-08-01T00:00:00Z",
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
    { id: "ex1", template_id: pushId, deleted_at: null },
    { id: "ex2", template_id: pushId, deleted_at: null },
    { id: "ex3", template_id: pushId, deleted_at: "2026-08-01T00:00:00Z" },
    { id: "ex4", template_id: pullId, deleted_at: null },
  ],
};

Deno.test("lists live templates and keeps the template note", async () => {
  const result = await getTemplates(clientWith(db), {});
  const templates = result.structuredContent?.templates as Array<{
    id: string;
    name: string;
    note: string | null;
    exercise_count: number;
    folder_name: string | null;
  }>;
  assertEquals(result.isError, undefined);
  assertEquals(templates.map((t) => t.name), ["Push Day", "Push Day", "Pull Day"]);
  assertEquals(templates.some((t) => t.name === "Gone"), false);
  const filedPush = templates.find((t) => t.id === pushId)!;
  assertEquals(filedPush.note, "Elbows tucked");
  assertEquals(filedPush.folder_name, "Upper");
  assertEquals(filedPush.exercise_count, 2);
});

Deno.test("id lookup misses are a tool error, not an empty success", async () => {
  const result = await getTemplates(clientWith(db), {
    id: "ffffffff-ffff-ffff-ffff-ffffffffffff",
  });
  assertEquals(result.isError, true);
  assertEquals(result.content[0].text.includes("ffffffff-ffff-ffff-ffff-ffffffffffff"), true);
});

Deno.test("duplicate names return candidates and do not pick one", async () => {
  const result = await getTemplates(clientWith(db), { name: "Push Day" });
  const payload = result.structuredContent as {
    ambiguous: boolean;
    templates: Array<{ id: string }>;
  };
  assertEquals(payload.ambiguous, true);
  assertEquals(payload.templates.map((t) => t.id).sort(), [pushId, extraId].sort());
});

Deno.test("unknown fields are rejected by the input schema", () => {
  const parsed = getTemplatesInput.safeParse({ name: "Push", extra: true });
  assertEquals(parsed.success, false);
});
