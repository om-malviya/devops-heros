import pytest

from app.calculator import add, calculate, divide, multiply, subtract


def test_add():
    assert add(10, 5) == 15


def test_subtract():
    assert subtract(10, 5) == 5


def test_multiply():
    assert multiply(10, 5) == 50


def test_divide():
    assert divide(10, 5) == 2


def test_divide_by_zero():
    with pytest.raises(ValueError):
        divide(10, 0)


@pytest.mark.parametrize(
    "op,a,b,expected",
    [("add", 2, 3, 5), ("sub", 2, 3, -1), ("mul", 2, 3, 6), ("div", 9, 3, 3)],
)
def test_calculate_dispatch(op, a, b, expected):
    assert calculate(op, a, b) == expected


def test_calculate_unknown_op():
    with pytest.raises(ValueError):
        calculate("pow", 2, 3)
