# ============================================
# PERSON C's WORK
# Branch: main (after merging A and B's branches)
# Task: Pull A's and B's code together into one class
# ============================================

# C imports A and B's functions
from person_a_addition import add
from person_b_multiplication import multiply
from person_e_division import divide


class Calculator:
    def add(self, a, b):
        return add(a, b)

    def multiply(self, a, b):
        return multiply(a, b)

    def divide(self, a, b):
        return divide(a, b)


# C runs the full calculator
if __name__ == "__main__":
    calc = Calculator()

    print("=== Calculator ===")
    print(f"3 + 5  = {calc.add(3, 5)}")         # Output: 8
    print(f"3 x 5  = {calc.multiply(3, 5)}")    # Output: 15
    print(f"10 / 2 = {calc.divide(10, 2)}")     # Output: 5.0
    print(f"5  / 0 = {calc.divide(5, 0)}")      # Output: Error
