"""Pytest configuration.

The tests must never touch the production PostgreSQL database, so before the
application is imported we point DATABASE_URL at a throw-away SQLite file.
This works both locally (no Postgres required) and in GitHub Actions.
"""
import os
import tempfile

import pytest

_TEST_DB = os.path.join(tempfile.gettempdir(), "taskboard-test.db")
if os.path.exists(_TEST_DB):
    os.remove(_TEST_DB)
os.environ["DATABASE_URL"] = f"sqlite:///{_TEST_DB}"
os.environ["APP_ENV"] = "test"

from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402


@pytest.fixture(scope="session")
def client():
    # Using the TestClient as a context manager runs the FastAPI startup hook (create_all).
    with TestClient(app) as c:
        yield c


@pytest.fixture()
def task(client):
    payload = {"title": "Fixture task", "description": "created by fixture", "priority": "LOW", "assignee": "Om Malviya"}
    response = client.post("/api/tasks", json=payload)
    assert response.status_code == 201
    return response.json()
