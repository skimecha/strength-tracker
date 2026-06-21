// ai-macros — estimates nutrition macros for a food, with a shared cache.
//
// Two actions (POST body { action }):
//   "estimate" (default): look up the shared macro_cache FIRST; on a hit, scale
//       the stored per-unit density to the requested amount (no AI call). On a
//       miss, ask Claude (Sonnet 4.6) and return the estimate (NOT cached here).
//   "record": fold a USER-ACCEPTED entry into the cache via a running mean. The
//       client calls this when the user saves a food they used AI Macros for, so
//       the cache is always built from values a human actually accepted.
//
// Responses:
//   { type: "macros", calories, protein, carbs, fat, basis, assumptions, source }
//   { type: "clarify", question, options: [...], source: "ai" }
//   { ok: true }                         (record)
//
// The Anthropic API key lives here as a secret, never in the client.
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.
//
// Deploy:  supabase functions deploy ai-macros
// Secret:  ANTHROPIC_API_KEY  (from console.anthropic.com)
// SQL:     supabase/macro-cache-setup.sql  (creates macro_cache + RPC)

import { createClient } from "jsr:@supabase/supabase-js@2";

const MODEL = "claude-sonnet-4-6"; // accuracy upgrade; misses are rarer thanks to the cache

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

// ── Normalization & units ──────────────────────────────────────────────────
// Moderate, deterministic: lowercase, strip diacritics + punctuation, collapse
// whitespace. No stemming/de-pluralization (too error-prone to be safe).
const norm = (s: unknown) =>
  String(s || "")
    .toLowerCase()
    .normalize("NFKD").replace(/[\u0300-\u036f]/g, "") // strip combining diacritics
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .replace(/\s+/g, " ");

const WT: Record<string, number> = { g: 1, oz: 28.3495, lb: 453.592 };   // → grams
const VOL: Record<string, number> = { ml: 1, cup: 240, tbsp: 15, tsp: 5 }; // → ml

// Canonical base amount for a qty+unit, and the cache unit-class bucket.
function canon(unit: unknown, qty: number) {
  const u = String(unit || "units").toLowerCase();
  if (u in WT) return { cls: "wt", base: qty * WT[u] };   // grams
  if (u in VOL) return { cls: "vol", base: qty * VOL[u] }; // ml
  return { cls: "ct:" + u, base: qty };                    // count of items (units / slice / …)
}

const round5 = (v: number) => Math.round(v);              // calories → integer
const round2 = (v: number) => Math.round(v * 2) / 2;      // macros → nearest 0.5

const SYSTEM = `You estimate nutrition macros for foods a user logs in a fitness app. Given a food name, a quantity, and a unit, estimate Calories (kcal), Protein (g), Carbs (g), and Fat (g) for that exact amount, using well-established average nutrition data for commonly available preparations.

Unit handling:
- Weight/volume units (g, oz, lb, ml, cup, tbsp, tsp, slice): estimate for that exact amount.
- "units" means a count of average-sized items. "1 unit" of "Chicken Breast" = one average chicken breast; "5 units" of "Chicken Fingers" = five average chicken fingers. Scale by the count.

If the food is specific enough to estimate reasonably, call provide_macros with your best estimate. Put any assumptions (preparation, size, brand-agnostic average) in "assumptions", and a short human-readable "basis" describing the amount you priced (e.g. "5 average chicken fingers (~140 g)").

Only if the food name is genuinely ambiguous in a way that would swing the macros a lot (e.g. "chicken" could be breast/thigh/wing, "milk" could be whole/2%/skim) call ask_clarification with a short question and 2-5 concise options. Prefer to estimate whenever a reasonable default exists.

These are estimates: round calories to the nearest 5 and macros to the nearest 0.5 g.`;

const TOOLS = [
  {
    name: "provide_macros",
    description: "Provide the estimated macros for the given food and amount.",
    input_schema: {
      type: "object",
      properties: {
        calories: { type: "number", description: "Total calories (kcal) for the amount" },
        protein: { type: "number", description: "Total protein (g)" },
        carbs: { type: "number", description: "Total carbohydrates (g)" },
        fat: { type: "number", description: "Total fat (g)" },
        basis: { type: "string", description: "Short description of the amount priced, e.g. '5 average chicken fingers (~140 g)'" },
        assumptions: { type: "string", description: "Any assumptions made (preparation, size). May be empty." },
      },
      required: ["calories", "protein", "carbs", "fat", "basis"],
    },
  },
  {
    name: "ask_clarification",
    description: "Ask the user a short clarifying question when the food is too ambiguous to estimate well.",
    input_schema: {
      type: "object",
      properties: {
        question: { type: "string", description: "A short clarifying question" },
        options: { type: "array", items: { type: "string" }, description: "2-5 concise answer choices" },
      },
      required: ["question", "options"],
    },
  },
];

