import os
import re
import json
import requests
import agent_common as common

API_KEY = os.environ.get("GEMINI_API_KEY")
if not API_KEY:
    print("Error: GEMINI_API_KEY is missing from GitHub Secrets.")
    exit(1)

BASE_URL = "https://generativelanguage.googleapis.com/v1beta"
FALLBACK_MODELS = ["gemini-3.7-flash", "gemini-3.6-flash"]

# Models Google's own ListModels catalog still returns as supporting
# generateContent, but that are actually retired in practice (confirmed by
# a live 404 "no longer available to new users" response). The catalog
# metadata and real availability have drifted apart here, so this is a
# manual client-side patch rather than something the dynamic listing alone
# can catch.
KNOWN_RETIRED_MODELS = {"gemini-2.5-flash"}

RESPONSE_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "filename": {"type": "STRING"},
        "content": {"type": "STRING"}
    },
    "required": ["filename", "content"]
}


def get_ranked_flash_models(api_key):
    """Lists stable Gemini Flash models that support generateContent, newest first."""
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
        if short_name in KNOWN_RETIRED_MODELS:
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


try:
    MODEL_CANDIDATES = get_ranked_flash_models(API_KEY)
except Exception as e:
    print(f"Could not auto-detect Flash models, falling back to hardcoded list. Reason: {e}")
    MODEL_CANDIDATES = FALLBACK_MODELS

claimed_files = common.load_claimed_files()
available_files = common.get_available_files(claimed_files)
repo_manifest, manifest_json = common.build_manifest()
prompt = common.build_prompt(
    "the lead Principal Software Architect",
    claimed_files, available_files, manifest_json, repo_manifest
)


def call_fn(model):
    url = f"{BASE_URL}/models/{model}:generateContent"
    headers = {"Content-Type": "application/json"}
    payload = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {
            "responseMimeType": "application/json",
            "responseSchema": RESPONSE_SCHEMA,
            "maxOutputTokens": 16000,
            # Gemini 3.x models think by default, and thinking tokens are
            # drawn from the SAME maxOutputTokens budget as the visible
            # answer - "minimal" leaves nearly all of that budget for the
            # actual file content instead of silently eating it, which is
            # what was causing repeated truncated/unterminated JSON output.
            "thinkingConfig": {
                "thinkingLevel": "minimal"
            }
            # temperature/top_p/top_k intentionally omitted: deprecated on 3.x Flash models
        }
    }
    return common.call_with_retry(url, headers, payload, params={"key": API_KEY})


def extract_text_fn(response):
    """Defensive on purpose: a 200 response doesn't guarantee a normal
    candidates[0].content.parts[0].text shape. Gemini can return a
    candidate with no 'parts' at all when generation is cut off
    (finishReason: MAX_TOKENS), safety-filtered, or otherwise produces no
    visible text. Any missing-shape case here must return None rather than
    raise, so try_generate's fallback to the next model actually runs
    instead of the whole generation flow crashing on model #1."""
    try:
        data = response.json()
    except ValueError:
        print("Gemini response was not valid JSON:")
        print(response.status_code, response.text[:500])
        return None

    candidates = data.get("candidates")
    if not candidates:
        print("No candidates returned by Gemini. Full response:")
        print(json.dumps(data, indent=2))
        return None

    candidate = candidates[0]
    finish_reason = candidate.get("finishReason")
    parts = candidate.get("content", {}).get("parts")

    if not parts:
        print(f"Gemini candidate had no usable 'parts' (finishReason: {finish_reason}). "
              f"Usually means the response was cut off, safety-filtered, or otherwise "
              f"produced no visible text. Full candidate for diagnosis:")
        print(json.dumps(candidate, indent=2))
        return None

    text = parts[0].get("text")
    if not text:
        print("Gemini candidate's first part had no 'text' field. Full part for diagnosis:")
        print(json.dumps(parts[0], indent=2))
        return None

    return text


try:
    target_file, file_content = common.pick_unclaimed_file(
        MODEL_CANDIDATES, call_fn, extract_text_fn, claimed_files
    )
    if target_file is None:
        exit(0)  # collision-exhausted, not an error

    common.write_file_and_claim(target_file, file_content, claimed_files)
    print(f"Success! The Gemini agent has modified or created the '{target_file}' file.")

except common.GenerationFailed as e:
    print(f"Generation failed: {e}")
    exit(1)
except Exception as e:
    print(f"A structural or network error occurred: {e}")
    exit(1)
