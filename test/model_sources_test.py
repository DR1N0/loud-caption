import hashlib
import unittest

from scripts.fetch_models import matches_md5


class ModelSourcesTest(unittest.TestCase):
    def test_digest_rejects_changed_bytes(self):
        data = b"model payload"
        self.assertTrue(matches_md5(data, hashlib.md5(data).hexdigest()))
        self.assertFalse(matches_md5(data + b"x", hashlib.md5(data).hexdigest()))
