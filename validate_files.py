#!/usr/bin/env python3
"""
Best-effort syntax validation for files touched by today's AI agents.

Reads .agent_state.json for the list of files modified today and checks
each one with whatever lightweight tool is available for its language.

BLOCKING checks (the specific failing file is reverted - see below):
  .py   -> python3 -m py_compile
  .js   -> node --check
  .go   -> gofmt -l        (parses syntax; doesn't need a go.mod)
  .cpp  -> g++ -fsyntax-only
  .rb   -> ruby -c          (syntax check only, no gem dependencies needed)

ADVISORY checks (printed as a warning only, never reverts anything):
  .sql  -> sqlite3 parse (schema.sql may use dialect features sqlite
           rejects even when valid for the intended database, so this is
           informational rather than authoritative)
  .rs   -> rustc --emit=metadata, no Cargo.toml/dependencies available.
           Real on-chain Rust (OnChainProgram.rs) depends on external
           crates like solana_program and borsh - a bare rustc check has
           no way to resolve those, so it will always report "cannot find
           crate" and cascading errors for legitimate, correct code.

NOT CHECKED (no lightweight tool available without heavier CI setup):
  .cs   (C# - would need a scaffolded .csproj to compile a single file)
  .sol  (Solidity - would need solc + resolved imports, e.g. OpenZeppelin,
         to avoid false failures on legitimate contracts)
  .html/.css/.md - not code in the sense that matters here

REVERT BEHAVIOR: a file that fails a blocking check is reverted rather
than left broken or allowed to block the whole run's commit:
  - If the file already existed before today's run, it's restored to its
    last known-good committed version (git checkout -- <path>).
  - If the file is brand new (never committed before), it's simply
    deleted so it's never added.
This script always exits 0 - it cleans up failures itself instead of
stopping the pipeline, so one agent's bad output only costs that one
file's progress for the day, not every other agent's valid work too.
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


def validate_ruby(path):
    return run(["ruby", "-c", path])


def validate_rust_advisory(path):
    return run(["rustc", "--edition", "2021", "--crate-type", "lib",
                "--emit=metadata", "-o", "/dev/null", path])


def validate_sql_advisory(path):
    return run(["sqlite3", ":memory:", f".read {path}"])


BLOCKING_VALIDATORS = {
    ".py": validate_python,
    ".js": validate_js,
    ".go": validate_go,
    ".cpp": validate_cpp,
    ".rb": validate_ruby,
}

ADVISORY_VALIDATORS = {
    ".sql": validate_sql_advisory,
    ".rs": validate_rust_advisory,
}


def file_existed_before_today(path):
    """True if this path already had a committed version before today's
    run (i.e. it's at HEAD) - used to decide revert vs delete."""
    result = subprocess.run(
        ["git", "cat-file", "-e", f"HEAD:{path}"],
        capture_output=True
    )
    return result.returncode == 0


def revert_file(path):
    if file_existed_before_today(path):
        subprocess.run(["git", "checkout", "--", path], check=False)
        print(f"  -> Reverted {path} to its last known-good committed version.")
    else:
        try:
            os.remove(path)
            print(f"  -> Removed {path} (it was new today, never previously committed).")
        except FileNotFoundError:
            pass


def main():
    files = get_todays_files()
    if not files:
        print("No files recorded in .agent_state.json - nothing to validate.")
        return 0

    failing_paths = []

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
                failing_paths.append(path)

        elif ext in ADVISORY_VALIDATORS:
            code, output = ADVISORY_VALIDATORS[ext](path)
            if code not in (0, None):
                print(f"[WARN] {path} (advisory only, not blocking):\n{output}")
            else:
                print(f"[OK]   {path} (advisory check)")

        else:
            print(f"[SKIP] {path}: no validator for '{ext}' files.")

    if failing_paths:
        print(f"\n{len(failing_paths)} file(s) failed validation. Reverting just those, "
              f"so today's other valid changes still commit normally:")
        for path in failing_paths:
            revert_file(path)
    else:
        print("\nAll validated files passed.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
