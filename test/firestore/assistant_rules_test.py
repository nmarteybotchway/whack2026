"""Exercise checked-in rules against the local Firestore emulator, never production.

From the repository root:
firebase emulators:exec --only firestore --project demo-assistant \
  --config firebase.assistant-test.json 'python3 test/firestore/assistant_rules_test.py'
"""

import base64
import json
import os
import time
import urllib.error
import urllib.request

HOST = os.environ.get("FIRESTORE_EMULATOR_HOST", "")
assert HOST.startswith(("127.0.0.1:", "localhost:")), "Local emulator required"
PROJECT = "demo-assistant"
ROOT = f"projects/{PROJECT}/databases/(default)/documents"
BASE = f"http://{HOST}/v1/{ROOT}"


def token(uid):
    def encode(value):
        return base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip("=")
    now = int(time.time())
    return ".".join([
        encode({"alg": "none", "typ": "JWT"}),
        encode({"aud": PROJECT, "iss": f"https://securetoken.google.com/{PROJECT}",
                "sub": uid, "user_id": uid, "iat": now, "exp": now + 3600,
                "auth_time": now, "firebase": {"sign_in_provider": "anonymous"}}),
        "",
    ])


def call(method, path="", body=None, uid="alice", admin=False):
    headers = {"Content-Type": "application/json"}
    if admin:
        headers["Authorization"] = "Bearer owner"
    elif uid is not None:
        headers["Authorization"] = "Bearer " + token(uid)
    request = urllib.request.Request(BASE + path, method=method, headers=headers,
                                     data=None if body is None else json.dumps(body).encode())
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, json.load(error)


def value(item):
    if isinstance(item, bool):
        return {"booleanValue": item}
    if isinstance(item, str):
        return {"stringValue": item}
    if isinstance(item, int):
        return {"integerValue": str(item)}
    if isinstance(item, float):
        return {"doubleValue": item}
    if isinstance(item, list):
        return {"arrayValue": {"values": [value(x) for x in item]}}
    if isinstance(item, dict):
        return {"mapValue": {"fields": {k: value(v) for k, v in item.items()}}}
    raise TypeError(type(item))


def write(path, fields, timestamp=None):
    data = {k: value(v) for k, v in fields.items()}
    if path.startswith("users/alice/foodEntries/"):
        data["localDate"] = {"timestampValue": "2026-11-07T00:00:00Z"}
    result = {"update": {"name": ROOT + "/" + path, "fields": data}}
    if timestamp:
        result["updateTransforms"] = [{"fieldPath": timestamp, "setToServerValue": "REQUEST_TIME"}]
    return result


def commit(writes, **kwargs):
    return call("POST", ":commit", {"writes": writes}, **kwargs)


def expect(label, expected, response):
    actual, body = response
    assert actual == expected, f"{label}: expected {expected}, got {actual}: {body}"
    print("PASS:", label)


profile = "users/alice"
expect("owner can create preferences", 200,
       commit([write(profile, {"dietary": ["Vegan"]}, "updatedAt")]))
expect("owner can read profile", 200, call("GET", "/" + profile))
expect("other user cannot read profile", 403, call("GET", "/" + profile, uid="bob"))
expect("unauthenticated profile read denied", 403, call("GET", "/" + profile, uid=None))
expect("other user cannot change preferences", 403,
       commit([write(profile, {"dietary": ["Vegetarian"]}, "updatedAt")], uid="bob"))
expect("seed pre-existing profile field", 200,
       commit([write(profile, {"dietary": ["Vegan"], "displayName": "Alice"}, "updatedAt")], admin=True))
expect("preference update preserves existing extra profile fields", 200,
       commit([write(profile, {"dietary": ["Vegan", "Dairy free"], "displayName": "Alice"}, "updatedAt")]))
expect("profile update cannot introduce arbitrary fields", 403,
       commit([write(profile, {"dietary": [], "displayName": "Alice", "admin": True}, "updatedAt")]))

settings = {"schemaVersion": 1, "name": "Guide", "tone": "Calm guide",
            "answerLength": "short", "supportive": True, "humor": False,
            "instructions": "Be practical", "voiceEnabled": False,
            "locale": "en-GB", "speechRate": 0.5, "voiceName": ""}
settings_path = "users/alice/assistantSettings/preferences"
expect("valid personality settings save", 200,
       commit([write(settings_path, settings, "updatedAt")]))
expect("other user cannot read personality", 403, call("GET", "/" + settings_path, uid="bob"))
expect("overlong custom instructions rejected", 403,
       commit([write(settings_path, {**settings, "instructions": "x" * 1001}, "updatedAt")]))
expect("invalid voice speed rejected", 403,
       commit([write(settings_path, {**settings, "speechRate": 9.0}, "updatedAt")]))

health = "users/alice/healthData/latest"
expect("health collection opt-in schema supported", 200,
       commit([write(health, {"optedIn": True, "heartRateBpm": 72}, "updatedAt")]))
expect("other user cannot read health summary", 403, call("GET", "/" + health, uid="bob"))
expect("owner can delete stored health summary", 200,
       commit([{"delete": ROOT + "/" + health}]))

entry = {"name": "Porridge", "localDay": "2026-11-07", "kind": "eaten", "source": "assistant"}
marker = {"toolName": "propose_food_log", "summary": "Log porridge",
          "result": {"success": True, "entryId": "entry-one"}}
entry_path = "users/alice/foodEntries/entry-one"
marker_path = "users/alice/assistantActions/action-one"
expect("atomic food entry and action marker save", 200,
       commit([write(entry_path, entry, "createdAt"), write(marker_path, marker, "createdAt")]))
expect("other user cannot read food log", 403, call("GET", "/" + entry_path, uid="bob"))
expect("action markers cannot be overwritten", 403,
       commit([write(marker_path, marker, "createdAt")]))
expect("food entries cannot be overwritten", 403,
       commit([write(entry_path, {**entry, "name": "Toast"}, "createdAt")]))
expect("invalid food kind rejected", 403,
       commit([write("users/alice/foodEntries/bad", {**entry, "kind": "unknown"}, "createdAt")]))

image_path = "food_images/almond_milk"
expect("seed shared food image", 200,
       commit([write(image_path, {"name": "almond milk", "url": "https://example.org/milk.jpg", "page": "https://example.org/milk"})], admin=True))
expect("signed-in user can retrieve shared images", 200, call("GET", "/" + image_path))
expect("unauthenticated shared image read denied", 403, call("GET", "/" + image_path, uid=None))
print("All assistant Firestore rules checks passed.")
