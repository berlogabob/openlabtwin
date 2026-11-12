# Matching PS4 consoles to their boxes

You need: a phone (camera) or a laptop with a USB barcode scanner, staff sign-in, all boxes and consoles on one table.

1. Open the office on the phone: https://berlogabob.github.io/openlabtwin/office/ and sign in. Inventory, then the two-arrows icon: **Pair boxes and consoles**.
2. **Boxes.** Take each console out of its box and put it on a separate pile. Scan the serial barcode on every box. The counter goes up per box; a wrong scan: tap it in the list to remove it. Tap **Done with boxes**.
3. **Consoles.** The console label is too small for any phone scanner (tested: barcode decoders and phone OCR fail), but the lab's vision model reads it reliably (7/7 test photos, about 5 s each).
   - Photograph each console's label with the normal camera: label filling the width, sharp, no flash glare. One photo per console.
   - Put the photos in one folder on the Mac (AirDrop or a cable), then run `uv run python scripts/read_labels.py FOLDER` in the openlabtwin repo (needs the Studio on: AI_URL/AI_KEY in `.env`). Lines marked UNREAD: retake that photo.
   - Copy the serial list at the end of the output, paste it into the Pairing field on the consoles step (a pasted list adds every line), tap **Done with consoles**.
4. **Read the result.**
   - **Matched:** put each console into the box with the same serial.
   - **Move console into box:** "Put console X into box Y": these boxes keep a different serial, so the box label is wrong for what is inside.
   - **Empty boxes left / Consoles without a box:** should be empty when the counts match; if not, a scan is missing. Tap **Back to consoles** and scan the missing one.
5. **Stickers.** Tap **Print stickers**, open the downloaded `sticker.html`, print it. Each sticker says which console serial is inside which box; stick it on that box. Tap **Download CSV** too and keep it (thesis evidence, and the list for the inventory).

Check first: scan one box and the console you know belongs to it. If they don't show as **Matched**, the box barcode and the console barcode encode the serial differently (a prefix or a product code). Stop and tell Claude which text each one gives.
