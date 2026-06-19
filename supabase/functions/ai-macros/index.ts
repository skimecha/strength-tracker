// ai-macros — estimates nutrition macros for a food using Claude (Haiku 4.5).
//
// The Anthropic API key lives here as a secret, never in the client.
// Returns one of:
//   { type: "macros", calories, protein, carbs, fat, basis, assumptions }
//   { type: "clarify", question, options: [...] }
//
// Deploy:  supabase functions deploy ai-macros
// Secret:  ANTHROPIC_API_KEY  (from console.anthropic.com)

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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const key = Deno.env.get("ANTHROPIC_API_KEY");
  if (!key) return json({ error: "AI not configured" }, 500);

  try {
    const { food, qty, unit, clarification } = await req.json();
    const name = String(food || "").trim();
    if (!name) return json({ error: "Missing food name" }, 400);

    let userText = `Food: "${name}"\nAmount: ${qty || 1} ${unit || "units"}`;
    if (clarification) userText += `\nAdditional detail: ${String(clarification).trim()}`;

    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": key,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: "claude-haiku-4-5",
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
      return json({ type: "clarify", question: String(i.question || ""), options: Array.isArray(i.options) ? i.options.slice(0, 5).map(String) : [] });
    }

    const i = tool.input || {};
    const num = (v: unknown) => { const n = Number(v); return Number.isFinite(n) ? n : 0; };
    return json({
      type: "macros",
      calories: Math.round(num(i.calories)),
      protein: Math.round(num(i.protein) * 2) / 2,
      carbs: Math.round(num(i.carbs) * 2) / 2,
      fat: Math.round(num(i.fat) * 2) / 2,
      basis: String(i.basis || ""),
      assumptions: String(i.assumptions || ""),
    });
  } catch (e) {
    return json({ error: (e as Error)?.message || "Unexpected error" }, 500);
  }
});
