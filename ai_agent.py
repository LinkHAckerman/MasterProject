import os
import re
import time
import requests
import json

# 1. Fetch the Google Gemini API Key
API_KEY = os.environ.get("GEMINI_API_KEY")
if not API_KEY:
    print("Error: GEMINI_API_KEY is missing from GitHub Secrets.")
    exit(1)

BASE_URL = "https://generativelanguage.googleapis.com/v1beta"

# Used only if the ListModels call itself fails outright
FALLBACK_MODELS = ["gemini-3.7-flash", "gemini-3.6-flash"]


def get_ranked_flash_models(api_key):
    """
    Calls ListModels and returns stable Gemini Flash models that support
    generateContent, newest first. Skips preview/lite/image/tts variants.
    """
    resp = requests.get(f"{BASE_URL}/models", params={"key": api_key})
    resp.raise_for_status()
    models = resp.json().get("models", [])

    candidates = []
    for m in models:
        short_name = m.get("name", "").split("/")[-1]
        methods = m.get("supportedGenerationMethods", [])

        if "generateContent" not in methods:
            continue
        if "flash" not in short_name:
            continue
        if any(x in short_name for x in ["lite", "image", "tts", "preview"]):
            continue

        match = re.match(r"gemini-(\d+)\.(\d+)-flash$", short_name)
        if not match:
            continue

        version = (int(match.group(1)), int(match.group(2)))
        candidates.append((version, short_name))

    if not candidates:
        raise RuntimeError("No suitable stable Gemini Flash model found via ListModels.")

    candidates.sort(reverse=True)
    ranked_names = [name for _, name in candidates]
    print(f"Model preference order: {ranked_names}")
    return ranked_names


