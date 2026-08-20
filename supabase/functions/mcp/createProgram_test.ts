import { assertEquals } from "jsr:@std/assert@1";
import { createProgram, createProgramInput } from "./createProgram.ts";
import { clientWith } from "./testSupport.ts";

const pushId = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const pullId = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
const extraPush = "cccccccc-cccc-cccc-cccc-cccccccccccc";
const userId = "11111111-1111-1111-1111-111111111111";

function db() {
  return {
    template_folders: [
      {
        id: "dddddddd-dddd-dddd-dddd-dddddddddddd",
        name: "Odds and ends",
        kind: "folder",
        sort_order: 0,
        deleted_at: null,
      },
    ],
    templates: [
      {
        id: pushId,
        name: "Push Day",
        folder_id: null,
        deleted_at: null,
      },
      {
        id: pullId,
        name: "Pull Day",
        folder_id: null,
        deleted_at: null,
      },
      {
        id: extraPush,
        name: "Push Day",
        folder_id: null,
        deleted_at: null,
      },
    ],
    program_days: [] as Record<string, unknown>[],
  };
}

Deno.test("writes a program whose days may repeat a template", async () => {
  const data = db();
  const result = await createProgram(clientWith(data), userId, {
    name: "A/B Split",
    days: [
      { template_id: pushId, label: "A" },
      { template_id: pullId, label: "B" },
      { template_id: pushId, label: "A" },
    ],
  });
  assertEquals(result.isError, undefined);
  const payload = result.structuredContent as {
    created: boolean;
    program_id: string;
    days: Array<{ template_id: string; template_name: string; label: string | null }>;
    progression: { kind: string; executed: boolean };
  };
  assertEquals(payload.created, true);
  assertEquals(payload.days.map((d) => d.template_id), [pushId, pullId, pushId]);
  assertEquals(payload.days.map((d) => d.label), ["A", "B", "A"]);
  assertEquals(payload.progression.kind, "none");
  assertEquals(payload.progression.executed, false);
  assertEquals(data.template_folders.length, 2);
  assertEquals(data.template_folders[1].kind, "program");
  assertEquals(data.program_days.length, 3);
  assertEquals(data.templates[0].folder_id, payload.program_id);
  assertEquals(data.templates[1].folder_id, payload.program_id);
});

Deno.test("linear progression is recorded as prose and not executed", async () => {
  const data = db();
  const result = await createProgram(clientWith(data), userId, {
    name: "5/3/1",
    days: [{ template_id: pushId }],
    progression: { kind: "linear", add_weight: 5, weight_unit: "lbs" },
  });
  const payload = result.structuredContent as {
    progression: {
      kind: string;
      executed: boolean;
      note: string | null;
      add_weight: number | null;
    };
  };
  assertEquals(payload.progression.kind, "linear");
  assertEquals(payload.progression.executed, false);
  assertEquals(payload.progression.add_weight, 5);
  assertEquals(payload.progression.note?.includes("5 lbs"), true);
});

Deno.test("an ambiguous template name writes nothing", async () => {
  const data = db();
  const result = await createProgram(clientWith(data), userId, {
    name: "Push Pull",
    days: [{ template_name: "Push Day" }],
  });
  assertEquals(result.isError, true);
  assertEquals(data.template_folders.length, 1);
  assertEquals(data.program_days.length, 0);
});

Deno.test("a name collision returns the existing id", async () => {
  const data = db();
  const result = await createProgram(clientWith(data), userId, {
    name: "Odds and ends",
    days: [{ template_id: pushId }],
  });
  assertEquals(result.isError, true);
  const extra = result.structuredContent as { existing_id: string };
  assertEquals(extra.existing_id, "dddddddd-dddd-dddd-dddd-dddddddddddd");
  assertEquals(data.program_days.length, 0);
});

Deno.test("a missing template id writes nothing", async () => {
  const data = db();
  const result = await createProgram(clientWith(data), userId, {
    name: "Ghost",
    days: [{ template_id: "ffffffff-ffff-ffff-ffff-ffffffffffff" }],
  });
  assertEquals(result.isError, true);
  assertEquals(data.template_folders.length, 1);
});

Deno.test("drop_set-style unknown fields are rejected", () => {
  assertEquals(
    createProgramInput.safeParse({
      name: "X",
      days: [{ template_id: pushId, extra: true }],
    }).success,
    false,
  );
  assertEquals(
    createProgramInput.safeParse({
      name: "X",
      days: [],
    }).success,
    false,
  );
});
