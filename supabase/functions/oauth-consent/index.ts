// Consent screen for connecting Claude (or any MCP client) to a user's
// account. Supabase Auth redirects here with ?authorization_id= after the
// OAuth authorize step. Site URL + this function name must equal that
// redirect — see docs/02-architecture.md § Phase 3.

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ??
  Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? "";

function htmlPage(): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Connect MCP Strength</title>
  <style>
    :root {
      --surface: #293137;
      --field: #1f252a;
      --accent: #35a7ff;
      --success: #2ecd70;
      --destructive: #ff5964;
      --text: #ffffff;
      --muted: #94989a;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: var(--surface);
      color: var(--text);
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 24px;
    }
    main {
      width: 100%;
      max-width: 420px;
    }
    h1 { font-size: 1.4rem; margin: 0 0 8px; }
    p { color: var(--muted); line-height: 1.45; }
    label { display: block; font-size: 0.85rem; color: var(--muted); margin: 12px 0 6px; }
    input {
      width: 100%;
      padding: 12px 14px;
      border: 0;
      border-radius: 10px;
      background: var(--field);
      color: var(--text);
      font-size: 1rem;
    }
    button {
      width: 100%;
      margin-top: 12px;
      padding: 14px;
      border: 0;
      border-radius: 10px;
      font-size: 1rem;
      font-weight: 600;
      cursor: pointer;
    }
    .approve { background: var(--accent); color: #082033; }
    .deny { background: transparent; color: var(--destructive); }
    .sign-in { background: var(--accent); color: #082033; }
    .error { color: var(--destructive); }
    .client { color: var(--text); margin: 16px 0; }
    .hidden { display: none; }
    ul { color: var(--muted); padding-left: 1.2em; }
  </style>
</head>
<body>
  <main>
    <h1>Connect to MCP Strength</h1>
    <p id="status">Loading…</p>
    <p id="error" class="error hidden"></p>

    <form id="login" class="hidden">
      <p>Sign in with the same email you use in the app. This lets Claude read and write <em>your</em> workouts — nobody else's.</p>
      <label for="email">Email</label>
      <input id="email" name="email" type="email" autocomplete="username" required />
      <label for="password">Password</label>
      <input id="password" name="password" type="password" autocomplete="current-password" required />
      <button class="sign-in" type="submit">Sign in</button>
    </form>

    <div id="consent" class="hidden">
      <div class="client">
        <p><strong id="client-name"></strong> wants access to your training data.</p>
        <p id="redirect-line"></p>
        <div id="scopes"></div>
      </div>
      <button class="approve" id="approve" type="button">Allow</button>
      <button class="deny" id="deny" type="button">Deny</button>
    </div>
  </main>
  <script type="module">
    import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

    const supabase = createClient(${JSON.stringify(supabaseUrl)}, ${JSON.stringify(supabaseAnonKey)});
    const params = new URLSearchParams(location.search);
    const authorizationId = params.get("authorization_id");
    const status = document.getElementById("status");
    const errorEl = document.getElementById("error");
    const login = document.getElementById("login");
    const consent = document.getElementById("consent");

    function showError(message) {
      errorEl.textContent = message;
      errorEl.classList.remove("hidden");
      status.textContent = "";
    }

    async function showConsent() {
      const { data, error } = await supabase.auth.oauth.getAuthorizationDetails(authorizationId);
      if (error || !data) {
        showError(error?.message || "This permission request is invalid or expired.");
        login.classList.add("hidden");
        return;
      }
      if (!("authorization_id" in data) && data.redirect_url) {
        location.href = data.redirect_url;
        return;
      }
      status.textContent = "";
      login.classList.add("hidden");
      consent.classList.remove("hidden");
      document.getElementById("client-name").textContent = data.client?.name ?? "An AI assistant";
      document.getElementById("redirect-line").textContent = data.redirect_uri
        ? "After you allow it, you'll return to " + data.redirect_uri
        : "";
      const scopes = (data.scope || "").trim().split(/\\s+/).filter(Boolean);
      const scopesBox = document.getElementById("scopes");
      if (scopes.length) {
        scopesBox.innerHTML = "<p>Requested:</p><ul>" +
          scopes.map((s) => "<li>" + s + "</li>").join("") + "</ul>";
      }
    }

    if (!authorizationId) {
      status.textContent = "Open this page from Claude's Connect flow. There is nothing to approve on its own.";
    } else {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) {
        status.textContent = "";
        login.classList.remove("hidden");
      } else {
        await showConsent();
      }
    }

    login.addEventListener("submit", async (event) => {
      event.preventDefault();
      errorEl.classList.add("hidden");
      const email = document.getElementById("email").value;
      const password = document.getElementById("password").value;
      const { error } = await supabase.auth.signInWithPassword({ email, password });
      if (error) {
        showError(error.message);
        return;
      }
      await showConsent();
    });

    document.getElementById("approve").addEventListener("click", async () => {
      const { data, error } = await supabase.auth.oauth.approveAuthorization(authorizationId);
      if (error) { showError(error.message); return; }
      location.href = data.redirect_url;
    });

    document.getElementById("deny").addEventListener("click", async () => {
      const { data, error } = await supabase.auth.oauth.denyAuthorization(authorizationId);
      if (error) { showError(error.message); return; }
      location.href = data.redirect_url;
    });
  </script>
</body>
</html>`;
}

Deno.serve((req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, content-type",
      },
    });
  }
  return new Response(htmlPage(), {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store",
    },
  });
});
