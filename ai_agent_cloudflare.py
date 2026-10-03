import os
import requests
import agent_common as common

ACCOUNT_ID = os.environ.get("CLOUDFLARE_ACCOUNT_ID")
API_TOKEN = os.environ.get("CLOUDFLARE_API_TOKEN")
if not ACCOUNT_ID or not API_TOKEN:
    print("Error: CLOUDFLARE_ACCOUNT_ID and/or CLOUDFLARE_API_TOKEN is missing from GitHub Secrets.")
    exit(1)

BASE_URL = f"https://api.cloudflare.com/client/v4/accounts/{ACCOUNT_ID}/ai"
LIST_URL = f"{BASE_URL}/models/search"
CHAT_URL = f"{BASE_URL}/v1/chat/completions"

# Emergency fallback only - the dynamic catalog listing below is the real
# source of truth, since Cloudflare retires/renames Workers AI models too.
FALLBACK_MODELS = [
    "@cf/meta/llama-3.3-70b-instruct-fp8-fast",
    "@cf/meta/llama-3.1-8b-instruct"
]

NON_CHAT_KEYWORDS = ["embed", "whisper", "bge", "tts", "flux", "stable-diffusion", "moderation"]

# Well-tested general chat models get tried first; anything else the
# catalog returns is tried afterward, in whatever order it comes back.
PREFERRED_MODELS = [
    "@cf/meta/llama-3.3-70b-instruct-fp8-fast",
    "@cf/openai/gpt-oss-120b",
    "@cf/meta/llama-3.1-8b-instruct"
]

headers_base = {
    "Authorization": f"Bearer {API_TOKEN}",
    "Content-Type": "application/json"
}


def get_ranked_models():
    """Lists Workers AI text-generation models, preferred ones first."""
    resp = requests.get(
        LIST_URL,
        headers=headers_base,
        params={"task": "text-generation", "hide_experimental": "true", "per_page": 50}
    )
    resp.raise_for_status()
    data = resp.json()
    raw_list = data.get("result", [])

    candidates = []
    for m in raw_list:
        model_id = m.get("name") or m.get("id")
        if not model_id:
            continue
        if any(kw in model_id.lower() for kw in NON_CHAT_KEYWORDS):
            continue
        candidates.append(model_id)

    if not candidates:
        raise RuntimeError("No usable text-generation models returned by Workers AI.")

    candidates.sort(key=lambda m: (0 if m in PREFERRED_MODELS else 1))
    print(f"Cloudflare Workers AI model preference order: {candidates}")
    return candidates


try:
    MODEL_CANDIDATES = get_ranked_models()
except Exception as e:
    print(f"Could not list Workers AI models, falling back to hardcoded list. Reason: {e}")
    MODEL_CANDIDATES = FALLBACK_MODELS

claimed_files = common.load_claimed_files()
available_files = common.get_available_files(claimed_files)
repo_manifest, manifest_json = common.build_manifest()
prompt = common.build_prompt(
    "a Principal Software Architect",
    claimed_files, available_files, manifest_json, repo_manifest
)


def call_fn(model):
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.2,
        "response_format": {"type": "json_object"}
    }
    return common.call_with_retry(CHAT_URL, headers_base, payload)


def extract_text_fn(response):
    try:
        data = response.json()
    except ValueError:
        print("Workers AI response was not valid JSON:")
        print(response.status_code, response.text[:500])
        return None
    try:
        return data["choices"][0]["message"]["content"]
    except (KeyError, IndexError):
        print("Unexpected Workers AI response shape:")
        print(response.text)
        return None


try:
    target_file, file_content = common.pick_unclaimed_file(
        MODEL_CANDIDATES, call_fn, extract_text_fn, claimed_files
    )
    if target_file is None:
        exit(0)  # collision-exhausted, not an error

    common.write_file_and_claim(target_file, file_content, claimed_files)
    print(f"Success! Cloudflare Workers AI agent has modified or created the '{target_file}' file.")

except common.GenerationFailed as e:
    print(f"Generation failed: {e}")
    exit(1)
except Exception as e:
    print(f"A structural or network error occurred: {e}")
    exit(1)
