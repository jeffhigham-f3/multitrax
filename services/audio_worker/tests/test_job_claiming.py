import sys
import types
import unittest
from unittest.mock import patch

if "psycopg" not in sys.modules:
    fake_psycopg = types.ModuleType("psycopg")

    class _FakePsycopgError(Exception):
        pass

    def _connect(*args, **kwargs):  # noqa: ANN001, ANN002
        raise RuntimeError("psycopg.connect should be mocked in tests")

    fake_psycopg.Error = _FakePsycopgError
    fake_psycopg.connect = _connect
    sys.modules["psycopg"] = fake_psycopg

if "psycopg.rows" not in sys.modules:
    fake_rows = types.ModuleType("psycopg.rows")
    fake_rows.dict_row = object()
    sys.modules["psycopg.rows"] = fake_rows

if "supabase" not in sys.modules:
    fake_supabase = types.ModuleType("supabase")

    class _FakeSupabaseClient:
        pass

    def _create_client(*args, **kwargs):  # noqa: ANN001, ANN002
        return _FakeSupabaseClient()

    fake_supabase.Client = _FakeSupabaseClient
    fake_supabase.create_client = _create_client
    sys.modules["supabase"] = fake_supabase

import worker


class _FakeCursor:
    def __init__(self, row=None):
        self.row = row
        self.calls = []

    def execute(self, query, params=None):
        self.calls.append((query, params))

    def fetchone(self):
        return self.row

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False


class _FakeDb:
    def __init__(self, row=None):
        self.cursor_obj = _FakeCursor(row=row)
        self.commits = 0
        self.closed = False

    def cursor(self):
        return self.cursor_obj

    def commit(self):
        self.commits += 1

    def close(self):
        self.closed = True


class JobClaimingTest(unittest.TestCase):
    def _make_worker(self, db):
        instance = worker.AudioWorker.__new__(worker.AudioWorker)
        instance._settings = worker.Settings(
            database_url="postgresql://localhost/postgres",
            supabase_url="http://localhost:54321",
            supabase_service_role_key="service-role",
            poll_interval_seconds=3,
            reconnect_backoff_seconds=2,
            lock_timeout_seconds=120,
            max_attempts=3,
            worker_id="worker-test",
        )
        instance._db = db
        return instance

    def test_claim_job_reclaims_stale_processing_rows(self):
        fake_db = _FakeDb(row={"id": "job-1"})
        test_worker = self._make_worker(fake_db)

        claimed = test_worker._claim_job("render_jobs")

        self.assertEqual(claimed, {"id": "job-1"})
        self.assertEqual(fake_db.commits, 1)
        query, params = fake_db.cursor_obj.calls[0]
        self.assertIn("status = 'processing'", query)
        self.assertIn("attempts < %s", query)
        self.assertEqual(params, (120, 3, "worker-test"))

    def test_fail_exhausted_jobs_rejects_unknown_tables(self):
        test_worker = self._make_worker(_FakeDb())

        with self.assertRaises(ValueError):
            test_worker._fail_exhausted_jobs("other_jobs")

    def test_reconnect_db_replaces_connection(self):
        fake_db = _FakeDb()
        test_worker = self._make_worker(fake_db)
        replacement = _FakeDb()

        with patch("worker.psycopg.connect", return_value=replacement) as connect_mock:
            test_worker._reconnect_db()

        self.assertTrue(fake_db.closed)
        self.assertIs(test_worker._db, replacement)
        connect_mock.assert_called_once()


if __name__ == "__main__":
    unittest.main()
