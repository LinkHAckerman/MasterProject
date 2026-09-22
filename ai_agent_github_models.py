import os
import requests
import agent_common as common

# Uses the Actions workflow's own token (mapped to this env var in the
# workflow YAML from ${{ github.token }}) - not a separately created secret.
# Requires the job to declare `permissions: models: read`.
TOKEN = os.environ.get("GITHUB_MODELS_TOKEN")
if not TOKEN:
    print("Error: GITHUB_MODELS_TOKEN is missing. Make sure the workflow step maps "
          "env: GITHUB_MODELS_TOKEN: ${{ github.token }} and the job has "
          "'permissions: models: read' set.")
    exit(1)

CATALOG_URL = "https://models.github.ai/catalog/models"
INFERENCE_URL = "https://models.github.ai/inference/chat/completions"

# Confirmed-working model IDs, used only if the catalog listing itself fails.
FALLBACK_MODELS = ["openai/gpt-4.1", "openai/gpt-4o-mini"]

# Models we don't want for this task (embeddings, vision-only, audio, rerankers).
NON_CHAT_KEYWORDS = ["embed", "whisper", "dall-e", "tts", "rerank", "vision"]

# Well-tested general chat models get tried first; anything else in the
# catalog is tried afterward, in whatever order the catalog returns it.
PREFERRED_MODELS = ["openai/gpt-4.1", "openai/gpt-4o-mini", "openai/gpt-4.1-mini"]


def get_ranked_models(token):
    """Lists GitHub Models' catalog and ranks preferred general-purpose chat models first."""
    resp = requests.get(CATALOG_URL, headers={"Authorization": f"Bearer {token}"})
    resp.raise_for_status()
    data = resp.json()
    raw_list = data if isinstance(data, list) else data.get("data", data.get("models", []))

    candidates = []
    for m in raw_list:
        model_id = m.get("id") or m.get("name")
        if not model_id:
            continue
        if any(kw in model_id.lower() for kw in NON_CHAT_KEYWORDS):
            continue
        candidates.append(model_id)

    if not candidates:
        raise RuntimeError("No usable chat models returned by the GitHub Models catalog.")

    candidates.sort(key=lambda m: (0 if m in PREFERRED_MODELS else 1))
    print(f"GitHub Models preference order: {candidates}")
    return candidates


try:
    MODEL_CANDIDATES = get_ranked_models(TOKEN)
except Exception as e:
    print(f"Could not list GitHub Models catalog, falling back to hardcoded list. Reason: {e}")
    MODEL_CANDIDATES = FALLBACK_MODELS

claimed_files = common.load_claimed_files()
available_files = common.get_available_files(claimed_files)
repo_manifest, manifest_json = common.build_manifest()
prompt = common.build_prompt(
    "a Principal Software Architect",
    claimed_files, available_files, manifest_json, repo_manifest
)

headers_base = {
    "Authorization": f"Bearer {TOKEN}",
    "Content-Type": "application/json"
}


def call_fn(model):
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.2,
        "response_format": {"type": "json_object"}
    }
    return common.call_with_retry(INFERENCE_URL, headers_base, payload)


def extract_text_fn(response):
    data = response.json()
    try:
        return data["choices"][0]["message"]["content"]
    except (KeyError, IndexError):
        print("Unexpected GitHub Models response shape:")
        print(response.text)
        return None


try:
    if MODEL_CANDIDATES == FALLBACK_MODELS:
        pass  # already logged the fallback reason above

    target_file, file_content = common.pick_unclaimed_file(
        MODEL_CANDIDATES, call_fn, extract_text_fn, claimed_files
    )
    if target_file is None:
        exit(0)  # collision-exhausted, not an error

    common.write_file_and_claim(target_file, file_content, claimed_files)
    print(f"Success! GitHub Models agent has modified or created the '{target_file}' file.")

except common.GenerationFailed as e:
    print(f"Generation failed: {e}")
    if "403" in str(e):
        print("A 403 here usually means GitHub Models isn't enabled for this "
              "repo/org's Actions token. Fix: create a personal access token with "
              "'models: read' scope, add it as a repo secret, and use that instead "
              "of the built-in token in the workflow's env mapping.")
    exit(1)
except Exception as e:
    print(f"A structural or network error occurred: {e}")
    exit(1)
