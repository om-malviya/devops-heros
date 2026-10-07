"""Calculator module (adapted from the course 10-final-cicd-pipeline project).

Pure functions with no side effects so they are easy to unit test.
"""


def add(a, b):
    return a + b


def subtract(a, b):
    return a - b


def multiply(a, b):
    return a * b


def divide(a, b):
    if b == 0:
        raise ValueError("Cannot divide by zero")
    return a / b


# Maps the `op` query parameter of /api/calc to a function.
OPERATIONS = {
    "add": add,
    "sub": subtract,
    "mul": multiply,
    "div": divide,
}


def calculate(op, a, b):
    """Dispatch an operation by name. Raises ValueError for unknown ops."""
    if op not in OPERATIONS:
        raise ValueError(f"Unknown operation '{op}'. Valid: {sorted(OPERATIONS)}")
    return OPERATIONS[op](a, b)


if __name__ == "__main__":
    print("Calculator Application")
    print("----------------------")
    print(f"10 + 5 = {add(10, 5)}")
    print(f"10 - 5 = {subtract(10, 5)}")
    print(f"10 * 5 = {multiply(10, 5)}")
    print(f"10 / 5 = {divide(10, 5)}")
