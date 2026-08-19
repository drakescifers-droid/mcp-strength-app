// Forwards mcp.mcpstrength.com to the Supabase MCP Edge Function.
// Claude's connector URL must match MCP_RESOURCE_URL on that function.
// Do not serve HTML here — the Allow page is the Pages site on the apex.

const ORIGIN = "https://knrmembtnmgddzyyvyvq.supabase.co/functions/v1/mcp";

export default {
  async fetch(request) {
    const incoming = new URL(request.url);
    let path = incoming.pathname;
    if (path === "/.well-known/oauth-protected-resource") {
      path = "/oauth-protected-resource";
    }
    if (path === "/") path = "";

    const headers = new Headers(request.headers);
    headers.delete("host");

    const init = {
      method: request.method,
      headers,
      redirect: "manual",
    };
    if (request.method !== "GET" && request.method !== "HEAD") {
      init.body = request.body;
    }

    return fetch(ORIGIN + path + incoming.search, init);
  },
};
