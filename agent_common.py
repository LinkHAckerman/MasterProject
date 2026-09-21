"""
Shared logic for all AI agent scripts (Gemini, Groq, Mistral, Cerebras, ...).

Each provider script only needs to define:
  - how to list/rank its own models
  - a call_fn(model) -> requests.Response, using common.call_with_retry
  - an extract_text_fn(response) -> str | None, pulling the model's raw text
    out of that provider's response shape

Everything else (state file, manifest truncation, prompt text, JSON
extraction, retry loop, collision handling) lives here once.
"""

import os
import json
import time
import requests

STATE_FILE = ".agent_state.json"

# Canonical list of files the agents are allowed to touch. Keep this in
# sync with what's actually in the repo root - if an agent invents a new
# filename outside this list, later agents won't know to avoid it.
ALL_PROJECT_FILES = [
    "index.html", "styles.css", "app.js",
    "CryptoEngine.cpp", "TransactionProcessor.cs",
    "SmartContract.sol", "server.go", "schema.sql",
    "OnChainProgram.rs",
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
"""


class GenerationFailed(Exception):
    """Raised when every candidate model failed to produce a usable response."""
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


def get_available_files(claimed_files):
    available = [f for f in ALL_PROJECT_FILES if f not in claimed_files]
    return available if available else ALL_PROJECT_FILES


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


def generate_with_model_fallback(model_names, call_fn):
    """Tries each model in order; moves to the next if one is persistently
    unavailable (e.g. overloaded, deprecated, or terms-gated)."""
    last_response = None
    for i, model in enumerate(model_names, start=1):
        print(f"Trying model {i}/{len(model_names)}: {model}")
        response = call_fn(model)
        if response is not None and response.status_code == 200:
            print(f"Success with model: {model}")
            return response
        last_response = response
        print(f"Model {model} did not succeed, trying next candidate if available.\n")
    return last_response


def pick_unclaimed_file(model_names, call_fn, extract_text_fn, claimed_files, max_pick_attempts=3):
    """
    Full generation flow: ask the model for a file+content pick, and if it
    picks something already claimed today (or the JSON doesn't parse),
    re-ask up to max_pick_attempts times before giving up gracefully.

    Returns (target_file, file_content) on success, or (None, None) if it
    never got a clean, unclaimed pick after all attempts (not an error -
    the caller should exit(0) in this case).

    Raises GenerationFailed if the provider itself never returns a usable
    200 response (real outage/misconfiguration - caller should exit(1)).
    """
    for pick_attempt in range(1, max_pick_attempts + 1):
        response = generate_with_model_fallback(model_names, call_fn)

        if response is None or response.status_code != 200:
            detail = response.text if response is not None else "no response (network failure)"
            status = getattr(response, "status_code", "n/a")
            raise GenerationFailed(f"All candidate models failed. Last status: {status}. {detail}")

        raw_text = extract_text_fn(response)
        if raw_text is None:
            raise GenerationFailed("Could not extract text from provider response.")

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
