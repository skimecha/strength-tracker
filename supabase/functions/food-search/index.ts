// food-search — searches USDA FoodData Central + Open Food Facts and returns
// a normalized list of foods. All macros are returned PER 100g, plus an
// optional servingGrams when the source provides a sensible serving size.
//
// Deploy:  supabase functions deploy food-search
// Secret:  USDA_API_KEY (free key from https://fdc.nal.usda.gov/api-key-signup.html)
//          If unset, USDA is skipped and only Open Food Facts is used.

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

const n = (v: unknown) => {
  const x = Number(v);
  return Number.isFinite(x) ? x : 0;
};
const r1 = (x: number) => Math.round(x * 10) / 10;

// USDA: per-100g macros via nutrientNumber (208 kcal, 203 protein, 204 fat, 205 carb)
async function searchUSDA(q: string) {
  const key = Deno.env.get("USDA_API_KEY");
  if (!key) return [];
  try {
    const res = await fetch(
      `https://api.nal.usda.gov/fdc/v1/foods/search?api_key=${key}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          query: q,
          pageSize: 15,
          dataType: ["Foundation", "SR Legacy", "Branded"],
        }),
      },
    );
    if (!res.ok) return [];
    const data = await res.json();
    const pick = (f: any, num: string) => {
      const hit = (f.foodNutrients || []).find(
        (x: any) => String(x.nutrientNumber) === num,
      );
      return hit ? n(hit.value) : 0;
    };
    return (data.foods || [])
      .map((f: any) => {
        const grams =
          /^g/i.test(f.servingSizeUnit || "") && f.servingSize
            ? n(f.servingSize)
            : 0;
        return {
          source: "USDA",
          name: (f.description || "").trim(),
          brand: (f.brandName || f.brandOwner || "").trim(),
          calories: r1(pick(f, "208")),
          protein: r1(pick(f, "203")),
          carbs: r1(pick(f, "205")),
          fat: r1(pick(f, "204")),
          servingGrams: grams,
        };
      })
      .filter((x: any) => x.name && x.calories > 0);
  } catch {
    return [];
  }
}

// Open Food Facts: per-100g macros from nutriments
async function searchOFF(q: string) {
  try {
    const url =
      `https://world.openfoodfacts.org/cgi/search.pl?search_terms=${
        encodeURIComponent(q)
      }&search_simple=1&action=process&json=1&page_size=15` +
      `&fields=product_name,brands,nutriments,serving_quantity`;
    const res = await fetch(url, {
      headers: { "User-Agent": "LockInStrength/1.0 (food search)" },
    });
    if (!res.ok) return [];
    const data = await res.json();
    return (data.products || [])
      .map((p: any) => {
        const nut = p.nutriments || {};
        return {
          source: "OFF",
          name: (p.product_name || "").trim(),
          brand: (p.brands || "").split(",")[0].trim(),
          calories: r1(n(nut["energy-kcal_100g"])),
          protein: r1(n(nut["proteins_100g"])),
          carbs: r1(n(nut["carbohydrates_100g"])),
          fat: r1(n(nut["fat_100g"])),
          servingGrams: n(p.serving_quantity),
        };
      })
      .filter((x: any) => x.name && x.calories > 0);
  } catch {
    return [];
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  try {
    const { q } = await req.json();
    const query = String(q || "").trim();
    if (query.length < 2) return json({ results: [] });

    const [usda, off] = await Promise.all([
      searchUSDA(query),
      searchOFF(query),
    ]);

    // USDA first (more authoritative), then OFF; dedupe by name+brand.
    const seen = new Set<string>();
    const results = [...usda, ...off]
      .filter((x) => {
        const k = (x.name + "|" + x.brand).toLowerCase();
        if (seen.has(k)) return false;
        seen.add(k);
        return true;
      })
      .slice(0, 24);

    return json({ results });
  } catch (e) {
    return json({ error: (e as Error)?.message || "Search failed", results: [] }, 500);
  }
});