const num = (v: unknown) => { const n = Number(v); return Number.isFinite(n) ? n : 0; };

function admin() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const body = await req.json();
    const action = String(body.action || "estimate");
    const name = String(body.food || "").trim();
    if (!name) return json({ error: "Missing food name" }, 400);

    const qty = num(body.qty) || 1;
    const { cls, base } = canon(body.unit, qty);
    const foodKey = norm(name);
    const clarKey = norm(body.clarification);

    // ── record: fold a user-accepted entry into the running-mean cache ──────
    if (action === "record") {
      const cal = num(body.calories), pro = num(body.protein), carb = num(body.carbs), fat = num(body.fat);
      if (base <= 0 || cal <= 0) return json({ ok: true }); // nothing useful to learn

      const calP = cal / base, proP = pro / base, carbP = carb / base, fatP = fat / base;
      // Cheap sanity guard against unit mistakes for weight foods (e.g. "1 g" = 2000 cal):
      // nothing can exceed ~9 kcal/g or 1 g of a macro per gram of food.
      const bad = [calP, proP, carbP, fatP].some((x) => !Number.isFinite(x) || x < 0) ||
        (cls === "wt" && (calP > 9.5 || proP > 1.05 || carbP > 1.05 || fatP > 1.05));
      if (bad) return json({ ok: true });

      try {
        await admin().rpc("macro_cache_record", {
          p_food_key: foodKey, p_unit_class: cls, p_clar_key: clarKey,
          p_cal: calP, p_pro: proP, p_carb: carbP, p_fat: fatP,
          p_basis: String(body.basis || ""),
        });
      } catch (e) {
        console.error("macro_cache_record failed:", e);
      }
      return json({ ok: true });
    }

    // ── estimate: cache first, then AI on a miss ────────────────────────────
    if (base > 0) {
      try {
        const { data: row } = await admin()
          .from("macro_cache")
          .select("cal_per,pro_per,carb_per,fat_per,samples")
          .eq("food_key", foodKey).eq("unit_class", cls).eq("clar_key", clarKey)
          .maybeSingle();
        if (row) {
          return json({
            type: "macros",
            calories: round5(row.cal_per * base),
            protein: round2(row.pro_per * base),
            carbs: round2(row.carb_per * base),
            fat: round2(row.fat_per * base),
            basis: `From saved data (${row.samples} ${row.samples === 1 ? "entry" : "entries"})`,
            assumptions: "",
            source: "cache",
          });
        }
      } catch (e) {
        console.error("macro_cache lookup failed (falling back to AI):", e);
      }
    }

    const key = Deno.env.get("ANTHROPIC_API_KEY");
    if (!key) return json({ error: "AI not configured" }, 500);

    let userText = `Food: "${name}"\nAmount: ${qty} ${body.unit || "units"}`;
    if (body.clarification) userText += `\nAdditional detail: ${String(body.clarification).trim()}`;

    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": key,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: 512,
        system: SYSTEM,
        tools: TOOLS,
        tool_choice: { type: "any" },
        messages: [{ role: "user", content: userText }],
      }),
    });

    if (!res.ok) {
      const detail = await res.text();
      console.error("anthropic error", res.status, detail);
      return json({ error: "AI request failed" }, 502);
    }

    const data = await res.json();
    const tool = (data.content || []).find((b: any) => b.type === "tool_use");
    if (!tool) return json({ error: "No estimate returned" }, 502);

    if (tool.name === "ask_clarification") {
      const i = tool.input || {};
      return json({ type: "clarify", question: String(i.question || ""), options: Array.isArray(i.options) ? i.options.slice(0, 5).map(String) : [], source: "ai" });
    }

    const i = tool.input || {};
    return json({
      type: "macros",
      calories: round5(num(i.calories)),
      protein: round2(num(i.protein)),
      carbs: round2(num(i.carbs)),
      fat: round2(num(i.fat)),
      basis: String(i.basis || ""),
      assumptions: String(i.assumptions || ""),
      source: "ai",
    });
  } catch (e) {
    return json({ error: (e as Error)?.message || "Unexpected error" }, 500);
  }
});
