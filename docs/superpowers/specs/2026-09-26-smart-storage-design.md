# Smart storage: design

Date: 2026-09-26. Status: approved in chat.

## Why

The lab's equipment list is a spreadsheet the previous team made (`Inventario Tech Lab.xlsx`, 6 sheets, about 210 rows). Its locations are free text, written several ways for the same shelf ("15 - 3 Direito", "15- 3 Direito", "15 -3 Direito"), and nobody fully trusts it. Milestone 4 already has the machinery: a place tree, items, append-only movements, and the `stock` and `on_loan` views. What it lacked is what that milestone deferred:

- real places with codes and QR labels;
- individual tagged items (consoles, headsets, lab PCs);
- a stocktake that replaces the spreadsheet's numbers with counted ones;
- a way to clean up the mess the import brings in.

The place code is also the contract with the Godot digital twin (milestone 5). The scene node for a shelf is named after the shelf's `places.code`, so the twin can show where anything is without a copy of the layout in the database.

## Decisions (user, 2026-09-26)

| Topic | Decision |
|---|---|
| Place tree | Tech Lab (`LAB`, rooms 13/14) holds the Vitrine (`LAB-VIT`) and the grey server cabinet (`LAB-SRV`). Room 15 (`R15`, the gabinete, the main store) holds a left and right cabinet, each with shelves 1 (top) to 5 (bottom): `R15-L-S1` … `R15-R-S5`. Its three labelled boxes are `R15-BOX-GREEN`, `-SENS` and `-CARS`. The -2 floor is `B2` (long-term), with racks and shelves (`B2-R1-S1`) added from the office at its first stocktake. There are 8 classroom cupboards, `CUP1`–`CUP8`; staff set their rooms later. |
| Codes | Capitals, digits and dashes (`^[A-Z0-9]+(-[A-Z0-9]+)*$`), unique, printed on the label. Once printed, a code doesn't change: changing it breaks the label and the Godot link, and the office warns about this. |
| QR label | Opens `…/openlabtwin/office/?place=<CODE>`, the office place screen. Staff only. |
| Tags | Existing tags are kept: GS-031, LV-01, PF-136 (normalised as prefix, dash, number). A new tagged item gets the next `TL-0001` from a sequence. |
| Labels | `scripts/labels.py` on the Mac writes a print-ready A4 page. They are not on the public Jaspr site, which would publish where every console and headset is stored. |
| Local database | A read-only mirror on the edge node (Postgres, localhost), loaded nightly from the existing JSON backup. Supabase stays the only place anything is written. |
| Jaspr | Not used here: everything in this part is staff-only data. |

## Data model

- **places** gets `code` and `counted_at`. An empty `counted_at` means never counted.
- **items** gets:
  - `note`: what the spreadsheet said;
  - `merged_into`: set by a merge; the office hides these items;
  - `name_norm`: generated, lowercased, accents and punctuation stripped, with a trigram index.
- **assets:** one row per tagged item: `item_id`, `tag`, `serial`, `condition` (ok / broken / missing), `note` and `seen_at` (last ticked in a stocktake).
- **movements** gets:
  - `asset_id`;
  - `note`: provenance, such as `import: Inventario Tech Lab.xlsx`, `stocktake` or `tagged`.
  - Two constraints: a composite FK `(asset_id, item_id) → assets (id, item_id) on update cascade`, so an asset moves only as its own item and follows it through a merge; and `abs(qty) = 1` whenever an asset is named.
- **asset_place** (view): each asset's latest movement. That gives its place; issued means held by a person; consumed or adjusted away means nowhere.
- **storage_issues** (view): every Needs-attention rule in one place, as in UNIDCOM RIMS `output_quality.sql`:
  - `negative_stock`
  - `never_counted` (a place holds stock but was never counted)
  - `stale_count` (more than 180 days)
  - `possible_duplicate` (trigram similarity > 0.5 between two unmerged items)
  - `asset_broken`, `asset_missing`

  Each row has a `key`.
- **issue_waivers:** a waived key stops showing. A stale key includes the count date, so its waiver lapses with the next count.
- **merge_items(survivor, losers[]):** staff only, security definer. It moves assets (their movements follow through the cascade), then the remaining movements and the kit lines (a booking that lists both keeps one line with both quantities), and sets `merged_into`. No item is deleted.

Stock is still the sum of movements. A tagged item counts in its item's stock like any other unit.

## Import

`scripts/import_inventory.py` reads the six sheets:
- "Sala 15" and "Sala 13/14" rows;
- "Material de Docente", with the note "belongs to <professor>";
- "Computadores Tech Lab", as assets LV-01…07, plus AS-08 marked broken;
- "Mobiliário", as stationary items in LAB, skipping rows other sheets already count;
- "PlayStation": console and controller serials become assets, placed by the block header above them.

How the cells are read:
- An unknown location spelling stops the import. Nothing is guessed.
- Quantities: "11 + 10" → 21, "Varios (100+)" → 100, other text → 1. The original text is kept in the item's note.
- When a row has more tags than items (device and box tags mixed together), the tags go into the note, to be sorted out at the stocktake.

It runs as a dry run by default. `--apply` writes one receive per asset plus the untagged remainder, and refuses to run a second time.

**Every place starts uncounted,** so the whole store appears as `never_counted` until someone counts it. That is how the untrusted spreadsheet gets replaced by real counts.

The PlayStation sheet's student loan records (12 rows) and the one console outside IADE are **listed, not imported**. Staff decide whether each is still on loan and record it as an issue movement if so.

## Office

- **Inventory:**
  - Needs attention at the top. Merge and "Not the same" for duplicates, Dismiss for anything else; tapping a place issue opens that place.
  - A Places button.
  - The Record movement form can pick a tagged item, which sets the quantity to 1.
- **Places:** the tree, indented, with the item count and last count per place, and "Add place".
- **Place screen:**
  - what should be here: totals, the untagged part, and the tagged items with their condition, which can be changed;
  - **Count**: type the real untagged counts and tick each tagged item seen. Saving writes `adjust` rows for the differences (note `stocktake`), marks unticked tagged items missing, and sets `counted_at`;
  - Edit (name, code, parent, tier), add a place inside, tag an item (the next TL number or a legacy tag, with a serial);
  - Record movement, prefilled with this place.
- **QR link:** `office/?place=CODE` opens that place's screen when signed in. Signing in through the email link drops the query, so a first scan while signed out lands on Bookings. Staff stay signed in on their phones.

## Labels

`scripts/labels.py [--root CODE] [--assets] [--out FILE]` writes an A4 page of 3 × 8 labels. Each label has the QR (with the segno library, as `tv.py` does), the code or tag in large type, and the name. The default output is `~/Downloads/labels.html`.

## Mirror

`scripts/mirror.py`, on the node at 03:45 after the 03:30 backup:
- loads the newest backup folder into the local database `openlabtwin`, one table per JSON file, with column types taken from the values;
- recreates `stock`, `on_loan` and `asset_place`;
- fails if any row count differs from its JSON file.

`edge-setup.sh` step 10 installs Postgres (localhost only) and creates the database.

## Godot contract

The twin names each storage node after its `places.code`. To show where an item is, it reads `stock` and `asset_place` for the item, maps each `place_id` to its code, and highlights those nodes. It can read from Supabase (HTTPS, a staff session) or from the node's mirror over SSH or Tailscale. `movements` gives the history, for replaying use over time. Nothing in this part builds Godot code.

## Out of scope

RFID, procurement, student self-service ("report broken" by QR, which would bring Jaspr back in), and moving the source of truth to the node.
