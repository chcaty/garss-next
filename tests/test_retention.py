import time
import unittest
from datetime import date

from retention import filter_recent_entries, retention_cutoff


def parsed_date(value):
    return time.strptime(value, "%Y-%m-%d")


class RetentionTests(unittest.TestCase):
    def test_cutoff_is_inclusive(self):
        self.assertEqual(retention_cutoff(date(2026, 9, 30), 30), date(2026, 9, 1))

        entries = [
            {"title": "boundary", "published_parsed": parsed_date("2026-09-01")},
            {"title": "expired", "published_parsed": parsed_date("2026-08-31")},
            {"title": "recent", "updated_parsed": parsed_date("2026-09-30")},
            {"title": "unknown"},
        ]
        kept = filter_recent_entries(entries, today=date(2026, 9, 30))
        self.assertEqual([entry["title"] for entry in kept], ["boundary", "recent"])

    def test_invalid_retention_is_rejected(self):
        with self.assertRaises(ValueError):
            retention_cutoff(date(2026, 9, 30), 0)

    def test_window_contains_exactly_requested_dates(self):
        today = date(2026, 9, 30)
        for days in (1, 7, 30):
            self.assertEqual((today - retention_cutoff(today, days)).days + 1, days)



if __name__ == "__main__":
    unittest.main()
