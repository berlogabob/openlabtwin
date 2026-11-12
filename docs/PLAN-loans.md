# Plan: lab loans in natural language (OpenLabTwin side)

Source plan: TyLog wave 34 (`TypstSeq/docs/plans/activity-plan.md`, section "Wave 34"). OpenLabTwin stays the system of record; TyLog is the natural-language interface. Scripts that write default to a dry run.

- [ ] A0 Addressed storage cells: `scripts/seed_places.py` + `docs/places.yaml` (draft; shelf counts to confirm), then `--apply` and print labels
- [ ] A1 Pairing key: match on product + unit digits (`apps/office/lib/pairing_logic.dart`)
- [ ] A2 `scripts/import_pairing.py`: register consoles from the final pairing CSV (dry run by default)
- [ ] A3 Run A2 on the real result, print QR labels for consoles and boxes — left for main session
- [ ] A4 Photo label reading (migration `label_reads`, edge job, office "Photo" button) — left for main session
- [ ] A5 `docs/STAFF-GUIDE.md`: find an item / hand it out / take it back
- [ ] B1 `scripts/export_tylog.py`: catalogue into the TyLog vault as `equipment` / `place` notes (tested on a temp directory only)
