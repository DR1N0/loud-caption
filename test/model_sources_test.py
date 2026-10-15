import hashlib
import unittest

from scripts.fetch_models import matches_sha256


class ModelSourcesTest(unittest.TestCase):
    def test_digest_rejects_changed_bytes(self):
        data = b"model payload"
        self.assertTrue(matches_sha256(data, hashlib.sha256(data).hexdigest()))
        self.assertFalse(matches_sha256(data + b"x", hashlib.sha256(data).hexdigest()))
