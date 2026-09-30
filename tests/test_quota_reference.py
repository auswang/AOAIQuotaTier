import json
from pathlib import Path
import re
import unittest


TEMPLATE = Path(__file__).resolve().parents[1] / "templates" / "index.html"


class QuotaReferenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.html = TEMPLATE.read_text()
        source = cls.html.split("const TIER_DATA = ", 1)[1].split(";", 1)[0]
        cls.tiers = json.loads(re.sub(r"(\d):", r'"\1":', source))

    def test_complete_unique_rows(self):
        self.assertEqual(set(self.tiers), set("0123456"))
        for tier, rows in self.tiers.items():
            self.assertEqual(len(rows), 4 if tier == "0" else 89)
            self.assertEqual(len({tuple(row[:2]) for row in rows}), len(rows))
            for row in rows:
                self.assertEqual(len(row), 4)
                self.assertIn(row[1], ("GlobalStandard", "DataZoneStandard", "Standard"))
                self.assertRegex(row[2], r"^[\d,]+(?: / 10s)?$")
                self.assertRegex(row[3], r"^(?:[\d,]+|-)$")

    def test_updated_models_all_paid_tiers(self):
        for tier, dz, gs in [
            ("1", "333", "1,000"),
            ("2", "667", "2,000"),
            ("3", "1,333", "4,000"),
            ("4", "2,333", "7,000"),
            ("5", "3,333", "10,000"),
            ("6", "5,000", "15,000"),
        ]:
            for model in ("gpt-5.5", "gpt-6-astra", "gpt-6-luna", "gpt-6-sol", "gpt-6.1-sol"):
                model_dz = "3,000" if model == "gpt-5.5" and tier == "5" else dz
                self.assertIn([model, "DataZoneStandard", model_dz, model_dz + ",000"], self.tiers[tier])
                self.assertIn([model, "GlobalStandard", gs, gs + ",000"], self.tiers[tier])
            for model in ("gpt-image-2.5-flare", "gpt-image-2.5-sunburst"):
                self.assertIn([model, "GlobalStandard", "5", "-"], self.tiers[tier])

    def test_chat_versions(self):
        for tier, thousands in enumerate((1, 2, 3, 4, 5, 8), start=1):
            rows = self.tiers[str(tier)]
            self.assertIn([
                "gpt-chat-latest (2026-05-05 / 2026-05-28 / 2026-06-24)",
                "GlobalStandard", f"{thousands * 10000:,}", f"{thousands * 1000000:,}",
            ], rows)
            self.assertIn([
                "gpt-chat-latest (2026-08-06)",
                "GlobalStandard", f"{thousands * 1000:,}", f"{thousands * 1000000:,}",
            ], rows)

    def test_notes_in_all_languages(self):
        self.assertEqual(self.html.count("quotaNotes:"), 5)
        self.assertIn('data-i18n="quotaNotes"', self.html)


if __name__ == "__main__":
    unittest.main()
