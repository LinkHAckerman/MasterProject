import os
import requests
import json

# 1. Fetch the Google Gemini API Key
API_KEY = os.environ.get("GEMINI_API_KEY")
if not API_KEY:
    print("Error: GEMINI_API_KEY is missing from GitHub Secrets.")
    exit(1)

url = f"https://googleapis.com{API_KEY}"

# 2. Gather existing directory snapshot so the AI sees EVERYTHING it has built so far
repo_manifest = {}
important_files = ["index.html", "styles.css", "app.js", "CryptoEngine.cs", "Analytics.cpp", "README.md"]

for file_name in important_files:
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

# 4. Transmit to Gemini
payload = {
    "contents": [{"parts": [{"text": prompt}]}],
    "generationConfig": {
        "temperature": 0.2,
        "responseMimeType": "application/json"
    }
}
headers = {"Content-Type": "application/json"}

try:
    response = requests.post(url, headers=headers, data=json.dumps(payload))
    response.raise_for_status()
    
    # 5. Process JSON payload and dynamically write the chosen language file
    response_data = response.json()
    ai_output_raw = response_data['contents'][0]['parts'][0]['text'] if 'contents' in response_data else response_data['candidates'][0]['content']['parts'][0]['text']
    
    # Parse the target action
    action = json.loads(ai_output_raw.strip())
    target_file = action["filename"]
    file_content = action["content"]
    
    with open(target_file, "w", encoding="utf-8") as f:
        f.write(file_content)
        
    print(f"Success! The AI Agent has modified or created the '{target_file}' file.")

except Exception as e:
    print(f"A structural or network error occurred: {e}")
    exit(1)
