# Labs and the common TV

Goal: several TVs, one per lab (Tech Lab, 3D Lab, later Print Lab), plus a common kiosk TV that shows every lab's content and the institution-wide events. Nobody but the owner edits content; the remote labs' TVs reach it over GitHub Pages, so no shared network is needed. The university subdomain later is a DNS and Pages custom-domain change only.

Scope: A (labs, per-lab TVs) and B (common TV). Not here: C, Book me with a lab choice (own spec; reuses `labs`).

## URLs

- `/tv/`: common TV (all labs, institution-wide first, then one page per lab in turn). `?order=grouped`: all schedules first, then each lab's pages in turn.
- `/tv/<lab>/` (`techlab`, `3dlab`, later `print`): that lab's schedule column plus its pages and the institution-wide ones.
- `?room=` still overrides the schedule rooms. No `?lab=` filter, no multi-lab subsets (add when asked).
- GitHub Pages: `https://berlogabob.github.io/openlabtwin/tv/…`. Node (LAN): same paths, nginx serves the page for `^/tv/\w+/$`.

## Data

- Migration: table `labs(code text primary key, title text not null, rooms text[] not null default '{}')`, staff-only RLS, audited like `tv_slides`. Seed `techlab` (Lab. e Estudo de Jogos - Tech Lab (Oriente)) and `3dlab` (3 D Lab. (Oriente)). `print` is added later with one insert.
- Migration: `tv_slides.lab text references labs(code) on update cascade on delete set null`. Null = every TV. Existing slides stay null.
- `places.code` untouched.

## tv.py

- `build()` is unchanged; `main()` calls it per scope: for each lab with slides where `lab` is null or the code, and once for the common file.
- Output on the node: `tv.json` (= common, kept so the current Pi works), `tv/<code>.json` per lab; each file carries `rooms` (the lab's, or all labs' for common). Common slides carry `lab` (code or absent); `lab` joins `SLIDE_KEYS`.
- Common order (mix): institution-wide pages, then round-robin over labs by page. Round-robin is by page, not seconds, so a lab with long videos gets more time (`# ponytail:` comment; upgrade: a per-lab time budget).
- Public copy: `write_public` writes the same files into `~/tv-public` (`tv.json`, `tv/<code>.json`, `labs.json` with `[{code,title}]`), through `public_tv` as today. Media still hard-linked and size-limited (95 MB); heavy videos stay LAN-only.
- `assert_public` runs on every file. The heartbeat counts the common file.

## TV page

- Lab = last path segment under `/tv/` (none = common). Fetch `../data/all.json` and the lab's JSON relative to the page; `rooms` comes from the JSON unless `?room=` is given. Replaces the hardcoded `DEFAULT_ROOM`.
- Grouped order: stable sort of the common slides by lab, schedule pages first.
- Several-TVs-in-sync (decision 0010) is unchanged: each file is a pure function of the clock.

## Deploy

`sync.yml`: after copying `apps/tv/index.html` into `tv/`, read `labs.json` from `tv-public` and copy the page into `tv/<code>/index.html` for each lab. A new lab appears after the next publish.

## Office

TV screen: a Lab dropdown on a slide (All labs, then each lab) and a Lab filter on the list. Labs themselves are edited by SQL.

## Pi

Rerun `scripts/tv-pi-setup.sh` with `/tv/techlab/` for the existing TV (roadmap item "Rooms" is replaced by this).

## Tests

- `tests/test_tv.py`: per-lab filtering (null + own lab), common mix order, `lab` key allowed by `assert_public`, public copy writes `labs.json`.
- `supabase/tests/database/`: next free number; `labs` staff-only, `tv_slides.lab` FK.
- `tests/check_tv_page.py`: `/tv/techlab/` shows its rooms; `/tv/` shows all.

## Docs and record

ARCHITECTURE (data model, status), OPERATIONS (add a lab), STAFF-GUIDE (Lab dropdown), edge-node.md (nginx rule, Pi URL), README (URLs), ROADMAP (this and C), a decision record, a LOG entry.
