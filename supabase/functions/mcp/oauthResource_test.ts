import { assertEquals } from "jsr:@std/assert@1";
import {
  isMetadataPath,
  mcpResourceUrl,
  unauthorizedResponse,
} from "./oauthResource.ts";

Deno.test("metadata path is recognised with and without a function prefix", () => {
  assertEquals(
    isMetadataPath("https://example.supabase.co/functions/v1/mcp/oauth-protected-resource"),
    true,
  );
  assertEquals(
    isMetadataPath("https://example.supabase.co/functions/v1/mcp"),
    false,
  );
  assertEquals(
    isMetadataPath("http://example.supabase.co/mcp/oauth-protected-resource"),
    true,
  );
});

Deno.test("MCP_RESOURCE_URL wins over the rewritten request URL Edge Functions see", () => {
  Deno.env.set(
    "MCP_RESOURCE_URL",
    "https://example.supabase.co/functions/v1/mcp",
  );
  try {
    assertEquals(
      mcpResourceUrl("http://example.supabase.co/mcp/oauth-protected-resource"),
      "https://example.supabase.co/functions/v1/mcp",
    );
  } finally {
    Deno.env.delete("MCP_RESOURCE_URL");
  }
});

Deno.test("a supabase.co SUPABASE_URL becomes the public https functions path", () => {
  Deno.env.set("SUPABASE_URL", "http://knrmembtnmgddzyyvyvq.supabase.co");
  try {
    assertEquals(
      mcpResourceUrl("http://knrmembtnmgddzyyvyvq.supabase.co/mcp"),
      "https://knrmembtnmgddzyyvyvq.supabase.co/functions/v1/mcp",
    );
  } finally {
    Deno.env.delete("SUPABASE_URL");
  }
});

Deno.test("a custom-domain MCP_RESOURCE_URL advertises metadata on that host", () => {
  Deno.env.set("MCP_RESOURCE_URL", "https://mcp.mcpstrength.com");
  try {
    assertEquals(
      mcpResourceUrl("http://example.supabase.co/mcp"),
      "https://mcp.mcpstrength.com",
    );
    const response = unauthorizedResponse("http://example.supabase.co/mcp");
    const header = response.headers.get("WWW-Authenticate") ?? "";
    assertEquals(
      header.includes(
        'resource_metadata="https://mcp.mcpstrength.com/oauth-protected-resource"',
      ),
      true,
    );
  } finally {
    Deno.env.delete("MCP_RESOURCE_URL");
  }
});

Deno.test("unauthenticated response is 401 with a resource_metadata pointer", () => {
  Deno.env.set(
    "MCP_RESOURCE_URL",
    "https://example.supabase.co/functions/v1/mcp",
  );
  try {
    const response = unauthorizedResponse("http://example.supabase.co/mcp");
    assertEquals(response.status, 401);
    const header = response.headers.get("WWW-Authenticate") ?? "";
    assertEquals(
      header.includes(
        'resource_metadata="https://example.supabase.co/functions/v1/mcp/oauth-protected-resource"',
      ),
      true,
    );
  } finally {
    Deno.env.delete("MCP_RESOURCE_URL");
  }
});
