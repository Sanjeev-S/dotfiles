"""Run with python3 -B -m unittest discover -s docs/tests -v."""

import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest


REPO = Path(__file__).resolve().parents[2]


class DotupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dotup-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.state = self.root / ".local/state/dotup"
        self.state.mkdir(parents=True)
        self.bin = self.root / ".local/bin"
        self.bin.mkdir(parents=True)
        # Redirect path references in the fixture, without changing HOME or
        # allowing any real updater or credential helper to execute.
        source = (REPO / "dot_local/bin/executable_dotup").read_text()
        self.script = self.root / "dotup"
        self.script.write_text(source.replace("$HOME", str(self.root)))
        self.write_command("chezmoi", '''
echo entered >> "$FIXTURE/entries"
touch "$FIXTURE/entered"
while [ -e "$FIXTURE/hold" ]; do sleep 0.05; done
''')
        for name in ("secrets-refresh", "sync-skills", "npm"):
            self.write_command(name, "exit 0\n")
        self.write_command("curl", '''
if [ -e "$FIXTURE/fail" ] && [[ "$*" == *claude.ai* ]]; then
  echo 'exit 9'
else
  echo 'exit 0'
fi
''')
        self.env = dict(os.environ, FIXTURE=str(self.root),
                        SHELL="/bin/zsh", ZSH_CUSTOM=str(self.root / ".oh-my-zsh/custom"),
                        COMPOSIO_INSTALL_DIR=str(self.root / ".composio"),
                        PATH=f"{self.bin}:/usr/bin:/bin:/usr/sbin:/sbin")
        for plugin in ("zsh-autosuggestions", "zsh-syntax-highlighting"):
            (self.root / ".oh-my-zsh/custom/plugins" / plugin).mkdir(parents=True)

    def write_command(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/bash\n" + body)
        path.chmod(0o755)

    def run_dotup(self, *args):
        process = subprocess.Popen(["/bin/bash", str(self.script), *args],
                                   env=self.env, text=True, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, start_new_session=True)
        try:
            out, err = process.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            out, err = process.communicate(timeout=3)
            self.fail(f"dotup did not finish: {out}{err}")
        return subprocess.CompletedProcess(process.args, process.returncode, out, err)

    def start_blocked(self):
        (self.root / "hold").touch()
        process = subprocess.Popen(["/bin/bash", str(self.script), "--force"],
                                   env=self.env, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL,
                                   start_new_session=True)

        def stop():
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=5)

        self.addCleanup(stop)
        deadline = time.monotonic() + 5
        while not (self.root / "entered").exists():
            if process.poll() is not None or time.monotonic() > deadline:
                self.fail("first run did not enter chezmoi")
            time.sleep(0.02)
        return process

    def test_concurrent_force_skips_without_changing_log_or_markers(self):
        (self.state / "last-failure").write_text("previous failure\n")
        first = self.start_blocked()
        before = (self.state / "last-run.log").read_text()
        second = self.run_dotup("--force")
        self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
        self.assertIn("another run is active", second.stdout)
        self.assertEqual((self.root / "entries").read_text(), "entered\n")
        self.assertEqual((self.state / "last-run.log").read_text(), before)
        self.assertEqual((self.state / "last-failure").read_text(), "previous failure\n")
        self.assertFalse((self.state / "last-success").exists())
        (self.root / "hold").unlink()
        self.assertEqual(first.wait(timeout=5), 0)

    def test_failure_recovery_and_daily_gate(self):
        (self.root / "fail").touch()
        result = self.run_dotup("--force")
        self.assertEqual(result.returncode, 1)
        self.assertIn('"failed":"claude"', (self.state / "last-failure").read_text())
        self.assertFalse((self.state / "last-success").exists())
        (self.root / "fail").unlink()
        self.assertEqual(self.run_dotup("--force").returncode, 0)
        self.assertFalse((self.state / "last-failure").exists())
        self.assertTrue((self.state / "last-success").exists())
        self.assertEqual(self.run_dotup().returncode, 0)
        self.assertEqual((self.root / "entries").read_text(), "entered\nentered\n")

    def test_lock_recovers_after_process_group_is_killed(self):
        first = self.start_blocked()
        os.killpg(first.pid, signal.SIGKILL)
        first.wait(timeout=5)
        (self.root / "hold").unlink()
        result = self.run_dotup("--force")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("==> dotup ok", result.stdout)

    def test_existing_tailscale_app_does_not_invoke_brew_install(self):
        source = (REPO / ".chezmoiscripts/run_onchange_before_02-install-packages.sh.tmpl").read_text()
        # Exercise the laptop branch on either test host, with no config secrets.
        rendered = subprocess.run(
            ["chezmoi", "execute-template", "--override-data",
             '{"chezmoi":{"os":"darwin"},"machine_type":"mac-personal"}'],
            input=source, text=True, capture_output=True, check=True).stdout
        apps = self.root / "Applications"
        (apps / "Tailscale.app").mkdir(parents=True)
        (apps / "Karabiner-Elements.app").mkdir()
        self.write_command("brew", 'echo "$*" >> "$FIXTURE/brew-calls"\n')
        self.write_command("bun", "exit 0\n")
        composio = self.root / ".composio/composio"
        composio.parent.mkdir()
        composio.touch()
        composio.chmod(0o755)
        script = rendered.replace("$HOME", str(self.root)).replace("/Applications/", f"{apps}/")
        subprocess.run(["/bin/bash"], input=script, text=True, env=self.env,
                       capture_output=True, check=True, timeout=5)
        calls = (self.root / "brew-calls").read_text()
        self.assertNotIn("tailscale-app", calls)
        # Bootstrap must still install the app when it is absent.
        (apps / "Tailscale.app").rmdir()
        subprocess.run(["/bin/bash"], input=script, text=True, env=self.env,
                       capture_output=True, check=True, timeout=5)
        self.assertIn("install --cask --adopt tailscale-app",
                      (self.root / "brew-calls").read_text())


if __name__ == "__main__":
    unittest.main()
