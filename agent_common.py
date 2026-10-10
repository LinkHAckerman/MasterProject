"""
Shared logic for all AI agent scripts (Gemini, Groq, Mistral, OpenRouter, Cloudflare, ...).

Each provider script only needs to define:
  - how to list/rank its own models
  - a call_fn(model) -> requests.Response, using common.call_with_retry
  - an extract_text_fn(response) -> str | None, pulling the model's raw text
    out of that provider's response shape

Everything else (state file, manifest truncation, prompt text, JSON
extraction, retry loop, collision handling, README cooldown, escaping
repair, and stalest-first file rotation) lives here once.
"""

import os
import json
import time
import random
import subprocess
import requests
from datetime import date

STATE_FILE = ".agent_state.json"

# Tracks README.md's last-updated date. Unlike STATE_FILE (which is reset
# at the start of every workflow run), this file is NOT reset daily - it
# persists across runs so the cooldown below actually works over time.
README_STATE_FILE = ".readme_state.json"
README_MIN_DAYS_BETWEEN_UPDATES = 7  # tune to taste

# Canonical list of files the agents are allowed to touch. Keep this in
# sync with what's actually in the repo root - if an agent invents a new
# filename outside this list, later agents won't know to avoid it.
ALL_PROJECT_FILES = [
    "index.html", "styles.css", "app.js",
    "CryptoEngine.cpp", "TransactionProcessor.cs",
    "SmartContract.sol", "server.go", "schema.sql",
    "OnChainProgram.rs", "WalletService.rb",
    "README.md"
]

# Prompt-size limits. The file an agent is ASSIGNED gets a big window so it
# can see (nearly) all of it before rewriting; every other file only gets a
# short preview for context.
MAX_CHARS_FOCUS_FILE = 5000
MAX_CHARS_OTHER_FILE = 350
MAX_TOTAL_MANIFEST_CHARS = 12000

# How many files each agent is offered. 1 = strict rotation: the stalest
# unclaimed file is the agent's assignment. Raise to 2-3 to give agents a
# little choice (they still only ever see the stalest N).
FILES_OFFERED_PER_AGENT = 1

PROJECT_GOAL = """
The Magnum Opus: The ultimate, all-encompassing platform for everything Crypto, NFTs, Web3, DeFi, and Blockchain.
It must be the best thing ever made, showcasing full-stack mastery across multiple ecosystems:
- FRONT-END/FULL-STACK WEB: Highly interactive modern dark-theme dashboard (HTML, CSS, JavaScript).
- BACK-END CORE (C# / .NET): Robust servers, API data fetchers, or mock blockchain transaction handlers.
- CRYPTO HIGH-PERFORMANCE ENGINE (C++): Fast computational modules for block verification, hashing, or trading math.
- SMART CONTRACTS (Solidity): Token, NFT, or DeFi contract logic (SmartContract.sol).
- MICROSERVICES (Go): A lightweight Go service for wallet/transaction relay (server.go).
- DATA LAYER (SQL): Schema for users, wallets, and transaction history (schema.sql).
- ON-CHAIN PROGRAMS (Rust): High-performance, memory-safe on-chain program logic (OnChainProgram.rs).
- SCRIPTING/GLUE LAYER (Ruby): Lightweight wallet balance and exchange-rate service (WalletService.rb).
"""

# The file(s) this agent is allowed to pick. Set by get_available_files()
# and enforced by pick_unclaimed_file().
_current_assignment = []


class GenerationFailed(Exception):
    """Raised when every candidate model failed to produce usable content."""
    pass


def load_claimed_files():
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, "r") as f:
                return json.load(f).get("modified_files", [])
        except Exception:
            pass
    return []


def save_claim(claimed_files, target_file):
    state = {"modified_files": claimed_files + [target_file]}
    with open(STATE_FILE, "w") as f:
        json.dump(state, f)


def load_readme_last_updated():
    if os.path.exists(README_STATE_FILE):
        try:
            with open(README_STATE_FILE, "r") as f:
                return json.load(f).get("last_updated")
        except Exception:
            pass
    return None


def record_readme_updated_today():
    with open(README_STATE_FILE, "w") as f:
        json.dump({"last_updated": date.today().isoformat()}, f)


def readme_is_due():
    """True if README.md hasn't been updated recently enough to still be
    on cooldown - i.e. it's actually available to pick again."""
    last = load_readme_last_updated()
    if not last:
        return True
    try:
        last_date = date.fromisoformat(last)
    except ValueError:
        return True
    return (date.today() - last_date).days >= README_MIN_DAYS_BETWEEN_UPDATES


_shallow_warning_printed = False


def _warn_if_shallow_clone():
    """Last-modified dates come from git history. In a shallow clone (the
    actions/checkout default) every file looks like it was touched by the
    single fetched commit, so rotation silently degrades to random."""
    global _shallow_warning_printed
    if _shallow_warning_printed:
        return
    _shallow_warning_printed = True
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--is-shallow-repository"],
            capture_output=True, text=True, timeout=30
        ).stdout.strip()
        if out == "true":
            print("WARNING: shallow git clone detected - file staleness cannot be "
                  "determined. Add 'fetch-depth: 0' to the checkout step.")
    except Exception:
        pass


