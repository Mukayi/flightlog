from pathlib import Path
import os
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts/release_app.sh"
ZIP_PUBLISHER = ROOT / "scripts/atomic_publish_zip.sh"
COMMIT_GUARD = ROOT / "scripts/release_commit_guard.sh"


class ReleaseAppScriptContractTests(unittest.TestCase):
    def test_release_script_has_reproducible_safe_pipeline(self):
        self.assertTrue(SCRIPT.is_file())
        text = SCRIPT.read_text(encoding="utf-8")
        for required in (
            "set -euo pipefail",
            "build_app.sh",
            "codesign --verify --deep --strict",
            "/Applications/FlightLog.app",
            "ditto",
            "COPYFILE_DISABLE=1",
            "--sequesterRsrc",
            "--norsrc",
            "--noextattr",
            "__MACOSX",
            "sha256",
            "CFFIXED_USER_HOME",
        ):
            self.assertIn(required, text)
        self.assertNotIn("REAL_STORE", text)
        self.assertNotIn('"${HOME}/Library/Application Support', text)
        self.assertIn('if [[ -n "${SMOKE_PID}" ]]', text)
        self.assertIn('wait "${SMOKE_PID}"', text)
        self.assertIn('if [[ "${commit_observed}" != true ]]', text)
        backup_removal = text.index('rm -rf "${BACKUP_APP}"')
        migration_gate = text.index(
            "ProfileSchemaMigrationTests/"
            "testPackagedReleaseMigratesWALFixtureIdempotentlyAndPreservesFailedSource"
        )
        self.assertGreater(backup_removal, migration_gate)
        success_flag = text.index("RELEASE_SUCCEEDED=true")
        self.assertLess(success_flag, backup_removal)
        self.assertIn('rm -rf "${BACKUP_APP}" 2>/dev/null || true', text)
        self.assertNotIn('rm -f "${ZIP_PATH}"', text)
        self.assertIn('"${ZIP_TEMP}"', text)
        self.assertIn('"${ZIP_PUBLISHER}" "${ZIP_TEMP}" "${ZIP_PATH}"', text)
        publish = text.index(
            '"${ZIP_PUBLISHER}" "${ZIP_TEMP}" "${ZIP_PATH}"'
        )
        expected_hash = text.index(
            'EXPECTED_ZIP_SHA256="$(shasum -a 256 "${ZIP_TEMP}"'
        )
        expected_size = text.index('EXPECTED_ZIP_SIZE="$(stat -f %z "${ZIP_TEMP}")"')
        self.assertLess(expected_hash, publish)
        self.assertLess(expected_size, publish)
        self.assertLess(publish, success_flag)
        self.assertIn(
            '"${COMMIT_GUARD}" "${ZIP_PATH}" "${EXPECTED_ZIP_SHA256}"',
            text,
        )

    def test_zip_publish_failure_preserves_existing_zip_bytes(self):
        self.assertTrue(ZIP_PUBLISHER.is_file())
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            final_zip = directory / "FlightLog-macOS-arm64.zip"
            temporary_zip = directory / ".FlightLog.zip.tmp"
            old_bytes = b"verified old zip bytes"
            final_zip.write_bytes(old_bytes)
            temporary_zip.write_bytes(b"unpublished replacement bytes")
            environment = os.environ.copy()
            environment["FLIGHTLOG_TEST_FAIL_ZIP_PUBLISH"] = "1"

            result = subprocess.run(
                [str(ZIP_PUBLISHER), str(temporary_zip), str(final_zip)],
                env=environment,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(final_zip.read_bytes(), old_bytes)
            self.assertTrue(temporary_zip.is_file())

    def test_before_publish_fault_rolls_back_app_and_preserves_old_zip(self):
        result = self._simulate_release_commit("before")
        self.assertNotEqual(result["returncode"], 0)
        self.assertEqual(result["installed"], b"old app")
        self.assertEqual(result["zip"], b"old zip")

    def test_after_publish_fault_keeps_new_app_and_new_zip(self):
        result = self._simulate_release_commit("after")
        self.assertNotEqual(result["returncode"], 0)
        self.assertEqual(result["installed"], b"new app")
        self.assertEqual(result["zip"], b"new zip")

    def _simulate_release_commit(self, fault):
        self.assertTrue(ZIP_PUBLISHER.is_file())
        self.assertTrue(COMMIT_GUARD.is_file())
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            installed_app = directory / "installed.app"
            backup_app = directory / "backup.app"
            final_zip = directory / "FlightLog.zip"
            temporary_zip = directory / "FlightLog.zip.tmp"
            installed_app.write_bytes(b"new app")
            backup_app.write_bytes(b"old app")
            final_zip.write_bytes(b"old zip")
            temporary_zip.write_bytes(b"new zip")
            expected_hash = subprocess.check_output(
                ["shasum", "-a", "256", str(temporary_zip)],
                text=True,
            ).split()[0]
            environment = os.environ.copy()
            if fault == "before":
                environment["FLIGHTLOG_TEST_FAIL_ZIP_PUBLISH"] = "1"
            else:
                environment["FLIGHTLOG_TEST_FAIL_ZIP_AFTER_MV"] = "1"
            harness = r'''
set -euo pipefail
publisher="$1"
guard="$2"
temporary_zip="$3"
final_zip="$4"
installed_app="$5"
backup_app="$6"
expected_hash="$7"
succeeded=false
cleanup() {
    set +e
    if [[ "${succeeded}" != true ]] \
        && ! "${guard}" "${final_zip}" "${expected_hash}"; then
        rm -f "${installed_app}"
        mv "${backup_app}" "${installed_app}"
    fi
}
trap cleanup EXIT
"${publisher}" "${temporary_zip}" "${final_zip}"
succeeded=true
rm -f "${backup_app}" 2>/dev/null || true
'''
            completed = subprocess.run(
                [
                    "bash",
                    "-c",
                    harness,
                    "release-window-test",
                    str(ZIP_PUBLISHER),
                    str(COMMIT_GUARD),
                    str(temporary_zip),
                    str(final_zip),
                    str(installed_app),
                    str(backup_app),
                    expected_hash,
                ],
                env=environment,
                check=False,
            )
            return {
                "returncode": completed.returncode,
                "installed": installed_app.read_bytes(),
                "zip": final_zip.read_bytes(),
            }


if __name__ == "__main__":
    unittest.main()
