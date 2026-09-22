import os
import requests
import agent_common as common

API_KEY = os.environ.get("OPENROUTER_API_KEY")
if not API_KEY:
    print("Error: OPENROUTER_API_KEY is missing from GitHub Secrets.")
    exit(1)

BASE_URL = "https://openrouter.ai/api/v1"

# These are just an emergency fallback if the models list can't be fetched -
# OpenRouter's free lineup rotates, so the dynamic ':free' filter below is
# the real source of truth.
FALLBACK_MODELS = [
    "meta-llama/llama-3.3-70b-instruct:free",
    "qwen/qwen-2.5-72b-instruct:free"
]


def get_ranked_models(api_key):
    """Lists OpenRouter's free-tier models (id ending in ':free'), largest context first."""
    resp = requests.get(f"{BASE_URL}/models", headers={"Authorization": f"Bearer {api_key}"})
    resp.raise_for_status()
    models = resp.json().get("data", [])

    candidates = []
    for m in models:
        model_id = m.get("id", "")
        if not model_id.endswith(":free"):
            continue
        context_length = m.get("context_length", 0) or 0
        candidates.append((context_length, model_id))

    if not candidates:
        raise RuntimeError("No free-tier (':free') models returned by OpenRouter.")

    candidates.sort(reverse=True)
    names = [model_id for _, model_id in candidates]
    print(f"OpenRouter model preference order: {names}")
    return names


try:
    MODEL_CANDIDATES = get_ranked_models(API_KEY)
except Exception as e:
    print(f"Could not list OpenRouter models, falling back to hardcoded list. Reason: {e}")
    MODEL_CANDIDATES = FALLBACK_MODELS

claimed_files = common.load_claimed_files()
available_files = common.get_available_files(claimed_files)
repo_manifest, manifest_json = common.build_manifest()
prompt = common.build_prompt(
    "a Principal Software Architect",
    claimed_files, available_files, manifest_json, repo_manifest
)

headers_base = {
    "Authorization": f"Bearer {API_KEY}",
    "Content-Type": "application/json",
    # Optional but recommended by OpenRouter for attribution/rate-limit fairness.
    "HTTP-Referer": "https://github.com/LinkHAckerman/MasterProject",
    "X-Title": "MasterProject Daily Autonomous AI Worker"
}


def call_fn(model):
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.2,
        "max_tokens": 8000,
        "response_format": {"type": "json_object"}
    }
    return common.call_with_retry(f"{BASE_URL}/chat/completions", headers_base, payload)


def extract_text_fn(response):
    data = response.json()
    try:
        return data["choices"][0]["message"]["content"]
    except (KeyError, IndexError):
        print("Unexpected OpenRouter response shape:")
        print(response.text)
        return None


try:
    target_file, file_content = common.pick_unclaimed_file(
        MODEL_CANDIDATES, call_fn, extract_text_fn, claimed_files
    )
    if target_file is None:
        exit(0)  # collision-exhausted, not an error

    common.write_file_and_claim(target_file, file_content, claimed_files)
    print(f"Success! OpenRouter agent has modified or created the '{target_file}' file.")

except common.GenerationFailed as e:
    print(f"Generation failed: {e}")
    exit(1)
except Exception as e:
    print(f"A structural or network error occurred: {e}")
    exit(1)
