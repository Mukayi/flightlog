import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
GENERATOR = ROOT / "scripts/generate_icon.sh"
SOURCE = ROOT / "Assets/FlightLogIconSource.png"
SOURCE_V1 = ROOT / "Assets/FlightLogIconSourceV1.png"
SOURCE_V2 = ROOT / "Assets/FlightLogIconSourceV2.png"
MASTER = ROOT / "Assets/FlightLogIconMaster.png"
ICONSET = ROOT / "Assets/FlightLog.iconset"
ICNS = ROOT / "Assets/FlightLog.icns"
V21_SOURCE_SHA256 = "4f5f1d952a7221bdb46805bbe42281034ec09b902bc6f3295832e14bb64fe02a"
V21_MASTER_SHA256 = "98c56c47919fc4517b70f2defa1dae5484703c10eac8a14190f739086ee5d7f2"
V21_ICNS_SHA256 = "6e644c3e10134166203f675d00a5cba4e9be03b8344ab58476d5a63a21c49ac6"
V2_SOURCE_SHA256 = "9d132133f1c29bb50ff323ce99f9249c49aa06f3a7f4e5734a460758d3f964ba"
V1_SOURCE_SHA256 = "bb9f9e4f755de74c4369fe46a0b3e85083575fec35919dc4221547ea9fcb32e6"

EXPECTED_SIZES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}


def sips_property(path, property_name):
    result = subprocess.run(
        ["sips", "-g", property_name, str(path)],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.rsplit(":", 1)[-1].strip()


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_pixels(path):
    result = subprocess.run(
        [
            "xcrun",
            "swift",
            str(ROOT / "scripts/verify_icon_alpha.swift"),
            str(path),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    return result


class IconGenerationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.output_directory = tempfile.TemporaryDirectory()
        cls.generated = Path(cls.output_directory.name)
        checked_in_assets = [MASTER, ICNS, *sorted(ICONSET.glob("*.png"))]
        cls.checked_in_hashes = {
            path: sha256(path) for path in checked_in_assets
        }
        environment = os.environ.copy()
        environment["FLIGHTLOG_ICON_OUTPUT_DIR"] = str(cls.generated)
        subprocess.run(
            [str(GENERATOR)],
            cwd=cls.generated,
            env=environment,
            check=True,
        )

    @classmethod
    def tearDownClass(cls):
        for path, original_hash in cls.checked_in_hashes.items():
            if sha256(path) != original_hash:
                raise AssertionError(f"Python tests modified checked-in asset: {path}")
        cls.output_directory.cleanup()

    def test_v21_source_and_icon_history_are_preserved(self):
        self.assertEqual(sips_property(SOURCE, "pixelWidth"), "1024")
        self.assertEqual(sips_property(SOURCE, "pixelHeight"), "1024")
        self.assertEqual(sha256(SOURCE), V21_SOURCE_SHA256)
        self.assertEqual(sha256(SOURCE_V2), V2_SOURCE_SHA256)
        self.assertEqual(sha256(SOURCE_V1), V1_SOURCE_SHA256)

    def test_master_has_real_alpha_safe_bounds_and_expected_pixels(self):
        master = self.generated / "FlightLogIconMaster.png"
        self.assertEqual(sips_property(master, "pixelWidth"), "1024")
        self.assertEqual(sips_property(master, "pixelHeight"), "1024")
        self.assertEqual(sips_property(master, "hasAlpha"), "yes")

        probe = verify_pixels(master)
        self.assertEqual(probe.returncode, 0, probe.stderr)
        self.assertIn("corners=0,0,0,0", probe.stdout)
        self.assertIn("center=255", probe.stdout)
        self.assertIn("safeBounds=pass", probe.stdout)
        self.assertIn("subjects=pass", probe.stdout)

    def test_v21_master_and_icns_match_golden_hashes(self):
        self.assertEqual(
            sha256(self.generated / "FlightLogIconMaster.png"),
            V21_MASTER_SHA256,
        )
        self.assertEqual(
            sha256(self.generated / "FlightLog.icns"),
            V21_ICNS_SHA256,
        )

    def test_small_icons_keep_navy_white_and_cyan_contrast(self):
        for filename in ("icon_16x16.png", "icon_32x32.png"):
            with self.subTest(filename=filename):
                probe = verify_pixels(
                    self.generated / "FlightLog.iconset" / filename
                )
                self.assertEqual(probe.returncode, 0, probe.stderr)
                self.assertIn("palette=pass", probe.stdout)
                self.assertIn("contrast=pass", probe.stdout)
                self.assertIn("shape=pass", probe.stdout)

    def test_iconset_contains_all_standard_sizes(self):
        self.assertEqual(
            {
                path.name
                for path in (
                    self.generated / "FlightLog.iconset"
                ).glob("*.png")
            },
            set(EXPECTED_SIZES),
        )
        for filename, expected_size in EXPECTED_SIZES.items():
            path = self.generated / "FlightLog.iconset" / filename
            self.assertEqual(sips_property(path, "pixelWidth"), str(expected_size))
            self.assertEqual(sips_property(path, "pixelHeight"), str(expected_size))

    def test_icns_round_trips_through_iconutil(self):
        with tempfile.TemporaryDirectory() as directory:
            decoded = Path(directory) / "decoded.iconset"
            subprocess.run(
                [
                    "iconutil",
                    "-c",
                    "iconset",
                    "-o",
                    str(decoded),
                    str(self.generated / "FlightLog.icns"),
                ],
                check=True,
            )
            decoded_sizes = {
                path.name: int(sips_property(path, "pixelWidth"))
                for path in decoded.glob("*.png")
            }
        self.assertEqual(decoded_sizes, EXPECTED_SIZES)

    def test_generation_is_reproducible(self):
        before = sha256(self.generated / "FlightLog.icns")
        self.assertEqual(before, V21_ICNS_SHA256)
        with tempfile.TemporaryDirectory() as second_output:
            environment = os.environ.copy()
            environment["FLIGHTLOG_ICON_OUTPUT_DIR"] = second_output
            subprocess.run(
                [str(GENERATOR)],
                cwd="/",
                env=environment,
                check=True,
            )
            after = sha256(Path(second_output) / "FlightLog.icns")
        self.assertEqual(after, before)


if __name__ == "__main__":
    unittest.main()
