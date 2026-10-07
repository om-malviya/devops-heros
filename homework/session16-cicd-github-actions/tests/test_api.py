import pytest

from app.main import app


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as c:
        yield c


def test_index(client):
    res = client.get("/")
    assert res.status_code == 200
    assert res.get_json()["app"] == "session16-calculator-api"


def test_health(client):
    res = client.get("/health")
    assert res.status_code == 200
    assert res.get_json() == {"status": "ok"}


def test_calc_add(client):
    res = client.get("/api/calc?a=10&b=5&op=add")
    assert res.status_code == 200
    assert res.get_json()["result"] == 15


def test_calc_default_op_is_add(client):
    res = client.get("/api/calc?a=1&b=2")
    assert res.get_json()["result"] == 3


def test_calc_missing_param(client):
    res = client.get("/api/calc?a=10&op=add")
    assert res.status_code == 400


def test_calc_not_a_number(client):
    res = client.get("/api/calc?a=ten&b=5&op=add")
    assert res.status_code == 400


def test_calc_unknown_op(client):
    res = client.get("/api/calc?a=10&b=5&op=pow")
    assert res.status_code == 400


def test_calc_divide_by_zero(client):
    res = client.get("/api/calc?a=10&b=0&op=div")
    assert res.status_code == 400
    assert "zero" in res.get_json()["error"]


def test_unknown_route(client):
    assert client.get("/nope").status_code == 404


@pytest.mark.parametrize("bad", ["nan", "NaN", "inf", "-Infinity"])
def test_calc_rejects_nan_and_inf(client, bad):
    res = client.get(f"/api/calc?a={bad}&b=1&op=add")
    assert res.status_code == 400