def call_gemini_with_retry(base_url, headers, payload, api_key, max_retries=3, base_delay=5):
    """
    Calls Gemini's generateContent for base_url. Retries transient errors
    (429/500/502/503/504, network exceptions) with exponential backoff.
    Returns the final response object regardless of success/failure -
    caller decides what to do with a non-200 result.
    """
    transient_statuses = {429, 500, 502, 503, 504}
    response = None

    for attempt in range(1, max_retries + 1):
        try:
            response = requests.post(
                base_url,
                headers=headers,
                data=json.dumps(payload),
                params={"key": api_key},
                timeout=120
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

        return response  # either non-transient, or out of retries for this model

    return response


def generate_with_model_fallback(model_names, headers, payload, api_key):
    """
    Tries each model in order. If a model fails after its retries are
    exhausted (still transient, e.g. persistent 503), moves on to the
    next model in the list rather than giving up entirely.
    """
    last_response = None
    for i, model in enumerate(model_names, start=1):
        url = f"{BASE_URL}/models/{model}:generateContent"
        print(f"Trying model {i}/{len(model_names)}: {model}")
        response = call_gemini_with_retry(url, headers, payload, api_key)

        if response is not None and response.status_code == 200:
            print(f"Success with model: {model}")
            return response

        last_response = response
        print(f"Model {model} did not succeed, moving to next candidate if available.\n")

    return last_response  # every model failed; return the last response for error reporting


try:
    MODEL_CANDIDATES = get_ranked_flash_models(API_KEY)
except Exception as e:
    print(f"Could not auto-detect Flash models, falling back to hardcoded list. Reason: {e}")
    MODEL_CANDIDATES = FALLBACK_MODELS

# 2. Gather existing directory snapshot and define project goals
ALL_PROJECT_FILES = [
    "index.html", "styles.css", "app.js",
    "CryptoEngine.cpp", "TransactionProcessor.cs",
    "SmartContract.sol", "server.go", "schema.sql",
    "README.md"
]

MAX_CHARS_PER_FILE = 3000
MAX_TOTAL_MANIFEST_CHARS = 12000

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

for file_name in ALL_PROJECT_FILES:
    if os.path.exists(file_name):
        with open(file_name, "r", encoding="utf-8", errors="ignore") as f:
            repo_manifest[file_name] = f.read()

manifest_json = json.dumps(repo_manifest, indent=2)

# 3. Define the Grand Ultimate Master Project Prompt
PROJECT_GOAL = """
The Magnum Opus: The ultimate, all-encompassing platform for everything Crypto, NFTs, Web3, DeFi, and Blockchain.
It must be the best thing ever made, showcasing full-stack mastery across multiple ecosystems:
- FRONT-END/FULL-STACK WEB: Highly interactive modern dark-theme dashboard (HTML, CSS, JavaScript).
- BACK-END CORE (C# / .NET): Robust servers, API data fetchers, or mock blockchain transaction handlers.
- CRYPTO HIGH-PERFORMANCE ENGINE (C++): Fast computational modules for block verification, hashing, or trading math.
"""

prompt = f"""
You are the lead Principal Software Architect working on:
{PROJECT_GOAL}

Here is a full snapshot of your current codebase across different languages:
---
{manifest_json if repo_manifest else "# The architecture is blank. Initialize the structural foundations today."}
---

Your task today is to pick the most critical next step to evolve this system. You can expand the UI, upgrade the C# backend data structures, or refine the C++ calculation engines.

Instructions for today's automated update:
1. Review the manifest. Choose ONE file to drastically improve or create today (e.g., add real-time Web3 wallet connectors in JS, code a blockchain transaction ledger in C#, optimize cryptographic sorting in C++, or enhance the CSS glow aesthetic).
2. Your response must be an automated file modification command. 
3. You must format your response as a strict JSON object containing the target 'filename' and the complete, non-truncated 'content'.
4. Do not include markdown code wrappers (like ```json). Return ONLY the raw JSON string.

Example output format:
{{"filename": "CryptoEngine.cs", "content": "...complete updated C# code here..."}}
"""

# 4. Transmit to Gemini, trying each candidate model in order
payload = {
    "contents": [{"parts": [{"text": prompt}]}],
    "generationConfig": {
        "responseMimeType": "application/json"
        # temperature/top_p/top_k intentionally omitted: deprecated on 3.x Flash models
    }
}
headers = {"Content-Type": "application/json"}

try:
    response = generate_with_model_fallback(MODEL_CANDIDATES, headers, payload, API_KEY)

    if response is None or response.status_code != 200:
        print("All candidate models failed.")
        if response is not None:
            print(f"Final status: {response.status_code}")
            print(response.text)
        exit(1)

    # 5. Process JSON payload and dynamically write the chosen language file
    response_data = response.json()

    if 'candidates' in response_data and response_data['candidates']:
        ai_output_raw = response_data['candidates'][0]['content']['parts'][0]['text']
    else:
        print("No candidates returned by Gemini. Full response:")
        print(json.dumps(response_data, indent=2))
        exit(1)

    # Clean up output formatting just in case
    clean_json = ai_output_raw.strip()
    if clean_json.startswith("```json"):
        clean_json = clean_json.replace("```json", "", 1).rstrip("```").strip()
    elif clean_json.startswith("```"):
        clean_json = clean_json.replace("```", "", 1).rstrip("```").strip()

    # Parse the target action
    action = json.loads(clean_json)
    target_file = action["filename"]
    file_content = action["content"]

    with open(target_file, "w", encoding="utf-8") as f:
        f.write(file_content)

    # Record which file we modified so other agents can avoid it
    state = {"modified_files": []}
    if os.path.exists(".agent_state.json"):
        try:
            with open(".agent_state.json", "r") as f:
                state = json.load(f)
        except Exception:
            pass
    state.setdefault("modified_files", [])
    state["modified_files"].append(target_file)
    with open(".agent_state.json", "w") as f:
        json.dump(state, f)

    print(f"Success! The AI Agent has modified or created the '{target_file}' file.")

except Exception as e:
    print(f"A structural or network error occurred: {e}")
    exit(1)