def get_last_modified_epoch(path):
    """Unix time of the last commit touching `path`; 0 if the file has no
    history (missing or brand new/uncommitted) so it sorts as 'stalest'."""
    try:
        out = subprocess.run(
            ["git", "log", "-1", "--format=%ct", "--", path],
            capture_output=True, text=True, timeout=30
        ).stdout.strip()
        return int(out) if out else 0
    except Exception:
        return 0


def get_available_files(claimed_files):
    """Returns the stalest unclaimed file(s) - the agent's assignment.

    - Files already claimed in this run are excluded.
    - README.md is excluded while on cooldown (unless nothing else is left).
    - Ordering is by last git commit time, oldest first (never-committed or
      missing files first), with random tie-breaking.
    """
    global _current_assignment
    _warn_if_shallow_clone()

    candidates = [f for f in ALL_PROJECT_FILES if f not in claimed_files]
    if not candidates:
        candidates = list(ALL_PROJECT_FILES)

    if "README.md" in candidates and not readme_is_due():
        filtered = [f for f in candidates if f != "README.md"]
        if filtered:
            candidates = filtered

    random.shuffle(candidates)  # random tie-break; sort below is stable
    candidates.sort(key=get_last_modified_epoch)

    _current_assignment = candidates[:FILES_OFFERED_PER_AGENT]
    print(f"Assigned file(s) by staleness: {_current_assignment}")
    return list(_current_assignment)


