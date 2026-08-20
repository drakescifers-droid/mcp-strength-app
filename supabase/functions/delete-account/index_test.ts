import { assertEquals } from "jsr:@std/assert@1";

function uncommented(source: string): string {
  return source
    .split("\n")
    .filter((line) => !line.trim().startsWith("//"))
    .join("\n");
}

Deno.test("delete-account requires a user JWT before using the service role", async () => {
  const source = uncommented(
    await Deno.readTextFile(new URL("./index.ts", import.meta.url)),
  );
  assertEquals(source.includes('auth: "user"'), true);
  assertEquals(source.includes("auth.admin.deleteUser"), true);
  assertEquals(source.includes("SUPABASE_SERVICE_ROLE_KEY"), true);
});
