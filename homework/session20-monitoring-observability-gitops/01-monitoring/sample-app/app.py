#!/usr/bin/env python3
"""Tiny HTTP service that exposes Prometheus metrics.

Endpoints:
  /         -> normal request (200)
  /slow     -> sleeps 0.3-0.8s so the latency histogram has something to show
  /error    -> always returns 500 so the error-rate alert can be demonstrated
  /health   -> JSON health check used by Docker/Kubernetes probes
  /metrics  -> Prometheus exposition format
"""
import json
import os
import random
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from prometheus_client import (CONTENT_TYPE_LATEST, Counter, Gauge, Histogram,
                               generate_latest)

# --- the three metric types we want to demonstrate -------------------------
REQUESTS = Counter(
    "app_requests_total",
    "Total HTTP requests handled by the sample app",
    ["method", "path", "status"],
)
LATENCY = Histogram(
    "app_request_duration_seconds",
    "Request latency in seconds",
    ["path"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5),
)
IN_PROGRESS = Gauge(
    "app_in_progress_requests",
    "Number of requests currently being handled",
)
START_TIME = Gauge(
    "app_start_time_seconds",
    "Unix timestamp at which the sample app started",
)
START_TIME.set(time.time())


class Handler(BaseHTTPRequestHandler):
    def _send(self, status, body, content_type="text/plain; charset=utf-8"):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # noqa: N802 (BaseHTTPRequestHandler API)
        path = self.path.split("?")[0]
        if path == "/metrics":
            # Scrapes are not counted as application traffic.
            self._send(200, generate_latest(), CONTENT_TYPE_LATEST)
            return

        IN_PROGRESS.inc()
        started = time.perf_counter()
        try:
            if path == "/health":
                status, body = 200, json.dumps({"status": "ok"}).encode()
                self._send(status, body, "application/json")
                return
            elif path == "/slow":
                time.sleep(random.uniform(0.3, 0.8))
                status, body = 200, b"slow response\n"
            elif path == "/error":
                status, body = 500, b"simulated failure\n"
            elif path == "/":
                status, body = 200, b"hello from session20 sample app\n"
            else:
                status, body = 404, b"not found\n"
            self._send(status, body)
        finally:
            LATENCY.labels(path=path).observe(time.perf_counter() - started)
            REQUESTS.labels(method="GET", path=path, status=str(status)).inc()
            IN_PROGRESS.dec()

    def log_message(self, fmt, *args):
        # One structured-ish log line per request: this is the "logs" pillar.
        print(f'{time.strftime("%Y-%m-%dT%H:%M:%S")} INFO {self.address_string()} {fmt % args}', flush=True)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8000"))
    print(f"sample-app listening on :{port} (metrics at /metrics)", flush=True)
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
