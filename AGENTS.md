# Agent notes

Docs are part of every change: a commit that changes behaviour, commands, schema, URLs, secrets, schedules or the staff workflow updates the matching doc in the same commit:
- `docs/ARCHITECTURE.md`: parts, data model, privacy layers, decisions and status;
- `docs/OPERATIONS.md`: runbook;
- `docs/STAFF-GUIDE.md`: office usage;
- `docs/edge-node.md`: the lab machine;
- `README.md`: URLs and the docs index;
- `docs/ROADMAP.md`: what's next (remove an item when it's done, add new ones).

Gotchas the code doesn't show (details in `docs/OPERATIONS.md`):
- Database work runs over HTTPS (`scripts/sqltest.py`, PostgREST): the IADE network blocks Postgres ports, and Docker isn't used.
- Public data leaves only through `scripts/export.py`'s explicit columns and `KEYS` allowlist.
- `apps/site` pins `build_web_compilers ^4.8.5` (jaspr_builder 0.23.4 needs analyzer 12).
- Never run `scripts/tv.py` (or `export.py`) from a dev machine against the live database with a test folder: `tv.py` rewrites `tv_media` from the folder it sees. Test with `tests/test_tv.py`, or on the node itself.
- Local models: Unsloth Studio (big lab PC, `http://192.168.1.42:8888` on the lab network, `http://desktop-vdsrh2e:8888` over Tailscale; key in `~/.unsloth_key`) and Ollama. pi on Studio: `PI_PROVIDER=studio PI_MODEL=unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF` (its `baseUrl` is in `~/.pi/agent/models.json`). `pi` sometimes hangs at start-up, and over the Tailscale relay a big prompt can take minutes to its first reply; calling Studio's `/v1/chat/completions` directly works. pi renames its process, so `pkill -f` misses it: stop it by process group. It tends to drop a file's final newline. Check every draft with tests.
- Storage data is staff-only: labels (`scripts/labels.py`) are written to the Mac, never to the repo or the site, and the source spreadsheet (student names and numbers) never goes in the repo.
- `places.code` is the QR label and the Godot node name: don't rename codes in migrations or scripts.
- The node's Postgres (`openlabtwin`) is a read-only mirror, rebuilt nightly by `scripts/mirror.py`; write only to Supabase. An empty table's backup has no columns, so a table a mirror view reads needs its columns in `mirror.EMPTY`.
- New database tests take the next free number in `supabase/tests/database/` (they run in name order).
- In `supabase/tests/database/*.sql`, top-level pgTAP calls start a line with `select`, and every other `select` is indented (`sqltest.py` captures those lines).

Project record rules (openlabtwin is the record location):
- A commit that makes, changes or reverses a decision adds a decision record in openlabtwin `docs/decisions` (a reversal adds a new record and marks the old one superseded) and carries the trailer `Decision: NNNN short title`.
- Each working day gets a `docs/LOG.md` entry in openlabtwin (newest first).
