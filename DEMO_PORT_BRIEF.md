# Demo Port Brief — Strength Tracker

> **INSTRUCTION (read first):** Update this demo per the Port Brief below. First
> audit the current demo (its version, how it seeds/persists sample data, what's
> already present) and post a short plan of exactly which items you'll port and
> skip. Wait for my go-ahead before editing. The brief's **PORT** items are in
> scope; **EXCLUDE** items must NOT be added. Exact live code is in the public
> repo `github.com/skimecha/strength-tracker` (single file: `index.html`). The
> changes land in this demo repo (`skimecha/strength-demo`).

**Purpose:** Update the backend-free public demo (`github.com/skimecha/strength-demo`, served on mattbreckenridge.com) to reflect functional changes made to the live app since it was forked (~v2.9.3). The demo runs with **no backend**: localStorage replaces Supabase, there is no auth/login, it boots straight into the app pre-seeded with generated sample data, and branding is neutral "Strength Tracker". **Preserve all of that.** Source of truth for the live code is the public repo `github.com/skimecha/strength-tracker` (single file: `index.html`).

---

## 1. VERSION

- **Live app current:** `APP_VERSION = '2.11.3'`, latest `main` commit **`878465b14f2ab874cb5bb2b2a9231e3b4e94f2a2`**.
- **Demo fork point:** ~**v2.9.3** (commit `f99bfbe`, "tap calorie total to toggle remaining/over goal"). If the demo predates that, treat the calorie-toggle (below) as also needing porting; if it's at/after v2.9.3 it may already have it.
- **Releases since the fork:** v2.10.0 → v2.11.3. Net user-facing deltas are in §2. Each live release bumps `APP_VERSION` in `index.html` **and** the cache name in `sw.js` together — do the equivalent in the demo at the end.

---

## 2. FUNCTIONAL CHANGELOG (since ~v2.9.3)

