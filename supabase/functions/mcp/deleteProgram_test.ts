import { assertEquals } from "jsr:@std/assert@1";
import { deleteProgram, deleteProgramInput } from "./deleteProgram.ts";
import { clientWith } from "./testSupport.ts";

const programId = "dddddddd-dddd-dddd-dddd-dddddddddddd";
const folderId = "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee";
const templateId = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const dayId = "cccccccc-cccc-cccc-cccc-cccccccccccc";

function db() {
  return {
    template_folders: [
      {
        id: programId,
        name: "Upper/Lower",
        kind: "program",
        deleted_at: null,
      },
      {
        id: folderId,
        name: "Just a drawer",
        kind: "folder",
        deleted_at: null,
      },
    ],
    program_days: [
      {
        id: dayId,
        folder_id: programId,
        template_id: templateId,
        deleted_at: null,
      },
    ],
    templates: [
      {
        id: templateId,
        name: "Push Day",
        folder_id: programId,
        deleted_at: null,
      },
    ],
  };
}

Deno.test("tombstones the program and its days, not its templates", async () => {
  const data = db();
  const result = await deleteProgram(clientWith(data), { id: programId });
  assertEquals(result.isError, undefined);
  const payload = result.structuredContent as {
    deleted: boolean;
    templates_survived: number;
    name: string;
  };
  assertEquals(payload.deleted, true);
  assertEquals(payload.templates_survived, 1);
  assertEquals(payload.name, "Upper/Lower");
  assertEquals(typeof data.template_folders[0].deleted_at, "string");
  assertEquals(typeof data.program_days[0].deleted_at, "string");
  assertEquals(data.templates[0].deleted_at, null);
  assertEquals(data.templates[0].folder_id, programId);
});

Deno.test("a plain folder is refused, not deleted", async () => {
  const data = db();
  const result = await deleteProgram(clientWith(data), { id: folderId });
  assertEquals(result.isError, true);
  assertEquals(result.content[0].text.includes("not a program"), true);
  assertEquals(data.template_folders[1].deleted_at, null);
});

Deno.test("a missing id names the id", async () => {
  const result = await deleteProgram(clientWith(db()), {
    id: "ffffffff-ffff-ffff-ffff-ffffffffffff",
  });
  assertEquals(result.isError, true);
  assertEquals(
    result.content[0].text.includes("ffffffff-ffff-ffff-ffff-ffffffffffff"),
    true,
  );
});

Deno.test("name lookups are rejected", () => {
  assertEquals(
    deleteProgramInput.safeParse({ name: "Upper/Lower" }).success,
    false,
  );
});
