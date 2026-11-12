"""Run: uv run python -m unittest tests.test_booking_report"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
import booking_report as report  # noqa: E402


class BookingReportTest(unittest.TestCase):
    def setUp(self):
        self.activities = [
            {"id": 8, "kind": "equipment", "starts_at": "2026-05-02T09:00:00Z", "title": 'Kit, "A"', "requester_id": 1, "requester_display": "Fallback", "status": "approved"},
            {"id": 2, "kind": "equipment", "starts_at": "2026-05-02T09:00:00Z", "title": "No issue", "requester_id": None, "requester_display": "Guest", "status": "requested"},
            {"id": 3, "kind": "booking", "starts_at": "2026-05-03T09:00:00Z", "title": "Filtered", "status": "approved"},
            {"id": 4, "kind": "equipment", "starts_at": "2026-06-01T00:00:00Z", "title": "Outside", "status": "approved"},
        ]
        self.lines = [
            {"activity_id": 8, "item_id": 9, "qty": 1.5},
            {"activity_id": 8, "item_id": 2, "qty": 2},
            {"activity_id": 2, "item_id": 7, "qty": 1},
        ]
        self.movements = [
            {"activity_id": 8, "kind": "issue", "qty": 3},
            {"activity_id": 8, "kind": "return", "qty": 1},
            {"activity_id": 2, "kind": "return", "qty": 1},
            {"activity_id": 8, "kind": "move", "qty": 20},
        ]

    def rows(self):
        return report.report_rows(self.activities, self.lines, self.movements,
                                  [{"id": 1, "name": "Ada", "email": "ada@example.test"}],
                                  {2: "Cable", 9: "Board"}, "2026-05-01", "2026-05-31")

    def test_filter_order_states_fallback_and_item_text(self):
        rows = self.rows()
        self.assertEqual([r["id"] for r in rows], [2, 8])
        self.assertEqual([r["state"] for r in rows], ["not issued", "outstanding"])
        self.assertEqual(rows[0]["requester"], "Guest")
        self.assertEqual(rows[1]["requester"], "Ada")
        self.assertEqual(rows[1]["email"], "ada@example.test")
        self.assertEqual(rows[1]["items"], "Cable x2; Board x1.5")
        self.assertEqual(rows[1]["outstanding"], 2)
        self.activities[0]["starts_at"] = "2026-05-02T09:00:00Z"
        self.movements.append({"activity_id": 8, "kind": "return", "qty": 2})
        self.assertEqual(self.rows()[1]["state"], "returned")

    def test_csv_quoting_and_column_order(self):
        csv_text = report.to_csv([{"id": 1, "date": "2026-05-02", "title": 'Kit, "A"\nnext'}])
        self.assertEqual(csv_text.splitlines()[0], ",".join(report.COLUMNS))
        self.assertIn('"Kit, ""A""\nnext"', csv_text)


if __name__ == "__main__":
    unittest.main()
