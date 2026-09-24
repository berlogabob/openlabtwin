# Idea hub: design

Date: 2026-09-24. Status: approved in chat.

## Why

Students have project ideas and nowhere to put them. A QR code leads to a simple form. A local language model (ornith) turns each idea into a normalised version with keywords, and links students with **similar** or **complementary** ideas: one student's "I'm looking for" meeting another's "I can bring". The ideas form a bank for lab workshops, help Andrey support students on their ideas, and join each student's lab history (identifiable, kept, staff-only, per the 2026-09-24 decision).

## Decisions (user, 2026-09-24)

| Topic | Decision |
|---|---|
| Visibility | Staff see everything. A student sees their own idea, plus matches between approved ideas as the AI title and a first name. Contact details are shared only after **both** students tap "I'd like to connect". |
| AI host | the lab edge node (MX Linux PC). The Ollama address and model come from settings: ornith if the PC can run it, otherwise a smaller model or the Mac's Ollama. Nothing leaves the lab. |
| Review | Students see the AI's normalised version straight away. Matches appear only after staff approve the idea. |
| Form | name, email, optional student number, the idea, an optional link, "I can bring" and "I'm looking for" (both optional) |
| Database | stays on Supabase cloud. A fully local setup is a possible later project (Postgres + PostgREST without Docker, a tunnel), if the PC and network allow. |

## Student flow

1. The QR leads to `…/openlabtwin/ideas/`. The student fills in the form and sees the notice line "Your idea is saved in your lab history, visible to lab staff only; matched students see its title and your first name."
2. **Send** gives a private link, `…/ideas/status/?t=<token>`. It works anywhere, because the page is on GitHub Pages and the data comes from Supabase.
3. The status page shows:
   - their idea;
   - "processing…" until the AI is done, then the AI title, summary and keywords;
   - once approved, the matches: title, first name, similar or complementary, and a one-line reason. Each match has **I'd like to connect**. When both sides have tapped it, the other's email and link are shown;
   - **Book a consultation about this**, which opens `/book/?project=<the idea>` with the project prefilled.

## Staff flow (office)

- **Ideas** screen (bulb icon): tabs for new, approved and archived, with a keyword filter.
- An idea shows:
  - the original fields and the student's link;
  - the AI title, summary and keywords, which staff can edit;
  - the student's lab history;
  - the suggested matches with scores.
- Actions:
  - **Approve** (matchable);
  - **Archive**;
  - **Workshop** (a flag for the workshop bank);
  - **Reprocess** (clears the AI fields so the job runs again).

## Data (migration)

- `create extension if not exists vector` (pgvector, provided by Supabase).
- `ideas`:
  - `id`, `person_id → people`, `body`, `link`, `can_bring`, `looking_for`;
  - `status` (new | approved | archived), `workshop bool`, `status_token uuid unique`, `created_at`;
  - `ai_title`, `ai_summary`, `ai_keywords text[]`, `ai_model`, `ai_done_at`;
  - `embedding vector(768)` (summary), `bring_embedding vector(768)`, `need_embedding vector(768)`.
  - Staff RLS, audited, no anon grants.
- `idea_matches`:
  - `idea_a < idea_b`, `kind` (similar | complementary), `score`, `reason`, `a_connect bool`, `b_connect bool`;
  - primary key `(idea_a, idea_b, kind)`.
  - Staff RLS, audited.

## Public functions (security definer, granted to anon and authenticated)

- **`submit_idea(p_name, p_email, p_body, p_link, p_can_bring, p_looking_for, p_student_number, p_website) → uuid`**
  - The same guards as `request_consultation`: honeypot, name and email rules, link `http(s)`, student number format.
  - The body must be 10–4000 characters; "can bring" and "looking for" at most 500 each.
  - At most 5 ideas per email in 24 hours.
  - It files the student under `people` by email.
- **`idea_status(p_token uuid) → json`**
  - The student's own idea: body, link, can_bring, looking_for, status, AI title, summary and keywords, and `processed`.
  - For an approved idea, the matches with other **approved** ideas: `match_id`, kind, reason, the other's AI title, the other's first name (the first word of `people.name`), `i_connected`, `they_connected`, and `contact {email, link}` only when both have connected.
- **`idea_connect(p_token uuid, p_other bigint) → void`**: sets the caller's side of the match between their idea and the other idea. Valid only when both ideas are approved.

## AI job: `scripts/ideas_ai.py` (edge node, every 15 min)

- **Settings** from `.env`: `OLLAMA_URL` (default `http://localhost:11434`), `IDEAS_MODEL` (default `ornith-1.5:9b`), `EMBED_MODEL` (default `nomic-embed-text`).
- **For each idea with `ai_done_at is null`:**
  1. The chat model gets a fixed prompt, with `format: json`, returning `{"title", "summary", "keywords"}`. The title is at most 8 words, the summary 1–3 sentences in English, the keywords 3–8 lowercase. If the reply isn't valid JSON, it retries once and otherwise skips until the next run.
  2. It embeds `summary`, `can_bring` and `looking_for`.
  3. It writes the AI fields.
- **Matching** (every run, for approved ideas):
  - *similar* = cosine(summary, summary) ≥ 0.75;
  - *complementary* = max(cosine(A.need, B.bring), cosine(B.need, A.bring)) ≥ 0.6.
  - It keeps the top 5 per idea and each kind, and upserts `idea_matches` without touching the existing `*_connect` flags.
  - The reason is a template: "similar topic: shared keywords x, y", or "A is looking for what B can bring".
  - The thresholds are constants, to tune on real data.
- The matching maths is pure Python and tested with fake vectors.
- **Cron line** on the edge node: `*/15 * * * * … scripts/ideas_ai.py`. `edge-setup.sh` gains the Ollama install and model pulls, sized by RAM (ornith needs about 8 GB free; otherwise it tells you to set `IDEAS_MODEL` or `OLLAMA_URL`).

## Tests

- **pgTAP (`05_ideas.test.sql`):**
  - anon can execute the three functions and read no table;
  - submit creates a new idea and one person per email;
  - the daily limit and the honeypot work;
  - status shows the student's own fields, and no matches before approval;
  - after approval, a match shows the title and first name but no contact;
  - after both connect, the contact appears;
  - connecting to an unapproved idea is refused.
- **Python:** cosine, thresholds, top-k, reason templates, JSON parsing and retry, using fake vectors and a fake Ollama.
- **Site (`dart test`):** form checks and the status view model.
- **Browser (live database):**
  1. two ideas are submitted;
  2. the AI step runs with a fake model writing deterministic vectors;
  3. both are approved;
  4. the match shows with no contact;
  5. both connect, and the contact shows;
  6. the test rows are removed.

## Out of scope

- A public idea wall and ideas on the TV (the TV showcase project).
- Emails to students.
- Editing an idea after sending.
- AI-written match reasons (templates first).
