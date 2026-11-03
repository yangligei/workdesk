#!/usr/bin/env python3
"""Launch the actual bundled app against synthetic scratch data only."""
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import time

repo = Path(__file__).resolve().parents[1]
app = repo / "dist/Workdesk.app/Contents/MacOS/Workdesk"
cli = app.with_name("WorkdeskCLI")
with tempfile.TemporaryDirectory(prefix="workdesk-launch-", dir=os.environ["TMPDIR"]) as temporary:
    root = Path(temporary)
    # A legacy-schema fixture also exercises startup migrations.
    with sqlite3.connect(root / "workdesk.sqlite") as db:
        db.executescript("CREATE TABLE projects(id TEXT PRIMARY KEY,title TEXT NOT NULL); INSERT INTO projects VALUES('fixture','隔离演示');")
    env = dict(os.environ, WORKDESK_DATA_DIR=str(root), WORKDESK_DISABLE_NOTIFICATIONS="1")
    def launch():
        return subprocess.Popen([str(app)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    def wait_for(predicate):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.1)
        raise AssertionError("Timed out")
    process = launch()
    try:
        wait_for(lambda: (root / "projects.json").exists())
        assert process.poll() is None
        # Stop before fixture setup so only the app writes while it runs.
        process.terminate()
        process.communicate(timeout=5)
        token = root / "fixture.key"
        subprocess.check_call([str(cli), "enroll", "--name", "fixture", "--project", "fixture", "--alias", "demo", "--token-file", str(token)], env=env, stdout=subprocess.DEVNULL)
        report = [str(cli), "report", "--source", "fixture", "--alias", "demo", "--token-file", str(token), "--text"]
        queued = subprocess.check_output(report + ["离线排队"], env=env, text=True).strip()
        process = launch()
        wait_for(lambda: (root / "receipts" / queued).exists())
        live = subprocess.check_output(report + ["目录通知实时更新"], env=env, text=True).strip()
        wait_for(lambda: (root / "receipts" / live).exists())
        for filename in (queued, live):
            receipt = json.loads(subprocess.check_output([str(cli), "receipt", filename], env=env))
            assert receipt["outcome"] == "accepted", receipt
        snapshot = json.loads(subprocess.check_output([str(cli), "projects"], env=env))
        assert snapshot[0]["title"] == "隔离演示"
        with sqlite3.connect(root / "workdesk.sqlite") as db:
            assert db.execute("SELECT count(*) FROM events").fetchone()[0] == 2
        assert process.poll() is None
        print("PASS: bundled app legacy migration, startup sweep, live directory event, CLI receipts, project snapshot")
    finally:
        if process.poll() is None:
            process.terminate()
        _, stderr = process.communicate(timeout=5)
        assert not stderr, stderr.decode()
