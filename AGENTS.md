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
- Local models: Unsloth Studio (big lab PC, `http://192.168.1.42:8888`, key in `~/.unsloth_key`) and Ollama. `pi` sometimes hangs at start-up; calling Studio's `/v1/chat/completions` directly works. Check every draft with tests.
- In `supabase/tests/database/*.sql`, top-level pgTAP calls start a line with `select`, and every other `select` is indented (`sqltest.py` captures those lines).
