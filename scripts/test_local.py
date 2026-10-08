"""Run deterministic API checks; optionally test live local Ollama with --image."""
import argparse
import asyncio
import io
import json
import sys
import time
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import httpx
from PIL import Image
from backend.main import Analysis, MISSION, SAFE_NOTE, app, enforce_safety


async def checks(image_path, smoke=False):
    sample = dict(identification="Mushroom", confidence="low", visual_clues=["Rounded cap"],
                  nature_context="Growing on soil", safety_level="low", safety_note="Safe to eat",
                  mission="Pick it")
    result = enforce_safety(Analysis(**sample))
    assert result.safety_level == "unknown" and result.safety_note == SAFE_NOTE
    assert result.mission == MISSION
    unsafe = enforce_safety(Analysis(**{**sample, "identification": "Edible mushroom", "confidence": "high"}))
    assert unsafe.confidence == "low" and "Unknown" in unsafe.identification
    for confidence in ("low", "moderate", "high"):
        for risk in ("unknown", "low", "caution", "high"):
            safe = enforce_safety(Analysis(**{**sample, "confidence": confidence, "safety_level": risk}))
            expected = "high" if risk == "high" else ("unknown" if confidence == "low" else "caution")
            assert safe.safety_level == expected
            assert safe.safety_note == SAFE_NOTE and safe.mission == MISSION
            Analysis.model_validate(safe.model_dump())
    fixture = json.loads((Path(__file__).resolve().parents[1] / "docs/sample_analyze_response.json").read_text())
    Analysis.model_validate(fixture)
    assert fixture["safety_note"] == SAFE_NOTE and fixture["mission"] == MISSION
    buffer = io.BytesIO()
    Image.new("RGB", (32, 32), "green").save(buffer, "PNG")
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        assert (await client.get("/health")).status_code == 200
        assert (await client.post("/analyze", files={"image": ("bad.png", b"bad")})).status_code == 415
        assert (await client.post("/analyze", files={"image": ("empty.png", b"")})).status_code == 400
        assert (await client.post("/analyze")).status_code == 422
        async def valid_response(*args, **kwargs):
            assert kwargs["json"]["model"] == "qwen3-vl:2b"
            assert kwargs["json"]["messages"][0]["images"]
            assert kwargs["json"]["think"] is False
            assert kwargs["json"]["messages"][-1] == {
                "role": "assistant", "content": "<think>\n\n</think>\n\n"}
            return httpx.Response(200, request=httpx.Request("POST", "http://localhost"),
                                  json={"done": True, "done_reason": "stop", "message": {"content": json.dumps(sample)}})
        with patch("backend.main.httpx.AsyncClient.post", valid_response):
            # Use the original client request method so only inference is mocked.
            response = await client.request("POST", "/analyze", files={"image": ("sample.png", buffer.getvalue())})
            assert response.status_code == 200, response.text
            assert response.json()["safety_level"] == "unknown"
            assert response.json()["safety_note"] == SAFE_NOTE and response.json()["mission"] == MISSION
            assert set(response.json()) == set(fixture)
        def envelope(content):
            return {"done": True, "message": {"content": content}}
        invalid_bodies = [
            envelope("{}"), envelope("not JSON"), envelope("```json\n{}\n```"),
            envelope(json.dumps({**sample, "confidence": "certain"})),
            envelope(json.dumps({**sample, "visual_clues": [42]})),
            envelope(json.dumps({**sample, "identification": "  "})),
            envelope(json.dumps({**sample, "extra": "unexpected"})),
            envelope(None), envelope({}), [], None, {}, {"done": True, "message": None},
            {"done": False, "message": {"content": json.dumps(sample)}},
            {"done": True, "done_reason": "length", "message": {"content": json.dumps(sample)}},
        ]
        for body in invalid_bodies:
            async def invalid_response(*args, _body=body, **kwargs):
                return httpx.Response(200, request=httpx.Request("POST", "http://localhost"), json=_body)
            with patch("backend.main.httpx.AsyncClient.post", invalid_response):
                response = await client.request("POST", "/analyze", files={"image": ("sample.png", buffer.getvalue())})
                assert response.status_code == 502, response.text
                assert response.json() == {"detail": "Ollama returned invalid analysis JSON"}
        for raw in (b"not JSON", b"[" * 2000 + b"0" + b"]" * 2000):
            async def invalid_outer(*args, _raw=raw, **kwargs):
                return httpx.Response(200, request=httpx.Request("POST", "http://localhost"), content=_raw)
            with patch("backend.main.httpx.AsyncClient.post", invalid_outer):
                response = await client.request("POST", "/analyze", files={"image": ("sample.png", buffer.getvalue())})
                assert response.status_code == 502
        for error, status in ((httpx.ConnectError("offline"), 503), (httpx.ReadTimeout("slow"), 504)):
            async def failed_inference(*args, _error=error, **kwargs):
                raise _error
            with patch("backend.main.httpx.AsyncClient.post", failed_inference):
                response = await client.request("POST", "/analyze", files={"image": ("sample.png", buffer.getvalue())})
                assert response.status_code == status
        schema = (await client.get("/openapi.json")).json()
        assert set(schema["components"]["schemas"]["Analysis"]["required"]) == set(fixture)
        print("PASS: stable contract, frontend fixture, malformed/truncated JSON, upstream errors and WildSafe overrides")
        if image_path or smoke:
            filename, data = (image_path.name, image_path.read_bytes()) if image_path else ("smoke.png", buffer.getvalue())
            started = time.perf_counter()
            print(f"Starting live /analyze: {filename}, {len(data)} bytes", flush=True)
            response = await client.post("/analyze", files={"image": (filename, data)})
            print(f"Live /analyze: HTTP {response.status_code}, {time.perf_counter() - started:.3f} seconds", flush=True)
            assert response.status_code == 200, response.text
            Analysis.model_validate(response.json())
            print("PASS: live qwen3-vl:2b image inference")
            print(json.dumps(response.json(), indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", type=Path, help="Local JPEG, PNG or WebP for real model inference")
    parser.add_argument("--smoke", action="store_true", help="Live inference with an in-memory 32x32 green PNG")
    args = parser.parse_args()
    asyncio.run(checks(args.image, args.smoke))
