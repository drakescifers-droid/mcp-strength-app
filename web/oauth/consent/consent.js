import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY } from "/config.js";

const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
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
  const { data, error } = await supabase.auth.oauth.getAuthorizationDetails(
    authorizationId,
  );
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
  document.getElementById("client-name").textContent =
    data.client?.name ?? "An AI assistant";
  document.getElementById("redirect-line").textContent = data.redirect_uri
    ? "After you allow it, you'll return to " + data.redirect_uri
    : "";
  const scopes = (data.scope || "").trim().split(/\s+/).filter(Boolean);
  const scopesBox = document.getElementById("scopes");
  if (scopes.length) {
    scopesBox.innerHTML = "<p>Requested:</p><ul>" +
      scopes.map((s) => "<li>" + s + "</li>").join("") + "</ul>";
  }
}

if (!authorizationId) {
  status.textContent =
    "Open this page from Claude’s Connect flow. There is nothing to approve on its own.";
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
  const { data, error } = await supabase.auth.oauth.approveAuthorization(
    authorizationId,
  );
  if (error) {
    showError(error.message);
    return;
  }
  location.href = data.redirect_url;
});

document.getElementById("deny").addEventListener("click", async () => {
  const { data, error } = await supabase.auth.oauth.denyAuthorization(
    authorizationId,
  );
  if (error) {
    showError(error.message);
    return;
  }
  location.href = data.redirect_url;
});
