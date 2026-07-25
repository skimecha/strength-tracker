// redeem-invite — validates an invite code and creates the user account.
//
// This is the ONLY path to a new account: public sign-ups are disabled in the
// Supabase Auth settings, and the Admin API used here bypasses that toggle.
// All validation happens server-side with the service-role key, which the
// browser never sees.
//
// Deploy:  supabase functions deploy redeem-invite
// (SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.)

import { createClient } from "jsr:@supabase/supabase-js@2";

const OWNER_DEFAULTS = { calories: 2500, protein: 180, carbs: 250, fat: 80 };

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
    const { code, email, password } = await req.json();
    if (!code || !email || !password) {
      return json({ error: "Missing invite code, email, or password." }, 400);
    }
    if (String(password).length < 8) {
      return json({ error: "Password must be at least 8 characters." }, 400);
    }

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );

    // 1. Validate the code.
    const { data: inv, error: invErr } = await admin
      .from("invite_codes")
      .select("*")
      .eq("code", code)
      .maybeSingle();
    if (invErr) {
      console.error("invite_codes lookup failed:", invErr);
      return json({ error: "Could not verify invite.", detail: invErr.message }, 500);
    }
    if (!inv) return json({ error: "That invite code isn't valid." }, 403);
    if (inv.expires_at && new Date(inv.expires_at) < new Date()) {
      return json({ error: "This invite has expired." }, 403);
    }
    if (inv.used_count >= inv.max_uses) {
      return json({ error: "This invite has already been used up." }, 403);
    }

    // 2. Create the account (email pre-confirmed so there's no extra step).
    const { data: created, error: cErr } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
    if (cErr || !created?.user) {
      const msg = /already|exists|registered/i.test(cErr?.message || "")
        ? "An account with that email already exists — try signing in."
        : (cErr?.message || "Could not create account.");
      return json({ error: msg }, 400);
    }
    const uid = created.user.id;

    // 3. Seed profile + macro goals. The on_auth_user_created trigger does not
    //    fire for Admin-API-created users, so do it here (idempotent).
    //    Trainer invites grant the trainer role at creation.
    const role = inv.invite_type === "trainer" ? "trainer" : "user";
    await admin.from("profiles").upsert({ id: uid, email, role }, { onConflict: "id" });
    await admin.from("macro_goals").upsert(
      { user_id: uid, ...OWNER_DEFAULTS },
      { onConflict: "user_id" },
    );

    // 3b. Client invites carry the issuing trainer's id — auto-link on signup.
    //     The link is a revocable grant (see trainer-setup.sql); no data
    //     visibility is attached in Phase 1.
    if (inv.invite_type === "client" && inv.trainer_id) {
      await admin.from("trainer_clients").upsert(
        { trainer_id: inv.trainer_id, client_id: uid, status: "active" },
        { onConflict: "trainer_id,client_id" },
      );
    }

    // 4. Burn one use + record the redemption.
    await admin
      .from("invite_codes")
      .update({ used_count: inv.used_count + 1 })
      .eq("code", code);
    await admin
      .from("invite_redemptions")
      .insert({ code, user_id: uid, email });

    return json({ ok: true });
  } catch (e) {
    return json({ error: (e as Error)?.message || "Unexpected error." }, 500);
  }
});
