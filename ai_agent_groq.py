import os
import re
import time
import json
import requests

API_KEY = os.environ.get("GROQ_API_KEY")
if not API_KEY:
    print("Error: GROQ_API_KEY is missing from GitHub Secrets.")
    exit(1)

BASE_URL = "https://api.groq.com/openai/v1"
FALLBACK_MODELS = ["llama-3.3-70b-versatile", "llama-3.1-8b-instant"]
STATE_FILE = ".agent_state.json"

ALL_PROJECT_FILES = [
    "index.html", "styles.css", "app.js",
    "CryptoEngine.cpp", "TransactionProcessor.cs",
    "SmartContract.sol", "server.go", "schema.sql",
    "README.md"
]

def get_ranked_models(api_key):
    """Lists available Groq models, newest/most-capable-looking first."""
    resp = requests.get(f"{BASE_URL}/models", headers={"Authorization": f"Bearer {api_key}"})
    resp.raise_for_status()
    models = resp.json().get("data", [])

    names = [m["id"] for m in models if "whisper" not in m["id"] and "guard" not in m["id"]]
    # Prefer larger/versatile-sounding models first, then everything else
    names.sort(key=lambda n: (0 if "70b" in n or "versatile" in n else 1, n), reverse=False)
    if not names:
        raise RuntimeError("No usable models returned by Groq.")
    print(f"Groq model preference order: {names}")
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


def generate_with_model_fallback(model_names, headers_base, payload_base, api_key):
    last_response = None
    for i, model in enumerate(model_names, start=1):
        print(f"Trying model {i}/{len(model_names)}: {model}")
        payload = dict(payload_base)
        payload["model"] = model
        headers = dict(headers_base)
        response = call_with_retry(f"{BASE_URL}/chat/completions", headers, payload)
        if response is not None and response.status_code == 200:
            print(f"Success with model: {model}")
            return response
        last_response = response
        print(f"Model {model} did not succeed, trying next candidate if available.\n")
    return last_response


# 1. Figure out which files other agents already claimed today, so we don't collide
claimed_files = []
if os.path.exists(STATE_FILE):
    try:
        with open(STATE_FILE, "r") as f:
            claimed_files = json.load(f).get("modified_files", [])
    except Exception:
        pass

available_files = [f for f in ALL_PROJECT_FILES if f not in claimed_files]
if not available_files:
    available_files = ALL_PROJECT_FILES  # fallback, shouldn't normally happen

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
"""

prompt = f"""
You are a second Principal Software Architect working alongside a colleague on:
{PROJECT_GOAL}

Here is a full snapshot of the current codebase across different languages:
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

payload_base = {
    "messages": [{"role": "user", "content": prompt}],
    "temperature": 0.2,
    "response_format": {"type": "json_object"}
}
headers_base = {
    "Authorization": f"Bearer {API_KEY}",
    "Content-Type": "application/json"
}

try:
    try:
        MODEL_CANDIDATES = get_ranked_models(API_KEY)
    except Exception as e:
        print(f"Could not list Groq models, falling back to hardcoded list. Reason: {e}")
        MODEL_CANDIDATES = FALLBACK_MODELS

    response = generate_with_model_fallback(MODEL_CANDIDATES, headers_base, payload_base, API_KEY)

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

    # Safety net: if the model ignores instructions and picks an already-claimed file,
    # skip writing rather than clobber someone else's work.
    if target_file in claimed_files:
        print(f"Groq picked '{target_file}', which was already claimed today. Skipping write to avoid collision.")
        exit(0)

    with open(target_file, "w", encoding="utf-8") as f:
        f.write(file_content)

    # Update shared state so later agents in the chain see this claim
    state = {"modified_files": claimed_files + [target_file]}
    with open(STATE_FILE, "w") as f:
        json.dump(state, f)

    print(f"Success! Groq agent has modified or created the '{target_file}' file.")

except Exception as e:
    print(f"A structural or network error occurred: {e}")
    exit(1)
