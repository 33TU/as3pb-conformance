"""Smoke tests for the compiled Node testee's binary stdio framing."""

import pathlib
import struct
import subprocess
import time
import unittest

RUNNER = pathlib.Path(__file__).with_name("run.sh")


def frame(payload):
    return struct.pack("<I", len(payload)) + payload


class TransportTest(unittest.TestCase):
    # ConformanceRequest.message_type = "x"; ConformanceResponse.skipped.
    request = frame(b"\x22\x01x")
    reason = b"unsupported message type: x"
    response = frame(b"\x2a" + bytes([len(reason)]) + reason)

    def run_testee(self, data):
        return subprocess.run([str(RUNNER)], input=data, capture_output=True, timeout=10)

    def test_clean_eof(self):
        result = self.run_testee(b"")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, b"")

    def test_multiple_frames(self):
        result = self.run_testee(self.request * 3)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, self.response * 3)

    def test_fragmented_frame(self):
        with subprocess.Popen([str(RUNNER)], stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE) as process:
            try:
                for byte in self.request:
                    process.stdin.write(bytes([byte]))
                    process.stdin.flush()
                    time.sleep(0.01)
                process.stdin.close()
                process.stdin = None
                stdout, stderr = process.communicate(timeout=10)
                self.assertEqual(process.returncode, 0, stderr)
                self.assertEqual(stdout, self.response)
            finally:
                if process.poll() is None:
                    process.kill()

    def test_truncated_frames(self):
        for data in (b"\x03\x00", frame(b"abc")[:-1]):
            with self.subTest(data=data):
                result = self.run_testee(data)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, b"")
                self.assertIn(b"Truncated conformance frame", result.stderr)


if __name__ == "__main__":
    unittest.main()
