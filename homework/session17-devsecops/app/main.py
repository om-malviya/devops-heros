"""Flask API for the Session 17 DevSecOps pipeline.

Written to stay clean under Bandit and Semgrep:
  * no eval/exec, no subprocess, no shell
  * debug mode is never enabled
  * configuration comes from environment variables, never hardcoded secrets
  * only the production server (gunicorn) binds to 0.0.0.0

Endpoints:
  GET /                      -> service info
  GET /health                -> liveness / readiness probe
  GET /api/status            -> runtime status
  GET /api/calc?a=&b=&op=    -> op in add|sub|mul|div
"""
import math
import os
import platform
import sys
import time

from flask import Flask, jsonify, request

from app.calculator import OPERATIONS, calculate

APP_NAME = "session17-devsecops-api"
APP_VERSION = os.getenv("APP_VERSION", "1.0.0")
GIT_SHA = os.getenv("GIT_SHA", "local")
_START = time.monotonic()

app = Flask(__name__)


def _parse_number(raw):
    """Parse a query parameter as a finite number.

    float() happily accepts "nan" and "inf"; rejecting them avoids NaN injection
    (Semgrep rule python.flask.security.injection.nan-injection).
    """
    value = float(raw)
    if math.isnan(value) or math.isinf(value):
        raise ValueError("not a finite number")
    return value


@app.get("/")
def index():
    return jsonify(
        {
            "app": APP_NAME,
            "version": APP_VERSION,
            "git_sha": GIT_SHA,
            "endpoints": ["/", "/health", "/api/status", "/api/calc?a=10&b=5&op=add"],
            "operations": sorted(OPERATIONS),
        }
    )


@app.get("/health")
def health():
    return jsonify({"status": "ok"}), 200


@app.get("/api/status")
def status():
    return jsonify(
        {
            "app": APP_NAME,
            "version": APP_VERSION,
            "git_sha": GIT_SHA,
            "python_version": sys.version.split()[0],
            "platform": platform.system(),
            "uptime_seconds": round(time.monotonic() - _START, 2),
        }
    )


@app.get("/api/calc")
def calc():
    op = request.args.get("op", "add")
    try:
        a = _parse_number(request.args["a"])
        b = _parse_number(request.args["b"])
    except KeyError as missing:
        return jsonify({"error": f"missing query parameter {missing}"}), 400
    except ValueError:
        return jsonify({"error": "a and b must be finite numbers"}), 400

    try:
        result = calculate(op, a, b)
    except ValueError as err:
        return jsonify({"error": str(err)}), 400

    return jsonify({"a": a, "b": b, "op": op, "result": result})


@app.errorhandler(404)
def not_found(_):
    return jsonify({"error": "not found"}), 404


if __name__ == "__main__":
    # Local development only; binds to loopback and never enables debug mode.
    app.run(host="127.0.0.1", port=int(os.getenv("PORT", "8000")))
