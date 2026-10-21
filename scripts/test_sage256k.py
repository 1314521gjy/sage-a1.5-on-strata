import json
import time
import urllib.request

URL = "http://127.0.0.1:8193/v1/chat/completions"
body = {
    "model": "sage-a1.5-q4_k_m",
    "messages": [
        {"role": "system", "content": "You are a concise assistant. Answer in one short sentence."},
        {"role": "user", "content": "用一句话回答：1+1等于几？"},
    ],
    "max_tokens": 1024,
    "temperature": 0,
}
req = urllib.request.Request(URL, data=json.dumps(body).encode("utf-8"),
                             headers={"Content-Type": "application/json"})
t0 = time.time()
with urllib.request.urlopen(req, timeout=600) as r:
    data = json.loads(r.read())
elapsed = time.time() - t0
ch = data["choices"][0]
msg = ch["message"]
print("elapsed_s", round(elapsed, 2))
print("finish", ch.get("finish_reason"))
print("content", repr(msg.get("content")))
rc = msg.get("reasoning_content") or ""
print("reasoning_len", len(rc))
print("reasoning_head", repr(rc[:200]))
print("usage", data.get("usage"))
print("timings", data.get("timings"))