def build_manifest():
    """Reads every existing project file. The assigned file gets a large
    window; the rest get a short preview. Total size is capped so the prompt
    stays within free-tier token limits."""
    focus = set(_current_assignment)
    repo_manifest = {}
    for file_name in ALL_PROJECT_FILES:
        if not os.path.exists(file_name):
            continue
        with open(file_name, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
        limit = MAX_CHARS_FOCUS_FILE if file_name in focus else MAX_CHARS_OTHER_FILE
        if len(content) > limit:
            content = content[:limit] + "\n# ...[truncated for prompt size]..."
        repo_manifest[file_name] = content

    manifest_json = json.dumps(repo_manifest, indent=2)
    if len(manifest_json) > MAX_TOTAL_MANIFEST_CHARS:
        manifest_json = manifest_json[:MAX_TOTAL_MANIFEST_CHARS] + "\n... [manifest truncated for length] ..."

    return repo_manifest, manifest_json


def build_prompt(agent_label, claimed_files, available_files, manifest_json, repo_manifest):
    return f"""
You are {agent_label}, working alongside other AI colleagues on:
{PROJECT_GOAL}

Here is a snapshot of the current codebase across different languages. The file
you are assigned has the longest preview; the others are short previews for context:
---
{manifest_json if repo_manifest else "# The architecture is blank. Initialize the structural foundations today."}
---

Colleagues have already claimed today: {claimed_files if claimed_files else "nothing yet"}.
Your assigned file today (it has gone the longest without an update): {available_files}

Instructions:
1. Work on the assigned file above and no other. If it is truncated in the snapshot,
   keep its existing structure and improve/extend it - do not discard what is there.
   If it does not exist yet, create it.
2. Respond with ONLY a strict JSON object: {{"filename": "...", "content": "...complete updated file content..."}}
3. No markdown code fences. No commentary. Just the raw JSON object.
4. Inside the "content" string, use real single-backslash JSON escapes
   (\\n for newline, \\t for tab, \\" for a quote) - do NOT double-escape
   them (never \\\\n or \\\\t).
5. If you are writing Go code (server.go) and need a regex pattern, file
   path, or any string containing backslashes, use a Go raw string literal
   (backticks, e.g. `{{regex pattern here}}`) instead of a double-quoted
   string - double-quoted Go strings only support a small fixed set of
   escape sequences and will fail to compile otherwise.
"""


def extract_json(raw_text):
    """Strips markdown fences if present, then parses the first complete
    JSON object and ignores any trailing text after it (some models add
    stray characters or commentary after a large generated file)."""
    clean = raw_text.strip()
    if clean.startswith("```json"):
        clean = clean.replace("```json", "", 1).rstrip("`").strip()
    elif clean.startswith("```"):
        clean = clean.replace("```", "", 1).rstrip("`").strip()

    decoder = json.JSONDecoder()
    action, _ = decoder.raw_decode(clean)
    return action


def repair_double_escaped_content(content):
    """
    Some smaller/open models double-escape when writing code inside a JSON
    string value - e.g. their raw output contains the four characters
    \\\\n (two backslashes then n) where a single \\n was intended, so
    after our one JSON-decode pass the content still contains literal
    two-character sequences like backslash-n instead of a real newline.
    The result is a file squashed onto one line full of stray backslashes.

    Heuristically detect this (suspiciously few real newlines, but many
    literal escape-looking sequences) and unescape once more. Uses plain
    string replacement rather than codecs' unicode_escape, since that
    codec operates byte-wise and can mangle non-ASCII text (e.g. comments
    with accented characters) - these targeted replacements only touch
    the specific sequences this failure mode actually produces.
    """
    real_newlines = content.count("\n")
    literal_n = content.count("\\n")
    literal_t = content.count("\\t")
    literal_quote = content.count('\\"')

    looks_double_escaped = (
        real_newlines <= 1 and (literal_n + literal_t + literal_quote) >= 3
    )

    if not looks_double_escaped:
        return content

    repaired = (
        content
        .replace("\\r\\n", "\n")
        .replace("\\n", "\n")
        .replace("\\t", "\t")
        .replace('\\"', '"')
        .replace("\\'", "'")
    )

    # Only trust the repair if it actually produced real structure -
    # otherwise return the original untouched rather than risk mangling it.
    if repaired.count("\n") > real_newlines:
        return repaired
    return content


def call_with_retry(url, headers, payload, params=None, max_retries=3, base_delay=5):
    """POSTs with exponential backoff on transient errors (429/5xx, network
    exceptions). Returns the final response regardless of outcome so the
    caller can inspect status/body; returns None only on total network failure."""
    transient_statuses = {429, 500, 502, 503, 504}
    response = None

    for attempt in range(1, max_retries + 1):
        try:
            response = requests.post(
                url, headers=headers, data=json.dumps(payload),
                params=params, timeout=120
            )
        except requests.exceptions.RequestException as e:
            print(f"  Attempt {attempt}/{max_retries}: network error ({e})")
            if attempt == max_retries:
                return None
            time.sleep(base_delay * (2 ** (attempt - 1)))
            continue

        if response.status_code == 200:
            return response

        print(f"  Attempt {attempt}/{max_retries}: status {response.status_code}")
        print(f"  {response.text}")

        if response.status_code in transient_statuses and attempt < max_retries:
            delay = base_delay * (2 ** (attempt - 1))
            print(f"  Transient error, retrying in {delay} seconds...")
            time.sleep(delay)
            continue

        return response

    return response


def try_generate(model_names, call_fn, extract_text_fn):
    """
    Tries each model in order. A model only counts as successful if it
    returns HTTP 200 AND yields non-empty extractable text - a 200 with
    empty/null content (e.g. a reasoning model that spends its whole token
    budget "thinking" and never writes a visible answer) is treated as a
    failure for that model, and the next candidate is tried.

    Returns (raw_text, model_name) on success, or (None, None) if every
    candidate failed one way or another.
    """
    for i, model in enumerate(model_names, start=1):
        print(f"Trying model {i}/{len(model_names)}: {model}")
        response = call_fn(model)

        if response is None:
            print(f"Model {model}: no response (network failure). Trying next candidate if available.\n")
            continue

        if response.status_code != 200:
            print(f"Model {model}: status {response.status_code}. Trying next candidate if available.\n")
            continue

        raw_text = extract_text_fn(response)
        if not raw_text:
            print(f"Model {model}: returned 200 but no usable text (empty/null content - "
                  f"often a reasoning model that ran out of token budget before answering). "
                  f"Trying next candidate if available.\n")
            continue

        print(f"Success with model: {model}")
        return raw_text, model

    return None, None


def pick_unclaimed_file(model_names, call_fn, extract_text_fn, claimed_files, max_pick_attempts=3):
    """
    Full generation flow: ask for the assigned file's new content (trying
    every model in the list, per try_generate's rules, until one produces
    usable text). If the model returns a different file than assigned (or
    one already claimed today, or the JSON doesn't parse), re-ask up to
    max_pick_attempts times before giving up gracefully.

    Returns (target_file, file_content) on success, or (None, None) if it
    never got a clean pick after all attempts (not an error - the caller
    should exit(0) in this case).

    Raises GenerationFailed if every model failed to produce usable content
    on every attempt (real outage/misconfiguration - caller should exit(1)).
    """
    allowed = list(_current_assignment) if _current_assignment else [
        f for f in ALL_PROJECT_FILES if f not in claimed_files
    ]

    for pick_attempt in range(1, max_pick_attempts + 1):
        raw_text, model = try_generate(model_names, call_fn, extract_text_fn)

        if raw_text is None:
            raise GenerationFailed("All candidate models failed to return usable content.")

        try:
            action = extract_json(raw_text)
            candidate_file = action["filename"]
            candidate_content = repair_double_escaped_content(action["content"])
        except Exception as e:
            print(f"Attempt {pick_attempt}/{max_pick_attempts}: could not parse model output as JSON ({e}). Retrying.")
            continue

        if candidate_file in allowed and candidate_file not in claimed_files:
            return candidate_file, candidate_content

        print(f"Attempt {pick_attempt}/{max_pick_attempts}: picked '{candidate_file}', "
              f"but the assignment is {allowed} (claimed today: {claimed_files}). "
              f"Asking again for the assigned file.")

    print(f"Could not get the assigned file after {max_pick_attempts} attempts. Skipping this agent's turn.")
    return None, None


def write_file_and_claim(target_file, file_content, claimed_files):
    with open(target_file, "w", encoding="utf-8") as f:
        f.write(file_content)
    save_claim(claimed_files, target_file)
    if target_file == "README.md":
        record_readme_updated_today()
