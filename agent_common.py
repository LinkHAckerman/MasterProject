"""
Shared logic for all AI agent scripts (Gemini, Groq, Mistral, OpenRouter, GitHub Models, ...).

Each provider script only needs to define:
  - how to list/rank its own models
  - a call_fn(model) -> requests.Response, using common.call_with_retry
  - an extract_text_fn(response) -> str | None, pulling the model's raw text
    out of that provider's response shape

Everything else (state file, manifest truncation, prompt text, JSON
extraction, retry loop, collision handling, README cooldown) lives here once.
"""

import os
import json
import time
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

MAX_CHARS_PER_FILE = 3000
MAX_TOTAL_MANIFEST_CHARS = 12000

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


def get_available_files(claimed_files):
    """Files not yet claimed today, with README.md filtered out unless its
    cooldown has elapsed - unless that filtering would leave nothing to
    pick, in which case README is allowed back in rather than starving
    every agent that day."""
    base_available = [f for f in ALL_PROJECT_FILES if f not in claimed_files]
    if not base_available:
        base_available = list(ALL_PROJECT_FILES)

    if "README.md" in base_available and not readme_is_due():
        filtered = [f for f in base_available if f != "README.md"]
        if filtered:
            return filtered

    return base_available


def build_manifest():
    """Reads every existing project file, truncating per-file and overall
    so the prompt stays within free-tier token limits even as the repo grows."""
    repo_manifest = {}
    for file_name in ALL_PROJECT_FILES:
        if os.path.exists(file_name):
            with open(file_name, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
                if len(content) > MAX_CHARS_PER_FILE:
                    content = content[:MAX_CHARS_PER_FILE] + "\n# ...[truncated for prompt size]..."
                repo_manifest[file_name] = content

    manifest_json = json.dumps(repo_manifest, indent=2)
    if len(manifest_json) > MAX_TOTAL_MANIFEST_CHARS:
        manifest_json = manifest_json[:MAX_TOTAL_MANIFEST_CHARS] + "\n... [manifest truncated for length] ..."

    return repo_manifest, manifest_json


def build_prompt(agent_label, claimed_files, available_files, manifest_json, repo_manifest):
    return f"""
You are {agent_label}, working alongside other AI colleagues on:
{PROJECT_GOAL}

Here is a snapshot of the current codebase across different languages:
---
{manifest_json if repo_manifest else "# The architecture is blank. Initialize the structural foundations today."}
---

Colleagues have already claimed today: {claimed_files if claimed_files else "nothing yet"}.
You MUST choose a DIFFERENT file from this list: {available_files}

Instructions:
1. Choose ONE file from that list to drastically improve or create today.
2. Respond with ONLY a strict JSON object: {{"filename": "...", "content": "...complete updated file content..."}}
3. No markdown code fences. No commentary. Just the raw JSON object.
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
    Full generation flow: ask for a file+content pick (trying every model in
    the list, per try_generate's rules, until one produces usable text), and
    if it picks something already claimed today (or the JSON doesn't parse),
    re-ask up to max_pick_attempts times before giving up gracefully.

    Returns (target_file, file_content) on success, or (None, None) if it
    never got a clean, unclaimed pick after all attempts (not an error -
    the caller should exit(0) in this case).

    Raises GenerationFailed if every model failed to produce usable content
    on every attempt (real outage/misconfiguration - caller should exit(1)).
    """
    for pick_attempt in range(1, max_pick_attempts + 1):
        raw_text, model = try_generate(model_names, call_fn, extract_text_fn)

        if raw_text is None:
            raise GenerationFailed("All candidate models failed to return usable content.")

        try:
            action = extract_json(raw_text)
            candidate_file = action["filename"]
            candidate_content = action["content"]
        except Exception as e:
            print(f"Attempt {pick_attempt}/{max_pick_attempts}: could not parse model output as JSON ({e}). Retrying.")
            continue

        if candidate_file not in claimed_files:
            return candidate_file, candidate_content

        print(f"Attempt {pick_attempt}/{max_pick_attempts}: picked '{candidate_file}', "
              f"already claimed today. Asking again for a different file.")

    print(f"Could not get an unclaimed file pick after {max_pick_attempts} attempts. Skipping this agent's turn.")
    return None, None


def write_file_and_claim(target_file, file_content, claimed_files):
    with open(target_file, "w", encoding="utf-8") as f:
        f.write(file_content)
    save_claim(claimed_files, target_file)
    if target_file == "README.md":
        record_readme_updated_today()
