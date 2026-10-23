import os
import hashlib
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import textwrap
import unittest


class BuildAppScriptContractTests(unittest.TestCase):
    def test_runs_build_tools_from_project_root_when_invoked_elsewhere(self):
        source_script = Path(__file__).with_name("build_app.sh")

        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_root = Path(temporary_directory)
            project_root = temporary_root / "project"
            scripts_directory = project_root / "scripts"
            outside_directory = temporary_root / "outside"
            fake_bin = temporary_root / "bin"
            cwd_log = temporary_root / "build-tool-cwds.txt"
            scripts_directory.mkdir(parents=True)
            outside_directory.mkdir()
            fake_bin.mkdir()

            copied_script = scripts_directory / "build_app.sh"
            shutil.copy2(source_script, copied_script)
            shutil.copy2(
                source_script.with_name("check_release_binary.sh"),
                scripts_directory / "check_release_binary.sh",
            )
            shutil.copy2(
                source_script.with_name("validate_airport_resources.py"),
                scripts_directory / "validate_airport_resources.py",
            )
            shutil.copy2(
                source_script.with_name("verify_app_icon.py"),
                scripts_directory / "verify_app_icon.py",
            )
            self._write_executable(
                scripts_directory / "generate_icon.sh",
                """
                #!/bin/bash
                set -euo pipefail
                test "${PWD}" = "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
                mkdir -p Assets
                printf 'fixture-flightlog-icns\n' > Assets/FlightLog.icns
                """,
            )
            self._write_executable(
                fake_bin / "xcodebuild",
                """
                #!/bin/sh
                echo "build_app.sh must not use xcodebuild" >&2
                exit 99
                """,
            )
            self._write_executable(
                fake_bin / "swift",
                """
                #!/bin/bash
                set -euo pipefail
                printf '%s\n' "${PWD}" >> "${FLIGHTLOG_TEST_CWD_LOG}"

                scratch_path=""
                show_bin_path=false
                while [[ $# -gt 0 ]]; do
                    case "$1" in
                        --scratch-path)
                            scratch_path="$2"
                            shift 2
                            ;;
                        --show-bin-path)
                            show_bin_path=true
                            shift
                            ;;
                        *)
                            shift
                            ;;
                    esac
                done

                products="${scratch_path}/test-triple/release"
                if [[ "${show_bin_path}" == true ]]; then
                    printf '%s\n' "${products}"
                    exit 0
                fi

                resources="${products}/FlightLog_FlightLog.bundle"
                mkdir -p "${resources}"
                printf '%s\n' \
                    '#!/bin/bash' \
                    'set -euo pipefail' \
                    'test "${HOME}" = "${CFFIXED_USER_HOME}"' \
                    'mkdir -p "${HOME}/Library/Application Support/FlightLog"' \
                    'printf fixture > "${HOME}/Library/Application Support/FlightLog/FlightLog.store"' \
                    'sleep 30' \
                    > "${products}/FlightLog"
                chmod +x "${products}/FlightLog"
                python3 -c 'import json,sys; required=[("PEK",["北京"]),("PKX",["北京大兴"]),("PVG",["浦东"]),("HND",["羽田"]),("LHR",["希思罗"]),("JFK",["肯尼迪"])]; rows=[{"iata":iata,"aliases":aliases} for iata,aliases in required]; rows.extend({"iata":f"T{index:04d}","aliases":[]} for index in range(9000-len(rows))); json.dump(rows,open(sys.argv[1],"w",encoding="utf-8"),ensure_ascii=False)' "${resources}/airports.json"
                printf '%s\n' \
                    'Airport data generated on 2026-08-19.' \
                    'Wikidata aliases: CC0 1.0.' \
                    > "${resources}/AIRPORT_DATA_LICENSE.md"
                """,
            )
            self._write_executable(
                fake_bin / "codesign",
                """
                #!/bin/sh
                exit 0
                """,
            )
            self._write_executable(
                fake_bin / "open",
                """
                #!/bin/bash
                set -euo pipefail
                app="${!#}"
                while [[ $# -gt 1 ]]; do
                    if [[ "$1" == "--env" ]]; then
                        export "$2"
                        shift 2
                    else
                        shift
                    fi
                done
                "${app}/Contents/MacOS/FlightLog" &
                """,
            )
            self._write_executable(
                fake_bin / "otool",
                """
                #!/bin/sh
                echo "segname __TEXT"
                """,
            )
            self._write_executable(
                fake_bin / "nm",
                """
                #!/bin/sh
                exit 0
                """,
            )

            environment = os.environ.copy()
            environment["PATH"] = f"{fake_bin}:{environment['PATH']}"
            environment["FLIGHTLOG_TEST_CWD_LOG"] = str(cwd_log)
            environment["OPEN_COMMAND"] = str(fake_bin / "open")
            result = subprocess.run(
                [str(copied_script)],
                cwd=outside_directory,
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            build_tool_working_directories = cwd_log.read_text(
                encoding="utf-8"
            ).splitlines()
            self.assertEqual(len(build_tool_working_directories), 2)
            self.assertTrue(
                all(
                    Path(directory).samefile(project_root)
                    for directory in build_tool_working_directories
                )
            )
            self.assertTrue(
                (project_root / "dist/FlightLog.app/Contents/MacOS/FlightLog")
                .is_file()
            )
            resources = (
                project_root / "dist/FlightLog.app/Contents/Resources"
            )
            self.assertTrue((resources / "airports.json").is_file())
            self.assertTrue((resources / "AIRPORT_DATA_LICENSE.md").is_file())
            packaged_icon = resources / "FlightLog.icns"
            generated_icon = project_root / "Assets/FlightLog.icns"
            self.assertTrue(packaged_icon.is_file())
            self.assertEqual(
                hashlib.sha256(packaged_icon.read_bytes()).hexdigest(),
                hashlib.sha256(generated_icon.read_bytes()).hexdigest(),
            )
            self.assertFalse(
                (resources / "FlightLog_FlightLog.bundle").exists(),
                "app 只应打包 Contents/Resources 下的一份 raw 机场资源",
            )
            self.assertIn("隔离 HOME 正常 launch smoke 通过", result.stdout)
            self.assertIn("App 图标验证通过", result.stdout)
            self.assertNotIn("FLIGHTLOG_RESOURCE_SMOKE_MARKER", source_script.read_text())
            with (
                project_root / "dist/FlightLog.app/Contents/Info.plist"
            ).open("rb") as info_file:
                info = plistlib.load(info_file)
            self.assertEqual(
                info["CFBundleShortVersionString"],
                info["CFBundleVersion"],
            )
            self.assertEqual(info["CFBundleIconFile"], "FlightLog.icns")

    def _write_executable(self, path: Path, contents: str) -> None:
        path.write_text(
            textwrap.dedent(contents).lstrip(),
            encoding="utf-8",
        )
        path.chmod(0o755)


if __name__ == "__main__":
    unittest.main()
