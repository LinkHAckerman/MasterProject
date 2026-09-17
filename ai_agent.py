import os
import requests
import json

# 1. Access the free Gemini API
API_KEY = os.environ.get("GEMINI_API_KEY")
url = f"https://googleapis.com{API_KEY}"

# 2. Grab your current repository files so the AI knows what to work on
# For a simple version, we will instruct the AI to write a daily module.
prompt = """
You are an autonomous AI coding agent working on a software project. 
Review the project and write the NEXT logical code feature or update.
Output ONLY valid Python code. Do not include markdown code blocks (```python) or text.
Just code.
"""

payload = {"contents": [{"parts": [{"text": prompt}]}]}
headers = {"Content-Type": "application/json"}

response = requests.post(url, headers=headers, data=json.dumps(payload))
ai_code = response.json()['candidates'][0]['content']['parts'][0]['text']

# Clean up any accidental markdown wrappers if the AI outputs them
ai_code = ai_code.replace("```python", "").replace("```", "").strip()

# 3. Save the AI's output to a file that gets committed
with open("daily_update.py", "w") as f:
    f.write(ai_code)

print("AI has successfully written today's code block.")
