#!/usr/bin/env python3
import argparse
import base64
import io
import json
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MODEL = None
PROCESSOR = None
MODEL_PATH = None


def fallback(category="built_in_model_runtime_error", evidence="builtin_runtime_error"):
    return {
        "focusState": "unknown",
        "activityCategory": category,
        "activitySummary": None,
        "confidence": 0.0,
        "evidenceCodes": [evidence],
        "nudgeSuggested": False,
    }


def strict_prompt(payload):
    goal = payload.get("goal", {})
    system_context = " | ".join(payload.get("contextSummaryText", [])[-8:]) or "none"
    return f"""Classify this Mac screenshot against the user's active goal.
Return strict JSON only with this schema:
{{"focusState":"on_goal|maybe|off_goal|unknown","activityCategory":"short_snake_case","activitySummary":"safe short generic summary or null","confidence":0.0,"evidenceCodes":["short_code"],"nudgeSuggested":false}}

Goal: {goal.get("title", "")}
Description: {goal.get("description", "")}
Allowed apps: {", ".join(goal.get("allowedApps", []))}
Blocked apps: {", ".join(goal.get("blockedApps", []))}
On-goal examples: {" | ".join(goal.get("onGoalExamples", []))}
Off-goal examples: {" | ".join(goal.get("offGoalExamples", []))}
Current app: {payload.get("appName", "unknown")}
Bundle id: {payload.get("bundleIdentifier") or "unknown"}
System activity context: {system_context}
Context: You receive exactly one current screenshot image plus system context about the focused app and visible apps with windows on active displays. Use both. Summarize the user's overall activity across relevant visible apps, not just the foreground app.
Always write activitySummary when the image or system context gives enough context. Make it a short phrase under 90 characters, like "Using Codex, Focula, and Reminders to plan app fixes" or "Running Swift tests while editing code". Mention safe app names when they clarify the activity. Do not quote visible text, URLs, emails, chat participants, document titles, private names, or message contents. Use null only when the activity is unclear. Use evidence codes only."""


def clean_summary(value):
    if not isinstance(value, str):
        return None
    cleaned = re.sub(r"\s+", " ", value).strip()
    if not cleaned:
        return None
    cleaned = re.sub(r"https?://\S+|www\.\S+", "[link]", cleaned, flags=re.I)
    cleaned = re.sub(r"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}", "[email]", cleaned, flags=re.I)
    cleaned = re.sub(r"`[^`]*`|\"[^\"]*\"|'[^']*'", "[text]", cleaned)
    cleaned = re.sub(r"\b\d{4,}\b", "[number]", cleaned)
    return cleaned[:90].strip()


def load_model():
    global MODEL, PROCESSOR
    if MODEL is not None and PROCESSOR is not None:
        return MODEL, PROCESSOR

    from mlx_vlm import load

    MODEL, PROCESSOR = load(MODEL_PATH)
    return MODEL, PROCESSOR


def classify(payload):
    try:
        from PIL import Image
        from mlx_vlm import generate
        from mlx_vlm.prompt_utils import apply_chat_template
        from mlx_vlm.utils import load_config

        model, processor = load_model()
        images = decode_images(payload)
        config = load_config(MODEL_PATH)
        parsed = generate_json(model, processor, config, payload, images)
        if parsed is None and len(images) > 1:
            parsed = generate_json(model, processor, config, payload, [images[-1]])
        if parsed is None:
            return fallback("parse_failed", "strict_json_missing")
        return classifier_result(parsed)
    except Exception as exc:
        result = fallback()
        result["evidenceCodes"] = ["builtin_runtime_error", exc.__class__.__name__]
        return result


def decode_images(payload):
    from PIL import Image

    image_bytes = base64.b64decode(payload["imageBase64"])
    return [Image.open(io.BytesIO(image_bytes)).convert("RGB")]


def generate_json(model, processor, config, payload, images):
    from mlx_vlm import generate
    from mlx_vlm.prompt_utils import apply_chat_template

    prompt = apply_chat_template(processor, config, strict_prompt(payload), num_images=len(images))
    generated = generate(model, processor, prompt, images, max_tokens=180, temperature=0.0)
    text = getattr(generated, "text", generated)
    start = text.find("{")
    end = text.rfind("}")
    if start < 0 or end < start:
        return None
    return json.loads(text[start : end + 1])


def classifier_result(parsed):
    return {
        "focusState": parsed.get("focusState", "unknown"),
        "activityCategory": parsed.get("activityCategory", "unknown"),
        "activitySummary": clean_summary(parsed.get("activitySummary")),
        "confidence": float(parsed.get("confidence", 0.0)),
        "evidenceCodes": [str(code) for code in parsed.get("evidenceCodes", [])][:6],
        "nudgeSuggested": bool(parsed.get("nudgeSuggested", False)),
    }


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/health":
            self.send_error(404)
            return
        self.write_json({"ok": True, "modelPath": MODEL_PATH})

    def do_POST(self):
        if self.path != "/classify":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", "0"))
        payload = json.loads(self.rfile.read(length))
        self.write_json(classify(payload))

    def write_json(self, payload):
        data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format, *args):
        return


def main():
    global MODEL_PATH
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-path", required=True)
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    MODEL_PATH = args.model_path
    ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
