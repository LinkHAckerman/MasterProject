import os
import requests
import agent_common as common

API_KEY = os.environ.get("GROQ_API_KEY")
if not API_KEY:
    print("Error: GROQ_API_KEY is missing from GitHub Secrets.")
    exit(1)

BASE_URL = "https://api.groq.com/openai/v1"
FALLBACK_MODELS = ["llama-3.3-70b-versatile", "llama-3.1-8b-instant"]

# Speech/TTS, moderation, agentic-router, and other non-general-chat models
# to skip when ranking candidates.
NON_CHAT_KEYWORDS = ["whisper", "tts", "guard", "orpheus", "allam", "moderation", "compound"]


def get_ranked_models(api_key):
    """Lists available Groq chat models, largest context window first."""
    resp = requests.get(f"{BASE_URL}/models", headers={"Authorization": f"Bearer {api_key}"})
    resp.raise_for_status()
    models = resp.json().get("data", [])

    candidates = []
    for m in models:
        model_id = m.get("id", "")
        if any(kw in model_id.lower() for kw in NON_CHAT_KEYWORDS):
            continue
        if not m.get("active", True):
            continue
        context_window = m.get("context_window", 0)
        candidates.append((context_window, model_id))

    if not candidates:
        raise RuntimeError("No usable chat models returned by Groq.")

    candidates.sort(reverse=True)
    names = [model_id for _, model_id in candidates]
    print(f"Groq model preference order: {names}")
    return names


try:
    MODEL_CANDIDATES = get_ranked_models(API_KEY)
except Exception as e:
    print(f"Could not list Groq models, falling back to hardcoded list. Reason: {e}")
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
        print("Unexpected Groq response shape:")
        print(response.text)
        return None


try:
    target_file, file_content = common.pick_unclaimed_file(
        MODEL_CANDIDATES, call_fn, extract_text_fn, claimed_files
    )
    if target_file is None:
        exit(0)  # collision-exhausted, not an error

    common.write_file_and_claim(target_file, file_content, claimed_files)
    print(f"Success! Groq agent has modified or created the '{target_file}' file.")

except common.GenerationFailed as e:
    print(f"Generation failed: {e}")
    exit(1)
except Exception as e:
    print(f"A structural or network error occurred: {e}")
    exit(1)
