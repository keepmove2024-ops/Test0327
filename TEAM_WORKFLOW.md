# Team Calculator - GitHub Collaboration Example

## Who Does What

```
GitHub Repository: team/calculator
│
├── Person A  →  feature/addition branch       →  writes add()
├── Person B  →  feature/multiplication branch →  writes multiply()
├── Person C  →  main branch                   →  merges both into Calculator class
└── Person D  →  Read-only access              →  can VIEW code, cannot push
```

---

## Step-by-Step Workflow

### Person A (feature/addition branch)
```bash
git checkout -b feature/addition
# writes person_a_addition.py
git add person_a_addition.py
git commit -m "Add addition function"
git push origin feature/addition
# opens Pull Request → asks C to review and merge
```

### Person B (feature/multiplication branch)
```bash
git checkout -b feature/multiplication
# writes person_b_multiplication.py
git add person_b_multiplication.py
git commit -m "Add multiplication function"
git push origin feature/multiplication
# opens Pull Request → asks C to review and merge
```

### Person C (main branch - manager/lead)
```bash
# Reviews A's Pull Request → clicks Merge
# Reviews B's Pull Request → clicks Merge
git checkout main
git pull origin main        # gets A and B's merged code
# writes calculator.py combining both
git add calculator.py
git commit -m "Create Calculator class using add and multiply"
git push origin main
```

### Person D (read-only / stakeholder)
```
GitHub Settings → Repository → Collaborators
Person D role: "Read"  ← can only VIEW, cannot push or merge

Person D can:
  ✅ View all code
  ✅ Download the code
  ✅ See commit history
  ❌ Cannot push code
  ❌ Cannot merge pull requests
  ❌ Cannot delete anything
```

---

## Final Result

```python
calc = Calculator()
calc.add(3, 5)        # → 8   (A wrote this)
calc.multiply(3, 5)   # → 15  (B wrote this)
```

Nobody steps on each other's work because each person works on their own branch.
C is the only one who merges into main.
D can watch everything but can't break anything.
