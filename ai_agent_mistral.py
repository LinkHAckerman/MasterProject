import os
import requests
import agent_common as common

API_KEY = os.environ.get("MISTRAL_API_KEY")
if not API_KEY:
    print("Error: MISTRAL_API_KEY is missing from GitHub Secrets.")
    exit(1)

BASE_URL = "https://api.mistral.ai/v1"
FALLBACK_MODELS = ["mistral-medium-latest", "mistral-small-latest"]

# OCR, voice, embedding, moderation, and CLI-tool models aren't useful for
# this task - skip them when ranking candidates.
NON_CHAT_KEYWORDS = ["ocr", "voxtral", "vibe-cli", "embed", "moderation", "fim"]


def get_ranked_models(api_key):
    """Lists available Mistral chat models, preferring medium/large general models."""
    resp = requests.get(f"{BASE_URL}/models", headers={"Authorization": f"Bearer {api_key}"})
    resp.raise_for_status()
    models = resp.json().get("data", [])

    candidates = []
    for m in models:
        model_id = m.get("id", "")
        if any(kw in model_id.lower() for kw in NON_CHAT_KEYWORDS):
            continue
        candidates.append(model_id)

    if not candidates:
        raise RuntimeError("No usable chat models returned by Mistral.")

    # Codestral first: this project is all code, and in practice the larger
    # general models hit rate limits / capacity errors on the free tier far
    # more often. The "-latest" alias is tried before dated versions.
    def rank(n):
        if "codestral" in n:
            return (0, 0 if n.endswith("latest") else 1, n)
        if "medium" in n or "large" in n:
            return (1, 0, n)
        return (2, 0, n)

    candidates.sort(key=rank)
    print(f"Mistral model preference order: {candidates}")
    return candidates


try:
    MODEL_CANDIDATES = get_ranked_models(API_KEY)
except Exception as e:
    print(f"Could not list Mistral models, falling back to hardcoded list. Reason: {e}")
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
    "Content-Type": "application/json"
}


def call_fn(model):
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.2,
        "response_format": {"type": "json_object"}
    }
    return common.call_with_retry(f"{BASE_URL}/chat/completions", headers_base, payload)


def extract_text_fn(response):
    data = response.json()
    try:
        return data["choices"][0]["message"]["content"]
    except (KeyError, IndexError):
        print("Unexpected Mistral response shape:")
        print(response.text)
        return None


try:
    target_file, file_content = common.pick_unclaimed_file(
        MODEL_CANDIDATES, call_fn, extract_text_fn, claimed_files
    )
    if target_file is None:
        exit(0)  # collision-exhausted, not an error

    common.write_file_and_claim(target_file, file_content, claimed_files)
    print(f"Success! Mistral agent has modified or created the '{target_file}' file.")

except common.GenerationFailed as e:
    print(f"Generation failed: {e}")
    exit(1)
except Exception as e:
    print(f"A structural or network error occurred: {e}")
    exit(1)
