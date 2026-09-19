import os
import time
import json
import requests

API_KEY = os.environ.get("MISTRAL_API_KEY")
if not API_KEY:
    print("Error: MISTRAL_API_KEY is missing from GitHub Secrets.")
    exit(1)

BASE_URL = "https://api.mistral.ai/v1"
FALLBACK_MODELS = ["mistral-large-latest", "mistral-small-latest", "open-mixtral-8x22b"]
STATE_FILE = ".agent_state.json"

ALL_PROJECT_FILES = [
    "index.html", "styles.css", "app.js",
    "CryptoEngine.cpp", "TransactionProcessor.cs",
    "SmartContract.sol", "server.go", "schema.sql",
    "README.md"
]


def get_ranked_models(api_key):
    resp = requests.get(f"{BASE_URL}/models", headers={"Authorization": f"Bearer {api_key}"})
    resp.raise_for_status()
    models = resp.json().get("data", [])
    names = [m["id"] for m in models if "embed" not in m["id"] and "moderation" not in m["id"]]
    names.sort(key=lambda n: (0 if "large" in n else 1, n))
    if not names:
        raise RuntimeError("No usable models returned by Mistral.")
    print(f"Mistral model preference order: {names}")
    return names


def call_with_retry(url, headers, payload, max_retries=3, base_delay=5):
    transient_statuses = {429, 500, 502, 503, 504}
    response = None
    for attempt in range(1, max_retries + 1):
        try:
            response = requests.post(url, headers=headers, data=json.dumps(payload), timeout=120)
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
            time.sleep(base_delay * (2 ** (attempt - 1)))
            continue
        return response
    return response


def generate_with_model_fallback(model_names, headers_base, payload_base):
    last_response = None
    for i, model in enumerate(model_names, start=1):
        print(f"Trying model {i}/{len(model_names)}: {model}")
        payload = dict(payload_base)
        payload["model"] = model
        response = call_with_retry(f"{BASE_URL}/chat/completions", headers_base, payload)
        if response is not None and response.status_code == 200:
            print(f"Success with model: {model}")
            return response
        last_response = response
        print(f"Model {model} did not succeed, trying next candidate if available.\n")
    return last_response


# 1. Load files already claimed by earlier agents today
claimed_files = []
if os.path.exists(STATE_FILE):
    try:
        with open(STATE_FILE, "r") as f:
            claimed_files = json.load(f).get("modified_files", [])
    except Exception:
        pass

available_files = [f for f in ALL_PROJECT_FILES if f not in claimed_files]
if not available_files:
    available_files = ALL_PROJECT_FILES

# 2. Gather current repo snapshot
repo_manifest = {}
for file_name in ALL_PROJECT_FILES:
    if os.path.exists(file_name):
        with open(file_name, "r", encoding="utf-8", errors="ignore") as f:
            repo_manifest[file_name] = f.read()

manifest_json = json.dumps(repo_manifest, indent=2)

PROJECT_GOAL = """
The Magnum Opus: The ultimate, all-encompassing platform for everything Crypto, NFTs, Web3, DeFi, and Blockchain.
It must be the best thing ever made, showcasing full-stack mastery across multiple ecosystems:
- FRONT-END/FULL-STACK WEB: Highly interactive modern dark-theme dashboard (HTML, CSS, JavaScript).
- BACK-END CORE (C# / .NET): Robust servers, API data fetchers, or mock blockchain transaction handlers.
- CRYPTO HIGH-PERFORMANCE ENGINE (C++): Fast computational modules for block verification, hashing, or trading math.
- SMART CONTRACTS (Solidity): Token, NFT, or DeFi contract logic (SmartContract.sol).
- MICROSERVICES (Go): A lightweight Go service for wallet/transaction relay (server.go).
- DATA LAYER (SQL): Schema for users, wallets, and transaction history (schema.sql).
"""

prompt = f"""
You are a third Principal Software Architect working alongside two colleagues on:
{PROJECT_GOAL}

Here is a full snapshot of the current codebase across different languages:
---
{manifest_json if repo_manifest else "# The architecture is blank. Initialize the structural foundations today."}
---

Colleagues have already claimed today: {claimed_files if claimed_files else "nothing yet"}.
You MUST choose a DIFFERENT file from this list: {available_files}

Prefer expanding into Solidity (SmartContract.sol), Go (server.go), or SQL (schema.sql) if they are
still unclaimed and would meaningfully advance the project, since those ecosystems need coverage.

Instructions:
1. Choose ONE file from the allowed list to drastically improve or create today.
2. Respond with ONLY a strict JSON object: {{"filename": "...", "content": "...complete updated file content..."}}
3. No markdown code fences. No commentary. Just the raw JSON object.
"""

headers_base = {
    "Authorization": f"Bearer {API_KEY}",
    "Content-Type": "application/json"
}
payload_base = {
    "messages": [{"role": "user", "content": prompt}],
    "temperature": 0.2,
    "response_format": {"type": "json_object"}
}

try:
    try:
        MODEL_CANDIDATES = get_ranked_models(API_KEY)
    except Exception as e:
        print(f"Could not list Mistral models, falling back to hardcoded list. Reason: {e}")
        MODEL_CANDIDATES = FALLBACK_MODELS

    response = generate_with_model_fallback(MODEL_CANDIDATES, headers_base, payload_base)

    if response is None or response.status_code != 200:
        print("All candidate models failed.")
        if response is not None:
            print(f"Final status: {response.status_code}")
            print(response.text)
        exit(1)

    response_data = response.json()
    ai_output_raw = response_data["choices"][0]["message"]["content"]

    clean_json = ai_output_raw.strip()
    if clean_json.startswith("```json"):
        clean_json = clean_json.replace("```json", "", 1).rstrip("```").strip()
    elif clean_json.startswith("```"):
        clean_json = clean_json.replace("```", "", 1).rstrip("```").strip()

    action = json.loads(clean_json)
    target_file = action["filename"]
    file_content = action["content"]

    if target_file in claimed_files:
        print(f"Mistral picked '{target_file}', which was already claimed today. Skipping write to avoid collision.")
        exit(0)

    with open(target_file, "w", encoding="utf-8") as f:
        f.write(file_content)

    # Update shared state
    state = {"modified_files": claimed_files + [target_file]}
    with open(STATE_FILE, "w") as f:
        json.dump(state, f)

    print(f"Success! Mistral agent has modified or created the '{target_file}' file.")

except Exception as e:
    print(f"A structural or network error occurred: {e}")
    exit(1)
