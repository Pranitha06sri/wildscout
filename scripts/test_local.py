"""Run deterministic API checks; optionally test live local Ollama with --image."""
import argparse
import asyncio
import io
import json
import sys
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import httpx
from PIL import Image
from backend.main import Analysis, MISSION, SAFE_NOTE, app, enforce_safety


async def checks(image_path):
    sample = dict(identification="Mushroom", confidence="low", visual_clues=["Rounded cap"],
                  nature_context="Growing on soil", safety_level="low", safety_note="Safe to eat",
                  mission="Pick it")
    result = enforce_safety(Analysis(**sample))
    assert result.safety_level == "unknown" and result.safety_note == SAFE_NOTE
    assert result.mission == MISSION
    unsafe = enforce_safety(Analysis(**{**sample, "identification": "Edible mushroom", "confidence": "high"}))
    assert unsafe.confidence == "low" and "Unknown" in unsafe.identification
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
            return httpx.Response(200, request=httpx.Request("POST", "http://localhost"),
                                  json={"message": {"content": json.dumps(sample)}})
        with patch("backend.main.httpx.AsyncClient.post", valid_response):
            # Use the original client request method so only inference is mocked.
            response = await client.request("POST", "/analyze", files={"image": ("sample.png", buffer.getvalue())})
            assert response.status_code == 200, response.text
            assert response.json()["safety_level"] == "unknown"
        async def invalid_response(*args, **kwargs):
            return httpx.Response(200, request=httpx.Request("POST", "http://localhost"),
                                  json={"message": {"content": "{}"}})
        with patch("backend.main.httpx.AsyncClient.post", invalid_response):
            response = await client.request("POST", "/analyze", files={"image": ("sample.png", buffer.getvalue())})
            assert response.status_code == 502
        print("PASS: upload validation, schema rejection, Ollama payload and conservative safety policy")
        if image_path:
            response = await client.post("/analyze", files={"image": (image_path.name, image_path.read_bytes())})
            assert response.status_code == 200, response.text
            Analysis.model_validate(response.json())
            print("PASS: live qwen3-vl:2b image inference")
            print(json.dumps(response.json(), indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", type=Path, help="Local JPEG, PNG or WebP for real model inference")
    asyncio.run(checks(parser.parse_args().image))
