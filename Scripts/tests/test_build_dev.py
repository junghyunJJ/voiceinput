import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


class BuildDevTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory(prefix="VoiceInput build test ")
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name)
        self.project = self.root / "package with spaces"
        scripts = self.project / "Scripts"
        scripts.mkdir(parents=True)
        self.script = scripts / "build-dev.sh"
        shutil.copyfile(Path(__file__).resolve().parents[1] / "build-dev.sh", self.script)
        self.binary_directory = self.project / "new build products"
        self.log = self.root / "commands.jsonl"
        fake_bin = self.root / "bin"
        fake_bin.mkdir()
        stub = f"#!{sys.executable}\n" + r"""
import json
import os
from pathlib import Path
import sys

name = Path(sys.argv[0]).name
with open(os.environ["VOICEINPUT_TEST_LOG"], "a") as log:
    log.write(json.dumps({"tool": name, "args": sys.argv[1:], "cwd": os.getcwd()}) + "\n")
if name == "swift":
    if "--show-bin-path" in sys.argv:
        print(os.environ["VOICEINPUT_TEST_BIN_DIR"])
    elif os.environ.get("VOICEINPUT_TEST_BUILD_FAILURE") == "1":
        sys.exit(1)
"""
        for name in ["swift", "cp", "mkdir", "pkill", "sleep", "codesign", "open"]:
            executable = fake_bin / name
            executable.write_text(stub)
            executable.chmod(0o755)
        self.environment = dict(os.environ)
        self.environment.update(
            PATH=f"{fake_bin}:{os.environ['PATH']}",
            SIGNING_IDENTITY="-",
            VOICEINPUT_TEST_LOG=str(self.log),
            VOICEINPUT_TEST_BIN_DIR=str(self.binary_directory),
        )

    def run_script(self):
        result = subprocess.run(
            ["/bin/bash", str(self.script)],
            cwd=self.root,
            env=self.environment,
            capture_output=True,
            text=True,
        )
        commands = [json.loads(line) for line in self.log.read_text().splitlines()]
        return result, commands

    def test_installs_the_binary_reported_by_swift(self):
        result, commands = self.run_script()

        self.assertEqual(result.returncode, 0, result.stderr)
        binary_copy = next(command for command in commands if command["tool"] == "cp")
        self.assertEqual(binary_copy["args"][0], str(self.binary_directory / "VoiceInput"))

    def test_builds_this_package_when_called_from_another_directory(self):
        result, commands = self.run_script()

        self.assertEqual(result.returncode, 0, result.stderr)
        build = next(command for command in commands if command["tool"] == "swift")
        if "--package-path" in build["args"]:
            index = build["args"].index("--package-path")
            self.assertEqual(build["args"][index + 1], str(self.project))
        else:
            self.assertEqual(build["cwd"], str(self.project))

    def test_does_not_install_when_the_build_fails(self):
        self.environment["VOICEINPUT_TEST_BUILD_FAILURE"] = "1"

        result, commands = self.run_script()

        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(command["tool"] in ["cp", "codesign", "open"] for command in commands))


if __name__ == "__main__":
    unittest.main()