Port the items marked **PORT**. Skip the items marked **EXCLUDE** (they require a backend/account and contradict the demo's purpose — see §5).

| Feature | Disposition | What it does / how to reach it | Implementing functions in `index.html` |
|---|---|---|---|
| **Calorie total toggle** (v2.9.3) | PORT (verify if present) | On **Nutrition** tab, tapping the big "Today's Totals" calorie number toggles between calories *consumed* and calories *remaining* (shows amber "over your goal" when exceeded). | Inline in `renderNutrition()` — an `onclick` that flips `state.calorieDisplay` between `'total'` and `'remaining'`, then `render()`. |
| **Toggle-bar collapse fix** (v2.10.2) | PORT | CSS bug fix: the segmented toggle bars (Workouts/Records, Log/Chart, List/Chart) collapsed to a 2px sliver in scrolling views. | CSS rule `.toggle-group` gains `flex-shrink:0`; the two chart period-selector rows (inline `style="display:flex;...overflow-x:auto..."`) also get `flex-shrink:0`. |
| **Nav icons refresh** (v2.10.3–2.10.5) | PORT | Bottom-nav glyphs changed: **Workout** = spoked 45lb weight plate, **Nutrition** = drumstick, **Weight** = bathroom scale (replacing old dumbbell/clock/sun). | `iconPlate()` (renamed from `iconDumbbell()`), `iconNutrition()`, `iconScale()`; referenced in `renderNav()` — update the `log` tab to call `iconPlate()`. Exact SVGs in §8. |
| **Remove Decline Bench Press** (v2.10.6) | PORT | "Decline Bench Press - Barbell" and "- Dumbell" removed from the Chest exercise picker. | `EXERCISES['Chest']` array (see §8 for the exact resulting array). |
| **Dark/Light theme toggle** (v2.11.1) | PORT | **More → Appearance** card with 🌙 Dark / ☀️ Light segmented toggle. Persists across reloads; updates mobile address-bar color. | `setTheme(t)`; `state.theme`; CSS `html.light{…}` variable overrides; toggle markup in `renderMore()` using `data-theme` attributes; wired in `attachEvents()` via `querySelectorAll('[data-theme]')`; applied at startup by calling `setTheme(state.theme)` before app init. CSS block in §8. |
| **"+ Log Set" button emphasis** (v2.11.3) | PORT | The set-logging button is now the filled accent (primary) style so it stands out; hierarchy is blue = log set, green = finish, red = cancel. | In `renderSets()`, button `#log-set` class changed `btn-outline` → `btn-primary`. |
| **Support prompt text** (v2.11.3) | PORT (string only) | Support card copy now reads: *"Have a question, suggestion, or found a bug? Let us know."* | `renderMore()` support card `<div>`. |
| **Service worker → network-first** (v2.10.1) | PORT (adapt) | `sw.js` serves page navigations network-first (latest shell online, cached fallback offline) so deploys stop serving a stale app. | `sw.js` `fetch` handler. Apply the same strategy to the demo's own `sw.js`; keep the demo's own cache name. |
| **Food search in Add Food** (v2.11.0) | EXCLUDE / STUB | Search box in the Add Food modal that queries USDA + Open Food Facts and auto-fills macros. **Requires a backend Edge Function.** | `foodSearch(q)`, `showAddFoodModal()`, `esc()`. See §4/§5 for stub guidance. |
| **Invite-only registration + QR/share** (v2.10.0) | EXCLUDE | Invite landing page, invite codes, QR codes, "Manage Invites" in More. Owner/Supabase only; antithetical to a no-login demo. | `renderAuth('invite')`, `redeemInvite()`, `showInvitesModal()`, `dbCreateInviteCode()`, `dbLoadInviteCodes()`, `genInviteCode()`, `shareInvite()`, `inviteLink()`, `inviteQR()`, `isOwner()`. **Do not port.** |
| **Demo-mode removal** (v2.11.2) | N/A | The live app removed its old in-app "demo mode"/demo-account code. The standalone demo doesn't have that anyway. **Do not** pull in the invite-only login that replaced it. | — |

---

## 3. DATA MODEL CHANGES (most important — demo seeds & persists to localStorage)

**Persisted record shapes are UNCHANGED since the fork.** Sessions, food log, weight log, macro goals, meal favorites, exercise favorites, and custom exercises all keep their existing structures. For reference, the shapes the demo must keep seeding:

```js
// session
{ id: "uuid", date: 1718000000000 /* ms epoch */, exercises: [
    { muscle: "Chest", name: "Bench Press - Barbell",
      sets: [ { type: "warmup"|"working", weight: 135, reps: 10 } ] },        // strength
    { type: "cardio", name: "Running", duration: 1800 /* sec */,
      distance: 3.1, distUnit: "mi", heartRate: 150 }                          // cardio (check ex.type first)
] }

// food_log entry  (date is LOCALE TEXT, not ms)
{ id: "uuid", date: "6/16/2026", ts: 1718000000000, name: "Chicken breast",
  calories: 165, protein: 31, carbs: 0, fat: 3.6 }

// weight_log entry
{ id: "uuid", date: 1718000000000 /* ms */, value: 178.4, unit: "lbs" }       // or "kg"

// macro_goals  (single object)
{ calories: 2500, protein: 180, carbs: 250, fat: 80 }
```

**NEW in-memory `state` fields to add:**

```js
state.calorieDisplay = 'total';   // 'total' | 'remaining'  — UI only, NOT persisted (v2.9.3)
state.theme = localStorage.getItem('li_theme') || 'dark';   // 'dark' | 'light'  (v2.11.1)
```

- **New localStorage key:** `li_theme` = `'dark'` | `'light'`. (Existing key `li_weight_unit` is unchanged.) The theme is the only new persisted value.
- `state.calorieDisplay` is transient (resets to `'total'` on load) — do **not** persist it.

**NEW transient shape — food-search result** (only relevant if you stub search per §5). The search returns macros **per 100g**:

```js
{ source: "USDA"|"OFF", name: "Chicken breast, raw", brand: "",
  calories: 165, protein: 31, carbs: 0, fat: 3.6, servingGrams: 0 }
```
Tapping a result fills the Add Food fields and an **Amount (g)** input (`#f-grams`); the macros scale by `grams/100`. The **saved** `food_log` entry is still the unchanged shape above (absolute values) — no schema change to persisted data.

**NEW Supabase tables (live only — EXCLUDE from demo, listed for completeness):**

```
invite_codes(code PK, label, max_uses int, used_count int, expires_at, created_by uuid, created_at)
invite_redemptions(id, code, user_id uuid, email, redeemed_at)
```
The demo has no auth and no invites — **omit both entirely.**

---

## 4. BACKEND / INTEGRATION TOUCHPOINTS introduced since the fork

The demo has no backend, so each of these must be removed or stubbed. (All are gated to EXCLUDE/STUB features above.)

1. **`POST {SUPABASE_URL}/functions/v1/food-search`** — called by `foodSearch(q)`.
   - Sends: headers `apikey` + `Authorization: Bearer <anon key>`, body `{"q":"chicken"}`.
   - Returns: `{"results":[ <per-100g food objects, shape in §3> ]}`.
   - **Demo action:** replace `foodSearch()` with a local stub (canned array) or hide the search box (see §5).

2. **`POST {SUPABASE_URL}/functions/v1/redeem-invite`** — called by `redeemInvite()` (EXCLUDE entirely; invites aren't in the demo).

3. **`https://api.qrserver.com/v1/create-qr-code/?...&data=<invite link>`** — external image API used by the invite manager (`inviteQR()`) to render QR codes. EXCLUDE (invite-only).

4. **All `sb.from('invite_codes')` / `sb.from('invite_redemptions')` calls** and `isOwner()` gating — EXCLUDE.

5. Pre-existing (already handled in the demo, just don't reintroduce): the Supabase JS SDK `<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2">` and `createClient(...)`. The demo should have **no** Supabase client at all.

No other new external/network/CDN dependencies were introduced by the **PORT** features — theme, icons, calorie toggle, exercise-list edit, log-set styling, and support text are all pure client-side/CSS.

---

## 5. DEMO-UNFRIENDLY FEATURES & recommended demo behavior

- **Invite-only registration / invite codes / QR / "Manage Invites"** → **Omit entirely.** Requires a real account, Supabase RLS, and the owner UUID. None of it makes sense with no login. Do not port any `invite*`, `redeemInvite`, `showInvitesModal`, or the owner-gated More card.
- **Food search** (Add Food modal) → **Recommended: stub it offline.** Two options:
  - *Simplest:* hide the `#f-search` box and its results container; keep the manual Add Food fields (name + Amount + macros). Fully offline, nothing breaks.
  - *Nicer for a portfolio:* keep the search UI but replace `foodSearch(q)` with a local function that filters a small canned array (e.g. chicken breast, white rice, egg, banana, greek yogurt, almonds — each with per-100g macros and a `servingGrams`) and returns matches. This showcases the feature with zero network. Either way, the **Amount (g) → macro scaling** and the saved entry shape stay as in §3.
- **Google sign-in / any auth** → not present in the demo; do not introduce. (`handleGoogleAuth()` references `lockinstrength.com` — exclude.)
- **Service worker** → network-first is fine offline (it falls back to cache); safe to port, but keep the demo's own cache name and never point it at the live origin.

---

## 6. SECRETS / PRIVATE IDENTIFIERS TO STRIP (must NOT appear in the public demo)

These live in the app's config/feature code. The demo should contain **none** of them. Grep the demo after porting to be sure nothing rode along:

- `SUPABASE_URL = 'https://htatrfchehxgravtjpez.supabase.co'` — live project URL. **Remove.**
- `SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIs…'` — the live Supabase **anon JWT** (long `eyJ…` string). **Remove the whole constant.**
- `OWNER_UID = '031a65ed-f52d-4a67-b271-47778e920c22'` — the owner's real user UUID (used only by invite gating). **Remove.**
- Any `createClient(...)` / `const sb = …` Supabase client init. **Remove.**
- Edge Function URLs (`/functions/v1/food-search`, `/functions/v1/redeem-invite`) — **Remove/stub.**
- The OAuth redirect literal `https://lockinstrength.com` inside `handleGoogleAuth()` — **Remove** (auth excluded).

(There are no demo passwords or account credentials in the current live code — those were already deleted upstream — but confirm none exist in the demo either.)

---

## 7. BRANDING TO NEUTRALIZE → "Strength Tracker"

Good news: **the PORT features introduce no new "Lock In" branding.** Icons, calorie toggle, theme toggle, log-set styling, exercise-list edit, and the support-text change contain none. So a correct port adds nothing new to neutralize.

The "Lock In: Strength" / `lockinstrength.com` / `🔒` / `lockinstrength@gmail.com` strings that exist in the live app are concentrated in:
- the **invite/auth screens and invite share text** (e.g. `"Lock In: Strength"`, `"Join Lock In"`, `"Lock In is invite-only"`, `"You're invited to Lock In: Strength 🔒💪"`) — these are all in **EXCLUDE** features, so they never enter the demo if you skip invites/auth as directed.
- pre-existing **Privacy Policy / Terms of Service** modal text and the **support email** `lockinstrength@gmail.com` — these predate the fork; the demo should already show neutral copy. **Verify** the demo's policy/support strings are still "Strength Tracker" with no live email/domain, but no change is required by this update.

**Net:** if you port only the §2 PORT items and exclude the rest, no new branding cleanup is needed — just re-verify nothing in §6 leaked in.

---

## 8. EXACT SNIPPETS (copy-ready)

**Nav icon SVGs** (replace the three icon functions; update `renderNav()` so the Workout tab calls `iconPlate()`):

```js
function iconPlate(){ return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="6"/><circle cx="12" cy="12" r="2"/><line x1="13.4" y1="10.6" x2="16.2" y2="7.8"/><line x1="10.6" y1="10.6" x2="7.8" y2="7.8"/><line x1="13.4" y1="13.4" x2="16.2" y2="16.2"/><line x1="10.6" y1="13.4" x2="7.8" y2="16.2"/></svg>`; }
function iconNutrition(){ return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15.45 15.4c-2.13.65-4.3.32-5.7-1.1-2.29-2.27-1.76-6.5 1.17-9.42 2.93-2.93 7.15-3.46 9.42-1.17 1.41 1.41 1.74 3.57 1.1 5.71-1.4-.51-3.26-.02-4.64 1.36-1.38 1.38-1.87 3.23-1.35 4.62z"/><path d="m11.25 15.6-2.16 2.16a2.5 2.5 0 1 1-4.56 1.73 2.49 2.49 0 0 1-1.41-4.24 2.5 2.5 0 0 1 3.14-.32l2.16-2.16"/></svg>`; }
function iconScale(){ return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="3"/><path d="M7 13a5 5 0 0 1 10 0"/><path d="M12 13l-2.2-3"/><circle cx="12" cy="13" r=".6" fill="currentColor" stroke="none"/></svg>`; }
```

**Light theme CSS** (add directly after the existing `:root{…}` variables block; apply via `document.documentElement.classList.toggle('light', …)`):

```css
html.light{
  --bg:#f4f6fb;--surface:#ffffff;--surface2:#eef1f7;--border:#d8dde9;
  --text:#161922;--text-muted:#5b6478;
  --accent:#2f6fe0;--accent-dim:#dde9fd;
  --green:#1fa971;--green-dim:#d6f3e6;
  --amber:#c9780a;--amber-dim:#fbe9c8;
  --red:#dc4747;--red-dim:#fbdada;
}
```

**`setTheme` helper** (theme-color hex may differ if the demo uses a different dark `--bg`; match the demo's own values):

```js
function setTheme(t){
  const light = (t === 'light');
  state.theme = t;
  localStorage.setItem('li_theme', t);
  document.documentElement.classList.toggle('light', light);
  const m = document.querySelector('meta[name="theme-color"]');
  if (m) m.content = light ? '#f4f6fb' : '#0f1117';
}
// call setTheme(state.theme) once at startup, before first render
// wire toggle: document.querySelectorAll('[data-theme]').forEach(b => b.addEventListener('click', () => { setTheme(b.dataset.theme); render(); }));
```

**Chest exercise array after removing Decline Bench Press:**

```js
'Chest':['Bench Press - Barbell','Bench Press - Dumbell','Cable Fly','Chest Dip','Floor Press - Barbell','Incline Bench Press - Barbell','Incline Bench Press - Dumbell','Incline Fly - Dumbell','Machine Fly','Machine Press','Push-Up'],
```

**Service worker — network-first navigations** (adapt cache name to the demo's own):

```js
self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.mode === 'navigate') {
    e.respondWith(
      fetch(req).then(res => { const copy = res.clone(); caches.open(CACHE).then(c => c.put('./', copy)); return res; })
                .catch(() => caches.match('./').then(r => r || caches.match(req)))
    );
    return;
  }
  e.respondWith(caches.match(req).then(cached => cached || fetch(req)));
});
```

---

### Final step
After porting: bump the demo's `APP_VERSION` and its `sw.js` cache name together, and confirm — sample data still renders, no login appears, no network request is required to boot, all five tabs work, the theme toggle persists across reload, and a grep for the §6 strings returns nothing.
