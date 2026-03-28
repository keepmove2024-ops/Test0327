# ============================================
# PERSON E's WORK
# Branch: feature/division
# Task: Just write the division function
# ============================================

def divide(a, b):
    if b == 0:
        return "Error: Cannot divide by zero"
    return a / b


# E tests their own function before pushing
if __name__ == "__main__":
    print(divide(10, 2))   # Output: 5.0
    print(divide(9, 3))    # Output: 3.0
    print(divide(7, 2))    # Output: 3.5
    print(divide(5, 0))    # Output: Error: Cannot divide by zero
