import importlib.util
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("ar_p0_probe", Path(__file__).with_name("ar_p0_probe.py"))
probe = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(probe)


class ARP0ProbeTests(unittest.TestCase):
    def test_shape_omits_values(self):
        self.assertEqual(probe._type_shape({"email": "person@example.test", "count": 2}), {"count": "number", "email": "string"})

    def test_digest_changes_without_memory_salt(self):
        first = probe._digest(["thread-a"], b"a" * 32)
        second = probe._digest(["thread-a"], b"b" * 32)
        self.assertNotEqual(first, second)

    def test_event_summary_does_not_retain_reasoning_contents(self):
        result = probe._event_summary([{"method": "item/started", "params": {"threadId": "t", "item": {"type": "reasoning", "content": ["secret"]}}}], {"t"})
        self.assertTrue(result["hidden_reasoning_retained"] is False)
        self.assertEqual(result["item_lifecycle_types"], {"reasoning": 1})


if __name__ == "__main__":
    unittest.main()
