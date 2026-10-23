import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).with_name("validate_airport_resources.py")


class AirportResourceValidationTests(unittest.TestCase):
    def test_accepts_current_alias_resource_and_license(self):
        with tempfile.TemporaryDirectory() as directory:
            resources = self.write_resources(Path(directory))

            result = self.run_validator(resources)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("9000 airports", result.stdout)
        self.assertIn("1 with aliases", result.stdout)

    def test_rejects_resource_without_aliases_field(self):
        with tempfile.TemporaryDirectory() as directory:
            resources = self.write_resources(Path(directory))
            airports_path = resources / "airports.json"
            airports = json.loads(airports_path.read_text(encoding="utf-8"))
            airports[0].pop("aliases")
            airports_path.write_text(json.dumps(airports), encoding="utf-8")

            result = self.run_validator(resources)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("aliases", result.stderr)

    def test_rejects_pre_chinese_alias_license(self):
        with tempfile.TemporaryDirectory() as directory:
            resources = self.write_resources(Path(directory))
            (resources / "AIRPORT_DATA_LICENSE.md").write_text(
                "Generated 2026-08-19. OurAirports Public Domain.\n",
                encoding="utf-8",
            )

            result = self.run_validator(resources)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Wikidata", result.stderr)

    def write_resources(self, root):
        resources = root / "Resources"
        resources.mkdir()
        airports = [
            {"iata": "PEK", "aliases": ["北京"]},
            *(
                {"iata": f"T{index:04d}", "aliases": []}
                for index in range(8_999)
            ),
        ]
        (resources / "airports.json").write_text(
            json.dumps(airports, ensure_ascii=False),
            encoding="utf-8",
        )
        (resources / "AIRPORT_DATA_LICENSE.md").write_text(
            "Generated 2026-08-19. Wikidata aliases are CC0 1.0.\n",
            encoding="utf-8",
        )
        return resources

    def run_validator(self, resources):
        return subprocess.run(
            [sys.executable, str(SCRIPT_PATH), str(resources)],
            capture_output=True,
            text=True,
            check=False,
        )


if __name__ == "__main__":
    unittest.main()
