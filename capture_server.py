#!/usr/bin/env python3
"""Local-only WebGL serving and completed-trace saving for Metal Web Capture Lab."""
from __future__ import annotations

import json
import argparse
import shutil
import subprocess
import tempfile
import time
from datetime import datetime
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent
CAPTURES = ROOT / "captures"
APP = ROOT / "app.html"
WEBKIT_TRACE_DIR = Path(tempfile.gettempdir()) / "com.apple.WebKit.GPU+org.webkit.MiniBrowser"
CLOCK_READY_AT = 0.0


def trace_paths():
    return {path.resolve() for path in WEBKIT_TRACE_DIR.glob("*.gputrace")}


def trace_snapshot(trace):
    """A complete trace is a directory; wait until its contents stop changing."""
    entries = [path for path in trace.rglob("*") if path.is_file()]
    return (len(entries), sum(path.stat().st_size for path in entries), max((path.stat().st_mtime_ns for path in entries), default=0))


def has_xcode_index(trace):
    return all((trace / name).is_file() and (trace / name).stat().st_size > 0 for name in ("index", "capture", "metadata"))


def wait_until_complete(trace):
    previous = None
    stable_samples = 0
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        snapshot = trace_snapshot(trace)
        stable_samples = stable_samples + 1 if snapshot == previous else 0
        if has_xcode_index(trace) and stable_samples >= 10:  # Five quiet seconds, with Xcode's required index files.
            return True
        previous = snapshot
        time.sleep(.5)
    return False


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def send_json(self, status, payload):
        encoded = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def do_GET(self):
        global CLOCK_READY_AT
        path = urlparse(self.path).path
        if path == "/":
            data = APP.read_bytes()
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if path == "/api/status":
            self.send_json(HTTPStatus.OK, {"captureClockReady": bool(CLOCK_READY_AT)})
            return
        return super().do_GET()

    def do_POST(self):
        global CLOCK_READY_AT
        path = urlparse(self.path).path
        if path == "/api/clock-ready":
            CLOCK_READY_AT = time.time()
            self.send_json(HTTPStatus.NO_CONTENT, {})
        elif path == "/api/capture":
            self.capture(self.command_count())
        else:
            self.send_error(HTTPStatus.NOT_FOUND)

    def command_count(self):
        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length) or b"{}")
            return max(1, min(2000, int(payload.get("commands", 3))))
        except (TypeError, ValueError, json.JSONDecodeError):
            return 3

    def capture(self, commands):
        if not CLOCK_READY_AT:
            self.send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": "WebGPU capture clock is not ready. Reload the lab with ./run.command."})
            return
        before = trace_paths()
        started = time.time()
        try:
            subprocess.run(["notifyutil", "-s", "com.apple.WebKit.WebGPU.CaptureFrame", str(commands)], check=True)
            subprocess.run(["notifyutil", "-p", "com.apple.WebKit.WebGPU.CaptureFrame"], check=True)
        except (OSError, subprocess.CalledProcessError) as error:
            self.send_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": str(error)})
            return
        deadline = time.monotonic() + 20
        trace = None
        while time.monotonic() < deadline:
            candidates = [p for p in trace_paths() - before if p.stat().st_mtime >= started - 1]
            if candidates:
                trace = max(candidates, key=lambda p: p.stat().st_mtime)
                break
            time.sleep(.25)
        if not trace:
            self.send_json(HTTPStatus.GATEWAY_TIMEOUT, {"error": "No trace arrived. Is MiniBrowser running the preview?"})
            return
        if not wait_until_complete(trace):
            self.send_json(HTTPStatus.GATEWAY_TIMEOUT, {"error": "The trace did not finish writing in time."})
            return
        CAPTURES.mkdir(exist_ok=True)
        name = f"capture-{datetime.now().strftime('%Y%m%d-%H%M%S')}.gputrace"
        staging = CAPTURES / f".{name}.partial"
        shutil.copytree(trace, staging)
        if not has_xcode_index(staging):
            shutil.rmtree(staging)
            self.send_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": "Trace finished without an Xcode index."})
            return
        staging.replace(CAPTURES / name)  # Xcode can only see a completed trace.
        self.send_json(HTTPStatus.OK, {"name": name, "path": str((CAPTURES / name).resolve())})


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Serve the local Metal Web Capture Lab.")
    parser.add_argument("--port", type=int, default=8000)
    options = parser.parse_args()
    print(f"Metal Web Capture Lab: http://127.0.0.1:{options.port}")
    ThreadingHTTPServer(("127.0.0.1", options.port), Handler).serve_forever()
