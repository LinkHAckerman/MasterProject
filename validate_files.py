#!/usr/bin/env python3
"""
Best-effort syntax validation for files touched by today's AI agents.

Reads .agent_state.json for the list of files modified today and checks
each one with whatever lightweight tool is available for its language.

BLOCKING checks (fail the workflow, commit is skipped):
  .py   -> python3 -m py_compile
  .js   -> node --check
  .go   -> gofmt -l        (parses syntax; doesn't need a go.mod)
  .cpp  -> g++ -fsyntax-only
  .rs   -> rustc --emit=metadata (full type-check as a library, no Cargo.toml needed)

ADVISORY checks (printed as a warning only, never blocks the commit):
  .sql  -> sqlite3 parse (schema.sql may use dialect features sqlite
           rejects even when valid for the intended database, so this is
           informational rather than authoritative)

NOT CHECKED (no lightweight tool available without heavier CI setup):
  .cs   (C# - would need a scaffolded .csproj to compile a single file)
  .sol  (Solidity - would need solc + resolved imports, e.g. OpenZeppelin,
         to avoid false failures on legitimate contracts)
  .html/.css/.md - not code in the sense that matters here
"""

import os
import json
import subprocess
import sys

STATE_FILE = ".agent_state.json"


def get_todays_files():
    if not os.path.exists(STATE_FILE):
        return []
    try:
        with open(STATE_FILE, "r") as f:
            return json.load(f).get("modified_files", [])
    except Exception:
        return []


def run(cmd):
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        return result.returncode, (result.stdout + result.stderr).strip()
    except FileNotFoundError:
        return None, f"tool not installed: {cmd[0]}"
    except subprocess.TimeoutExpired:
        return -1, "validation timed out"


def validate_python(path):
    return run(["python3", "-m", "py_compile", path])


def validate_js(path):
    return run(["node", "--check", path])


def validate_go(path):
    return run(["gofmt", "-l", path])


def validate_cpp(path):
    return run(["g++", "-fsyntax-only", "-std=c++17", path])


def validate_rust(path):
    return run(["rustc", "--edition", "2021", "--crate-type", "lib",
                "--emit=metadata", "-o", "/dev/null", path])


def validate_sql_advisory(path):
    return run(["sqlite3", ":memory:", f".read {path}"])


BLOCKING_VALIDATORS = {
    ".py": validate_python,
    ".js": validate_js,
    ".go": validate_go,
    ".cpp": validate_cpp,
    ".rs": validate_rust,
}

ADVISORY_VALIDATORS = {
    ".sql": validate_sql_advisory,
}


def main():
    files = get_todays_files()
    if not files:
        print("No files recorded in .agent_state.json - nothing to validate.")
        return 0

    had_blocking_failure = False

    for path in files:
        if not os.path.exists(path):
            print(f"[SKIP] {path}: file not found.")
            continue

        ext = os.path.splitext(path)[1]

        if ext in BLOCKING_VALIDATORS:
            code, output = BLOCKING_VALIDATORS[ext](path)
            if code is None:
                print(f"[SKIP] {path}: {output}")
            elif code == 0 and not output:
                print(f"[OK]   {path}")
            elif code == 0 and output:
                # e.g. gofmt -l prints the filename itself when formatting
                # differs but syntax is still valid - not a hard failure.
                print(f"[OK]   {path} (tool printed output, but exit code 0): {output}")
            else:
                print(f"[FAIL] {path}:\n{output}")
                had_blocking_failure = True

        elif ext in ADVISORY_VALIDATORS:
            code, output = ADVISORY_VALIDATORS[ext](path)
            if code not in (0, None):
                print(f"[WARN] {path} (advisory only, not blocking):\n{output}")
            else:
                print(f"[OK]   {path} (advisory check)")

        else:
            print(f"[SKIP] {path}: no validator for '{ext}' files.")

    if had_blocking_failure:
        print("\nOne or more files failed validation. Blocking the commit so broken "
              "code never lands on main. Fix the file or re-run the workflow.")
        return 1

    print("\nAll validated files passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
