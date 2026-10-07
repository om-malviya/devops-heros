"""API tests for the TaskBoard backend (run against a temporary SQLite database, see conftest.py)."""


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "UP"}


def test_ready_checks_database(client):
    response = client.get("/ready")
    assert response.status_code == 200
    assert response.json() == {"status": "READY"}


def test_root(client):
    response = client.get("/")
    assert response.status_code == 200
    body = response.json()
    assert body["service"] == "TaskBoard API"
    assert body["env"] == "test"


def test_metrics_endpoint_is_prometheus_format(client):
    client.get("/health")  # generate at least one request sample
    response = client.get("/metrics")
    assert response.status_code == 200
    assert "http_requests_total" in response.text


def test_create_task(client):
    response = client.post("/api/tasks", json={"title": "Deploy application", "priority": "HIGH", "assignee": "Om Malviya"})
    assert response.status_code == 201
    body = response.json()
    assert body["title"] == "Deploy application"
    assert body["status"] == "TODO"
    assert body["priority"] == "HIGH"
    assert "id" in body and "created_at" in body


def test_create_task_validation_error(client):
    # empty title and unknown priority must be rejected by the Pydantic schema
    response = client.post("/api/tasks", json={"title": "", "priority": "URGENT"})
    assert response.status_code == 422


def test_list_tasks_contains_created_task(client, task):
    response = client.get("/api/tasks")
    assert response.status_code == 200
    ids = [t["id"] for t in response.json()]
    assert task["id"] in ids


def test_get_task_by_id(client, task):
    response = client.get(f"/api/tasks/{task['id']}")
    assert response.status_code == 200
    assert response.json()["title"] == "Fixture task"


def test_get_missing_task_returns_404(client):
    response = client.get("/api/tasks/999999")
    assert response.status_code == 404
    assert response.json()["detail"] == "Task not found"


def test_update_task_status(client, task):
    response = client.put(f"/api/tasks/{task['id']}", json={"status": "IN_PROGRESS"})
    assert response.status_code == 200
    assert response.json()["status"] == "IN_PROGRESS"
    # fields that were not sent stay unchanged
    assert response.json()["title"] == "Fixture task"


def test_delete_task(client, task):
    response = client.delete(f"/api/tasks/{task['id']}")
    assert response.status_code == 204
    assert client.get(f"/api/tasks/{task['id']}").status_code == 404


def test_stats_counts_match_list(client, task):
    client.put(f"/api/tasks/{task['id']}", json={"status": "DONE"})
    stats = client.get("/api/tasks/stats").json()
    tasks = client.get("/api/tasks").json()
    assert stats["total"] == len(tasks)
    assert stats["done"] == len([t for t in tasks if t["status"] == "DONE"])
    assert stats["total"] == stats["todo"] + stats["inProgress"] + stats["done"]
