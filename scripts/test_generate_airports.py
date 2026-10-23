import csv
import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).with_name("generate_airports.py")
PROJECT_ROOT = SCRIPT_PATH.parent.parent
MANIFEST_PATH = SCRIPT_PATH.with_name("data") / "airport_coverage_manifest.json"
SPEC = importlib.util.spec_from_file_location("generate_airports", SCRIPT_PATH)
generate_airports = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(generate_airports)


class FakeTimezoneFinder:
    def timezone_at(self, *, lng, lat):
        if (lng, lat) == (10.0, 20.0):
            return None
        return "America/Toronto"


class AirportGeneratorTests(unittest.TestCase):
    def test_checked_in_coverage_manifest_matches_final_airport_resource(self):
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        resource_path = PROJECT_ROOT / manifest["output"]["path"]
        aliases_path = PROJECT_ROOT / manifest["sources"]["aliases"]["path"]

        self.assertEqual(
            self.sha256(resource_path),
            manifest["output"]["sha256"],
        )
        self.assertEqual(
            self.sha256(aliases_path),
            manifest["sources"]["aliases"]["sha256"],
        )
        for source_name in ("airports", "countries"):
            source = manifest["sources"][source_name]
            self.assertTrue(source["url"].startswith("https://"))
            self.assertEqual(len(source["sha256"]), 64)
            self.assertEqual(source["retrieved"], "2026-08-19")
        self.assertEqual(
            generate_airports.AIRPORTS_URL,
            manifest["sources"]["airports"]["url"],
        )
        self.assertEqual(
            generate_airports.AIRPORTS_SHA256,
            manifest["sources"]["airports"]["sha256"],
        )
        self.assertEqual(
            generate_airports.COUNTRIES_URL,
            manifest["sources"]["countries"]["url"],
        )
        self.assertEqual(
            generate_airports.COUNTRIES_SHA256,
            manifest["sources"]["countries"]["sha256"],
        )

        airports = {
            airport["iata"]: airport
            for airport in json.loads(resource_path.read_text(encoding="utf-8"))
        }
        covered_iata = manifest["coverage"]["scheduledRegionalIATA"]
        self.assertEqual(len(covered_iata), 277)
        self.assertEqual(covered_iata, sorted(set(covered_iata)))
        for iata in covered_iata:
            self.assertIn(iata, airports)
            self.assertTrue(
                any(self.contains_han(alias) for alias in airports[iata]["aliases"]),
                f"{iata} must have a Chinese alias",
            )

    def test_filters_closed_and_missing_iata_and_maps_country(self):
        airports, _ = self.generate_fixture()

        self.assertEqual([airport["iata"] for airport in airports], ["AAA", "LCL", "ZZB"])
        self.assertEqual(airports[0]["country"], "Estonia")

    def test_icao_uses_gps_code_and_never_falls_back_to_ident(self):
        airports, _ = self.generate_fixture()

        self.assertEqual(airports[1]["iata"], "LCL")
        self.assertEqual(airports[1]["icao"], "")
        self.assertEqual(airports[2]["icao"], "KZZZ")

    def test_missing_coordinate_timezone_falls_back_to_utc(self):
        airports, fallback_count = self.generate_fixture()

        self.assertEqual(airports[0]["timeZoneID"], "Etc/UTC")
        self.assertEqual(fallback_count, 1)

    def test_keywords_are_split_cleaned_and_deduplicated_stably(self):
        airports, _ = self.generate_fixture()

        self.assertEqual(airports[0]["aliases"], ["Alpha Hub", "Common"])

    def test_external_aliases_merge_by_iata_without_duplicates(self):
        airports, _ = self.generate_fixture(
            aliases={
                "AAA": ["阿尔法机场", "Common", " 阿尔法机场 "],
                "MISSING": ["不存在机场"],
            }
        )

        self.assertEqual(
            airports[0]["aliases"],
            ["Alpha Hub", "Common", "阿尔法机场"],
        )

    def test_source_option_writes_stably_sorted_compact_json(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "snapshot"
            source.mkdir()
            self.write_sources(source)
            output = root / "airports.json"
            aliases = root / "aliases.json"
            aliases.write_text(
                json.dumps(
                    {
                        "source": {
                            "name": "Test aliases",
                            "license": "CC0-1.0",
                            "generated": "2026-08-19",
                        },
                        "airports": {
                            "AAA": ["阿尔法机场", "Common", "阿尔法机场"]
                        },
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT_PATH),
                    "--source",
                    str(source),
                    "--aliases-input",
                    str(aliases),
                    "--output",
                    str(output),
                ],
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            encoded = output.read_text(encoding="utf-8")
            decoded = json.loads(encoded)

        self.assertEqual([airport["iata"] for airport in decoded], ["AAA", "LCL", "ZZB"])
        self.assertEqual(
            decoded[0]["aliases"],
            ["Alpha Hub", "Common", "阿尔法机场"],
        )
        self.assertNotIn('": "', encoded)
        self.assertNotIn(", ", encoded)
        self.assertTrue(encoded.endswith("\n"))

    def generate_fixture(self, aliases=None):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            self.write_sources(source)
            aliases_path = None
            if aliases is not None:
                aliases_path = source / "aliases.json"
                aliases_path.write_text(
                    json.dumps(
                        {
                            "source": {
                                "name": "Test aliases",
                                "license": "CC0-1.0",
                                "generated": "2026-08-19",
                            },
                            "airports": aliases,
                        },
                        ensure_ascii=False,
                    ),
                    encoding="utf-8",
                )
            return generate_airports.generate(
                source / "airports.csv",
                source / "countries.csv",
                aliases_path=aliases_path,
                timezone_finder=FakeTimezoneFinder(),
            )

    @staticmethod
    def write_sources(source):
        with (source / "countries.csv").open(
            "w",
            encoding="utf-8",
            newline="",
        ) as stream:
            writer = csv.DictWriter(stream, fieldnames=["code", "name"])
            writer.writeheader()
            writer.writerow({"code": "EE", "name": "Estonia"})
            writer.writerow({"code": "CA", "name": "Canada"})

        fields = [
            "ident",
            "type",
            "name",
            "latitude_deg",
            "longitude_deg",
            "iso_country",
            "municipality",
            "gps_code",
            "iata_code",
            "keywords",
        ]
        rows = [
            {
                "ident": "CA-0001",
                "type": "small_airport",
                "name": "Zulu Airport",
                "latitude_deg": "45",
                "longitude_deg": "-73",
                "iso_country": "CA",
                "municipality": "Zulu",
                "gps_code": "kzzz",
                "iata_code": "zzb",
                "keywords": "",
            },
            {
                "ident": "EAAA",
                "type": "closed",
                "name": "Closed Airport",
                "latitude_deg": "20",
                "longitude_deg": "10",
                "iso_country": "EE",
                "municipality": "Closed",
                "gps_code": "EAAA",
                "iata_code": "CLS",
                "keywords": "",
            },
            {
                "ident": "EE-0002",
                "type": "small_airport",
                "name": "No IATA Airport",
                "latitude_deg": "20",
                "longitude_deg": "10",
                "iso_country": "EE",
                "municipality": "Missing",
                "gps_code": "",
                "iata_code": "",
                "keywords": "",
            },
            {
                "ident": "EE-0003",
                "type": "small_airport",
                "name": "Alpha Airport",
                "latitude_deg": "20",
                "longitude_deg": "10",
                "iso_country": "EE",
                "municipality": "Alpha",
                "gps_code": "eaaa",
                "iata_code": "aaa",
                "keywords": " Alpha Hub, Common; alpha hub | COMMON ",
            },
            {
                "ident": "CA-LOCAL",
                "type": "small_airport",
                "name": "Local Airport",
                "latitude_deg": "45",
                "longitude_deg": "-73",
                "iso_country": "CA",
                "municipality": "Local",
                "gps_code": "",
                "iata_code": "lcl",
                "keywords": "",
            },
        ]
        with (source / "airports.csv").open(
            "w",
            encoding="utf-8",
            newline="",
        ) as stream:
            writer = csv.DictWriter(stream, fieldnames=fields)
            writer.writeheader()
            writer.writerows(rows)

    @staticmethod
    def sha256(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    @staticmethod
    def contains_han(value):
        return any(
            0x3400 <= ord(character) <= 0x9FFF
            for character in value
        )


if __name__ == "__main__":
    unittest.main()
