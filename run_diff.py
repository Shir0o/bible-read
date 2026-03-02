import subprocess
import os

try:
    res = subprocess.run(["git", "diff", "--stat", "origin/main...HEAD"], capture_output=True, text=True, check=True)
    if not res.stdout.strip():
        # Try finding parent commits if origin/main doesn't work
        res = subprocess.run(["git", "diff", "--stat", "HEAD~1"], capture_output=True, text=True, check=True)
    print(res.stdout)
except Exception as e:
    print(e)
