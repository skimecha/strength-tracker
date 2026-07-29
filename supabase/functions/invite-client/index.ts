// invite-client — a trainer enters a client's email; we create the client's
// account immediately (linked to the trainer) and Supabase Auth emails the
// client a link to set their password. The trainer can start working right
// away; the client owns the account from the moment they set a password.
//
// Consent guard: this only works for NEW emails. If the email already has an
// account, we refuse — linking an existing account requires the client's own
// consent (ROADMAP Phase 4 request/accept flow).
//
// Caller must be a trainer: we verify the caller's JWT and check profiles.role.
//
// Deploy:  supabase functions deploy invite-client
// (SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY auto-injected.
//  Uses Supabase Auth's built-in invite mailer — configure custom SMTP in
//  Auth settings for real volume; the built-in mailer is heavily rate-limited.)

import { createClient } from "jsr:@supabase/supabase-js@2";

const DEFAULT_GOALS = { calories: 2500, protein: 180, carbs: 250, fat: 80 };
const APP_URL = "https://lockinstrength.com";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const { email } = await req.json();
    const target = String(email || "").trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(target)) {
      return json({ error: "Enter a valid email address." }, 400);
    }

    // Identify the caller from their JWT (the app sends the session token).
    const authHeader = req.headers.get("Authorization") || "";
    const caller = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } }, auth: { persistSession: false } },
    );
    const { data: { user } } = await caller.auth.getUser();
    if (!user) return json({ error: "Not signed in." }, 401);

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );

    // Only trainers may invite clients.
    const { data: prof } = await admin.from("profiles").select("role").eq("id", user.id).maybeSingle();
    if (!prof || prof.role !== "trainer") {
      return json({ error: "Only trainers can add clients." }, 403);
    }

    // Create the account + send the set-password invite email in one step.
    // Fails cleanly if the email is already registered (consent guard).
    const { data: invited, error: invErr } = await admin.auth.admin.inviteUserByEmail(
      target,
      { redirectTo: APP_URL },
    );
    if (invErr || !invited?.user) {
      const exists = /already|registered|exists/i.test(invErr?.message || "");
      return json({
        error: exists
          ? "That email already has an account. Linking existing accounts is coming soon — for now, share an invite code with them instead."
          : (invErr?.message || "Could not send the invite."),
      }, exists ? 409 : 500);
    }
    const uid = invited.user.id;

    // Seed profile + goals (invited users skip the normal signup trigger path),
    // then link them to the calling trainer.
    await admin.from("profiles").upsert({ id: uid, email: target, role: "user" }, { onConflict: "id" });
    await admin.from("macro_goals").upsert({ user_id: uid, ...DEFAULT_GOALS }, { onConflict: "user_id" });
    await admin.from("trainer_clients").upsert(
      { trainer_id: user.id, client_id: uid, status: "active" },
      { onConflict: "trainer_id,client_id" },
    );

    return json({ ok: true, email: target });
  } catch (e) {
    return json({ error: (e as Error)?.message || "Unexpected error." }, 500);
  }
});
