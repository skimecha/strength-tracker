# Lock In: Strength — Roadmap

*Living document. Updated as decisions are made. Last updated: 2026-07-22.*

## Direction

The next evolution forks the experience between **individual users** and **Trainers**.
Trainers onboard and coach clients inside the app; clients are full, sovereign
users who happen to be linked to a trainer. This is the coach/client wedge —
a defensible niche vs. consumer tracker incumbents.

**MVP is free and unmetered. No pricing considerations in the MVP.** Pilot with
trainers at the local gym to work out functionality and UX first.

## Core model (settled)

- **Owner** (app owner) — unchanged; Admin area stays owner-only.
- **Trainer** — a normal user account *plus* client management. Owner grants
  trainer status during the pilot (no self-serve). Trainers train themselves too:
  their home screen lists **My Training** first, then their clients.
- **Client** — a sovereign, normal account linked to a trainer.
  - The link is a **grant, never ownership**. Either side can sever it:
    trainer can remove a client; client can disconnect from their trainer.
  - Disconnect is **clean**: trainer access ends immediately and completely.
    The client's account and data (including assigned-plan history) persist.
  - One active trainer per client (link table keeps history).
- **Visibility is client-controlled.** In the client's settings, per-category
  toggles: Workouts (default on when linked) · Nutrition · Weight. Changeable
  anytime. The trainer sees only what's granted. (Nutrition visibility is the
  future on-ramp to meal-planning features.)
- **Plans guide; logging stays free.** A trainer-authored weekly plan renders in
  the client's app as guidance ("Assigned by …"); the client logs exactly like an
  individual user. This trains clients on the full app.

## Key technical risk

All tables today are RLS-locked to `auth.uid() = user_id`. Trainer→client
visibility introduces **delegated cross-account reads** via a `trainer_clients`
link + expanded RLS. This is where cross-account leaks happen; every phase that
touches RLS gets adversarial testing before it reaches real users.

## Phases

### Phase 1 — Roles & links (plumbing) — SHIPPED v2.26.0
*(SQL: `supabase/trainer-setup.sql`; Edge Function: redeploy `redeem-invite`.)*
- `profiles.role` / trainer flag (owner-granted).
- `trainer_clients` link table (trainer_id, client_id, status, timestamps).
- Invite generator gains a type: **Trainer** or **Client**. Client invites carry
  the issuing trainer's id; redemption auto-links.
- Trainer home screen: button grid (like Log Workout) — **My Training** first,
  then each client, then **+ Add Client** (via invite). Remove = severs link only.
- No data visibility yet. Prove the relationship plumbing end-to-end.

### Phase 2 — Consented visibility
- Client settings: "Your trainer" card — who's linked, per-category visibility
  toggles (Workouts / Nutrition / Weight), Disconnect button.
- RLS delegated **read-only** access for granted categories on active links.
- Trainer taps a client → read-only coaching view (sessions, PRs; nutrition/
  weight only if granted). No re-login; no state loss switching clients.
- **Adversarial RLS testing before release.**

### Phase 3 — Plans
- Trainer authors a weekly plan per client: days → exercises (existing library)
  → target sets×reps.
- Client sees it as a guide panel ("This week from …") alongside free logging.
- Plan history persists on the client's side after unlinking.

### Shipped early (v2.28.0): trainer adds client by email
Trainer enters a client's email in Add Client → account is created instantly
(linked, trainer can start immediately) → Supabase Auth emails a set-password
link (`invite-client` Edge Function, built-in mailer; configure custom SMTP for
volume). Consent guard: refuses emails that already have an account — linking
an existing account stays in Phase 4 (client consent required).

### Phase 4 — Client-initiated linking
- Client enters a trainer's email → uniform "Request sent" response
  (no email enumeration — never confirm whether an account exists).
- Existing trainer: in-app link request, trainer **accepts/declines** (consent
  both ways). Non-existent: pending link + invite to that email.
- First transactional email (e.g. Resend via edge function). A shareable-link
  variant ("send this to your trainer") can ship first with zero email infra.

### Ops — transactional email branding (before the gym pilot)
- **Custom SMTP** in Supabase Auth settings (e.g. Resend free tier) so invite /
  reset emails send from **@LockInStrength.com**, not @supabase — also lifts the
  built-in mailer's few-per-hour rate limit and improves deliverability.
  Requires DNS records (SPF/DKIM) on the domain.
- **Styled email templates** (Auth → Email Templates): Lock In branding and
  clearer messaging for Invite ("Your trainer set up your account…"),
  Confirm, and Password Reset emails.

### Later / parked
- **Meal planning** (builds on nutrition visibility).
- **Organization accounts** (gym-level): all trainers in an org can access org
  clients. Trigger to build: a gym owner wants to buy, or pilot trainers ask to
  cover each other's clients. Requires explicit client re-consent (granting an
  org ≠ granting a person) and an org admin role. `trainer_clients` extends with
  an org layer without rework.
- **Pricing** — flat fee per N active client seats; "first client free" as an
  ecosystem hook. Explicitly out of MVP scope; revisit after the pilot.
- Native wrapper (Capacitor) when a wall demands it: push notifications /
  re-engagement, HealthKit/Health Connect (pedometer), store distribution.

## Done (context for where the app is)
- Individual tracking: workouts (PRs, assisted exercises, lb/kg), nutrition
  (AI Macros with shared cache + label scan), bodyweight, weekly volume planning
  (hypertrophy/strength).
- Owner Admin area: user metrics, activity dashboard (windowed engagement),
  dev-note publishing, support-ticket triage.
- Durability: Resume no longer deletes sessions; in-progress workouts autosave.
- Live in-workout green volume bars stacked on weekly volume.
