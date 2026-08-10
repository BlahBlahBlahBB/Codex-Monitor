import importlib.util
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("p0_probe", Path(__file__).with_name("p0_probe.py"))
probe = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(probe)


class P0ProbeTests(unittest.TestCase):
    def test_redacts_credentials_and_privacy_fields(self):
        result = probe.sanitize({
            "access_token": "secret-value",
            "email": "person@example.test",
            "command": "cat /Users/person/private.txt",
            "totalTokens": 1234,
        })
        self.assertEqual(result["access_token"], "<REDACTED>")
        self.assertEqual(result["email"], "<REDACTED>")
        self.assertEqual(result["command"], "<REDACTED>")
        self.assertEqual(result["totalTokens"], 1234)

    def test_export_never_writes_raw_credentials(self):
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory) / "fixture.json"
            digest = probe.export_fixture({"refresh_token": "raw", "totalTokens": 7}, fixture)
            text = fixture.read_text(encoding="utf-8")
            self.assertNotIn("raw", text)
            self.assertIn("<REDACTED>", text)
            self.assertEqual(len(digest), 64)

    def test_absent_socket_is_not_promoted_to_ready(self):
        status = probe.socket_status(Path("/private/tmp/codex-monitor-p0-no-socket.sock"))
        self.assertEqual(status["status"], "absent")

    def test_sparse_rate_limit_update_preserves_omitted_values(self):
        merged = probe.merge_sparse_rate_limits(
            {"primary": {"usedPercent": 20, "resetsAt": "2026-08-10T00:00:00Z"}},
            {"primary": {"usedPercent": 25}},
        )
        self.assertEqual(merged["primary"]["usedPercent"], 25)
        self.assertEqual(merged["primary"]["resetsAt"], "2026-08-10T00:00:00Z")

    def test_stale_connection_epoch_is_rejected(self):
        self.assertFalse(probe.accept_current_epoch(3, 4))
        self.assertTrue(probe.accept_current_epoch(4, 4))


if __name__ == "__main__":
    unittest.main()
