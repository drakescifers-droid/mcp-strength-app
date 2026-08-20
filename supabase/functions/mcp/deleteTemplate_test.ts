import { assertEquals } from "jsr:@std/assert@1";
import { deleteTemplate, deleteTemplateInput } from "./deleteTemplate.ts";
import { clientWith } from "./testSupport.ts";

const templateId = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const slotId = "11111111-1111-1111-1111-111111111111";
const setId = "33333333-3333-3333-3333-333333333333";
const workoutId = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
const dayId = "cccccccc-cccc-cccc-cccc-cccccccccccc";

function db() {
  return {
    templates: [
      {
        id: templateId,
        name: "Push Day",
        folder_id: "dddddddd-dddd-dddd-dddd-dddddddddddd",
        deleted_at: null,
      },
    ],
    template_exercises: [
      { id: slotId, template_id: templateId, deleted_at: null },
    ],
    template_sets: [
      { id: setId, template_exercise_id: slotId, deleted_at: null },
    ],
    workouts: [
      { id: workoutId, template_id: templateId, deleted_at: null },
    ],
    program_days: [
      {
        id: dayId,
        folder_id: "dddddddd-dddd-dddd-dddd-dddddddddddd",
        template_id: templateId,
        deleted_at: null,
      },
    ],
  };
}

Deno.test("tombstones the template and its sets, not history or program days", async () => {
  const data = db();
  const result = await deleteTemplate(clientWith(data), { id: templateId });
  assertEquals(result.isError, undefined);
  const payload = result.structuredContent as {
    deleted: boolean;
    already_deleted: boolean;
    name: string;
  };
  assertEquals(payload.deleted, true);
  assertEquals(payload.already_deleted, false);
  assertEquals(payload.name, "Push Day");
  assertEquals(typeof data.templates[0].deleted_at, "string");
  assertEquals(typeof data.template_exercises[0].deleted_at, "string");
  assertEquals(typeof data.template_sets[0].deleted_at, "string");
  assertEquals(data.workouts[0].deleted_at, null);
  assertEquals(data.program_days[0].deleted_at, null);
});

Deno.test("a second delete reports already_deleted rather than inventing a miss", async () => {
  const data = db();
  await deleteTemplate(clientWith(data), { id: templateId });
  const again = await deleteTemplate(clientWith(data), { id: templateId });
  assertEquals(again.isError, undefined);
  const payload = again.structuredContent as { already_deleted: boolean };
  assertEquals(payload.already_deleted, true);
});

Deno.test("a missing id is a tool error that names the id", async () => {
  const result = await deleteTemplate(clientWith(db()), {
    id: "ffffffff-ffff-ffff-ffff-ffffffffffff",
  });
  assertEquals(result.isError, true);
  assertEquals(
    result.content[0].text.includes("ffffffff-ffff-ffff-ffff-ffffffffffff"),
    true,
  );
});

Deno.test("name lookups and unknown fields are rejected", () => {
  assertEquals(
    deleteTemplateInput.safeParse({ name: "Push Day" }).success,
    false,
  );
  assertEquals(
    deleteTemplateInput.safeParse({ id: templateId, extra: true }).success,
    false,
  );
});
