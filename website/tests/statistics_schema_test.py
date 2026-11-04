"""Exercise the real SQL, including retries, concurrent writers and retention."""
import concurrent.futures
from pathlib import Path
import sqlite3
import tempfile
import unittest

SCHEMA=(Path(__file__).resolve().parents[1]/'cloudflare/migrations/0001_statistics.sql').read_text()
INSERT='INSERT OR IGNORE INTO stats_events (id,kind,bucket,created_at) VALUES (?,?,?,?)'

class StatisticsSchemaTests(unittest.TestCase):
    def test_concurrent_retry_deduplication_and_redeploy(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'stats.sqlite'
            with sqlite3.connect(path) as db:
                db.executescript(SCHEMA)
                started=db.execute('SELECT value FROM stats_meta').fetchone()[0]
            def write(i):
                with sqlite3.connect(path,timeout=30) as db:
                    db.execute(INSERT,(str(i%40),'pageview','/zh/',1000000))
            with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
                list(pool.map(write,range(200)))
            with sqlite3.connect(path) as db:
                self.assertEqual(db.execute('SELECT count FROM stats_counters').fetchone()[0],40)
                db.executescript(SCHEMA)
                self.assertEqual(db.execute('SELECT value FROM stats_meta').fetchone()[0],started)
                self.assertEqual(db.execute('SELECT count FROM stats_counters').fetchone()[0],40)
                db.execute(INSERT,('later','download','arm64',1000000+604801))
                self.assertEqual(db.execute('SELECT COUNT(*) FROM stats_events').fetchone()[0],1)
                self.assertEqual(dict(db.execute('SELECT kind,count FROM stats_counters')),
                                 {'pageview':40,'download':1})

if __name__=='__main__':unittest.main()
