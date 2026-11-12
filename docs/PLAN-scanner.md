# Plan: barcode scanner and inventory reports

One system: the office scans places (QR `office/?place=CODE`) and tagged items (tag, serial, or `?asset=TAG`), counts a place by scanning, pairs PlayStation boxes with consoles, and reports on equipment requests. Branch `scanner`; no database change is needed (all reads use existing tables and views), so nothing to apply. Pairing results are downloaded as CSV (no table for box serials).

Gates: `cd apps/office && flutter analyze && flutter test`; Python: `uv run python -m unittest discover -s tests -p 'test_*.py'`. One build or test at a time.

## Tasks

- [x] **S1** `resolveCode(code, refs)` pure function in `apps/office/lib/scan_logic.dart`: place QR text or URL, asset tag, `?asset=` URL, asset serial, else unknown. Ornith. Done when `test/scan_logic_test.dart` passes. Done: 8 tests pass.
- [ ] **S2** `mobile_scanner` dependency and `CodeCapture` widget (`scan_widget.dart`): camera on web, plus a text field that also takes USB scanners (Enter submits). terra. Done when `flutter analyze` is clean and `flutter build web` succeeds.
- [ ] **S3** `ScanPage` + asset screen (`scan_screen.dart`): Scan button on Bookings and Inventory app bars; place opens `PlacePage`; asset opens its screen (place or holder, condition, history); unknown offers search / add. `?asset=` deep link in `main.dart`. terra. Done when analyze + tests pass and a widget test covers the unknown-code state.
- [ ] **S4** Stocktake by scanning: in a place's Count mode a scan button feeds the existing Found here path (ticks listed items). luna. Done when analyze + tests pass.
- [ ] **S5** `matchPairs(boxes, consoles)` pure function in `pairing_logic.dart`: matched pairs, boxes holding the wrong console, unmatched consoles assigned to empty boxes, and leftovers. Ornith. Done when `test/pairing_logic_test.dart` passes (matches, swaps, extra/missing, duplicates).
- [ ] **S6** `PairingPage` (`pairing_screen.dart`): scan all boxes, then all consoles; results table; CSV download and printable sticker sheet (console serial per box). terra. Done when analyze + tests pass and a widget test drives it with typed codes.
- [ ] **S7** `bookingReport(activities, lines, movements, people)` pure function + CSV in `report_logic.dart`, equipment requests by period: request, requester, items, status, issued/returned/outstanding. Ornith. Done when `test/report_logic_test.dart` passes.
- [ ] **S8** `ReportScreen` in the office (period picker, table, Download CSV), linked from Usage. luna. Done when analyze + tests pass.
- [ ] **S9** `scripts/booking_report.py` (same columns, service key, like `usage_export.py`) + `tests/test_booking_report.py`. luna. Done when the unittest passes.
- [ ] **S10** Docs: STAFF-GUIDE (Scan, count by scanning, Pairing, Booking report), ARCHITECTURE office row, ROADMAP (item 7 of Smart storage done; scanner link), README docs index if needed. luna. Done when the sections exist.

Left for a person: camera test in a real browser (HTTPS or localhost), and a USB scanner test.
