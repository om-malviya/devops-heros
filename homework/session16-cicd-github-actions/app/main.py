"""Small Flask API around the calculator module.

Endpoints:
  GET /                      -> service info
  GET /health                -> liveness/readiness probe
  GET /api/calc?a=&b=&op=    -> op in add|sub|mul|div
"""
import math
import os

from flask import Flask, jsonify, request

from app.calculator import OPERATIONS, calculate

APP_NAME = "session16-calculator-api"
APP_VERSION = os.getenv("APP_VERSION", "1.0.0")
GIT_SHA = os.getenv("GIT_SHA", "local")

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
            "endpoints": ["/", "/health", "/api/calc?a=10&b=5&op=add"],
            "operations": sorted(OPERATIONS),
        }
    )


@app.get("/health")
def health():
    return jsonify({"status": "ok"}), 200


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
    # Local development only. In the container the app is served by gunicorn.
    app.run(host="127.0.0.1", port=int(os.getenv("PORT", "8000")))
