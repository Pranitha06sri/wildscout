# WildScout

**Your offline AI companion for exploring nature safely.**

Scout → Identify → WildSafe → Learn → Touch Grass

Initial Python/FastAPI backend using local Ollama **qwen3-vl:2b**. No cloud AI,
database, authentication or location tracking. The Flutter mobile companion is in
[`mobile/`](mobile/README.md), with sample mode enabled by default for development.

## Run locally

Python 3.11+ and Ollama are required. Initial package/model downloads need internet;
inference runs offline once installed.

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
ollama pull qwen3-vl:2b
# Start ollama serve in another terminal if Ollama is not already running.
python -m uvicorn backend.main:app --host 127.0.0.1 --port 8000
```

Open http://127.0.0.1:8000/docs or send multipart field `image`:

```powershell
curl.exe -F "image=@C:\path\nature.jpg" http://127.0.0.1:8000/analyze
python scripts/test_local.py
python -u scripts/test_local.py --smoke
python scripts/test_local.py --image C:\path\nature.jpg
```

`GET /health` checks the API process only. `POST /analyze` accepts JPEG, PNG or WebP
(8 MiB / 20 megapixels maximum), strips metadata by re-encoding, and sends the image
with a prompt and JSON schema to local Ollama. Pydantic independently validates the
response. Uploads are held in memory and never saved. One inference runs at a time;
timeout is 600 seconds to accommodate CPU inference and cold model loading. Override
it with `OLLAMA_TIMEOUT_SECONDS`. The service is intended for a single local user, bound to
loopback; do not expose it publicly.

Response fields: `identification`, `confidence` (`low|moderate|high`), `visual_clues`,
`nature_context`, `safety_level` (`unknown|low|caution|high`), `safety_note`, `mission`.
Errors: 400 empty upload, 413 size limit, 415 invalid image, 422 missing field,
502 invalid model JSON, 503 unavailable Ollama/model, 504 inference timeout.

## API contract for Flutter

### Start the services

Run Ollama in one terminal (skip `serve` if the desktop app already serves port 11434):

```powershell
ollama serve
```

The installed model must be named `qwen3-vl:2b`; check with `ollama list`.
If it is missing, download it once with `ollama pull qwen3-vl:2b`.
From the WildScout project directory, start FastAPI in another terminal:

```powershell
.venv\Scripts\python.exe -m uvicorn backend.main:app --host 127.0.0.1 --port 8000
```

Base URL: `http://127.0.0.1:8000`. Interactive API docs: `/docs`;
machine-readable schema: `/openapi.json`. `GET /health` returns
`{"status":"ok","model":"qwen3-vl:2b"}` and does not run inference.

### Request

`POST /analyze`, `Content-Type: multipart/form-data`, one required file part named
**`image`**. Send binary JPEG, PNG or WebP bytes, not a JSON body or a base64 string.
Let the HTTP client generate the multipart boundary. Maximum file size: 8 MiB;
maximum decoded resolution: 20 megapixels. No authentication header is required.

```powershell
curl.exe --max-time 660 -F "image=@C:\path\nature.jpg" http://127.0.0.1:8000/analyze
```

Inference can take minutes on this computer; give Flutter a receive timeout above
the backend's 600-second Ollama read timeout for a single request. Avoid overlapping
analyze requests: inference is serialized and queue waiting can add time. Desktop
Flutter uses the base URL above; the standard Android emulator reaches the host at
`http://10.0.2.2:8000`. A physical phone's `localhost` refers to the phone; it requires
separate local connectivity setup. The backend remains bound to loopback by default.

### Successful response

HTTP **200**, `Content-Type: application/json`. All seven fields are required and
non-null; there are no additional response keys. Strings are trimmed and nonempty.

| Field | Type / allowed values | Limits |
| --- | --- | --- |
| `identification` | string | 1–500 characters |
| `confidence` | `low`, `moderate`, `high` | enum |
| `visual_clues` | array of strings | 1–8 items; 1–300 characters each |
| `nature_context` | string | 1–1000 characters |
| `safety_level` | `unknown`, `low`, `caution`, `high` | enum |
| `safety_note` | string | 1–1000 characters |
| `mission` | string | 1–500 characters |

`low` remains a recognized safety enum value for client compatibility, but WildSafe
never emits it. A high-risk warning remains `high`; other low-confidence results
become `unknown`, and other results become `caution`. Uncertain identification is
forced to low confidence. Every success follows model validation → WildSafe overrides
→ final contract validation. The model's safety note and mission are always replaced.

This example is also saved in `docs/sample_analyze_response.json`:

```json
{
  "identification": "Tentative visual identification: possible broadleaf plant",
  "confidence": "moderate",
  "visual_clues": ["Green oval leaves", "Visible branching veins"],
  "nature_context": "Unverified model context: leafy vegetation beside a trail",
  "safety_level": "caution",
  "safety_note": "Image identification is tentative and cannot establish safety. Do not eat, touch, handle, or approach unfamiliar plants, fungi, or animals. Observe from an existing safe position and keep your distance.",
  "mission": "Put your phone away for one minute and notice three colors from your existing safe position, without touching or approaching wildlife."
}
```

### Frontend development without inference

Copy `docs/sample_analyze_response.json` into a Flutter asset or fake HTTP response
and decode it with the same response DTO used for real HTTP 200 results. It is a
curated development fixture, not a live identification. It contains the actual
server-controlled safety note and mission and is checked against the response model
by the local test script. No mock route or production-mode switch is added.

### Error responses

For the errors below, branch on the HTTP status before decoding a success DTO.
Errors use `{"detail":"..."}`. HTTP 422 uses FastAPI's structured `detail` array.
Invalid model JSON is never returned as a successful frontend response, and raw
model text, tracebacks and upstream response bodies are not included in these errors.

| Status | Meaning / detail |
| --- | --- |
| 400 | `Image is empty` |
| 413 | `Image exceeds 8 MiB` or `Image exceeds 20 megapixels` |
| 415 | `Use JPEG, PNG or WebP` or `Invalid or unsupported image` |
| 422 | Missing `image` or invalid multipart field; `detail` is an array |
| 502 | `Ollama returned invalid analysis JSON`; malformed outer JSON, invalid field types/enums, missing/extra fields, incomplete or truncated output |
| 503 | `Local Ollama unavailable; check service and qwen3-vl:2b` |
| 504 | `Local Ollama inference timed out` |

Example HTTP 502 body:

```json
{"detail":"Ollama returned invalid analysis JSON"}
```

### Test commands

Fast contract, fixture, invalid-JSON and WildSafe tests (no Ollama or running HTTP
server needed; real application routes run in-process and model responses are mocked):

```powershell
.venv\Scripts\python.exe -u scripts\test_local.py
```

Check the running backend without invoking inference:

```powershell
curl.exe http://127.0.0.1:8000/health
```

Optional full local model test, which can take several minutes:

```powershell
.venv\Scripts\python.exe -u scripts\test_local.py --smoke
```

## Safety policy

All model output is untrusted. Descriptions are tentative and unverified. The server
replaces safety advice and missions with fixed conservative wording, never reports
`low` risk, and treats low confidence as unknown (or preserves a high-risk warning).
A defensive language filter discards descriptive output containing action or safety
claims. Language filtering cannot prove semantic safety: model identifications and
visual clues may still be wrong. Never use this app to decide whether an organism is
safe to eat, touch or approach. The mission asks for one minute of observation from
an existing safe position with the phone put away.

No `.env` is needed. Optional `OLLAMA_URL` defaults to `http://127.0.0.1:11434` and
must use a loopback host. No API keys are required. Model files, datasets, uploads,
generated artifacts, virtual environments and secrets are excluded from Git.

## Implementation references

The request uses Ollama's documented image and JSON schema interface:
[Structured outputs](https://ollama.com/blog/structured-outputs).
Community research highlighted malformed JSON and brittle parsing fallbacks:
[Clean JSON Extraction with Ollama and Python](https://dev.to/nearshi/-clean-json-extraction-with-ollama-and-python-21f3).
WildScout uses schema-constrained generation plus independent validation and rejects
invalid responses rather than recovering arbitrary fragments from model prose.

## Initial local verification

On October 8, 2026, deterministic API checks passed: valid upload forwarding,
empty/invalid/missing image handling, invalid model JSON rejection, and conservative
safety/mission replacement. `pip check` reported no broken requirements.
Ollama 0.40.0 listed `qwen3-vl:2b`, but live analysis of a synthetic leaf PNG timed
out with both 180-second and 600-second limits. Real image inference is not yet
verified in that initial run.

### Timeout diagnosis and fix

The subsequent investigation found working local metadata endpoints and a CPU-only
`llamacpp` runner (`size_vram: 0`, context 4096). Historical Ollama logs show a
Ryzen 3 3250U, about 6 GiB RAM with limited free memory, roughly 4 output tokens/s,
and a 1024-token minimum vision budget. Even a tiny image therefore does not avoid
all vision processing costs. Cold direct image inference timed out before headers
at 121.091 seconds; warm direct image inference completed in 11.218 seconds but
used all 16 tokens for thinking and returned an empty answer. `think: false` alone
did not prevent this behavior on this installation.

The verified workaround requests `think: false`, adds `/no_think`, and prefills a
completed assistant thinking block. It keeps the same `qwen3-vl:2b` model, weights,
Ollama endpoint, JSON schema and architecture. The backend prompt is shorter and
the output budget is 320 tokens. Safety advice and missions remain server-controlled.
Image re-encoding/base64 was valid; image preparation runs in a worker thread and
the Ollama HTTP call is asynchronous. Non-streaming inference waits for the entire
answer, so slow CPU processing and unwanted reasoning consume the read-timeout budget.

Measured results on October 8, 2026:

- Direct 32x32 PNG (100 bytes), one-line prompt, assistant prefill: `green`, first
  answer at 5.391 seconds; completed in 17.045 seconds with 2 output tokens.
- Full FastAPI `/analyze` route using ASGI transport, 32x32 green PNG (110 bytes):
  HTTP 200 in **253.271 seconds**, independently validated JSON, low confidence,
  unknown identification/safety, and the fixed safe mission. Deterministic API
  checks also passed. This verifies the application route and real local Ollama
  inference; it is not a TCP-server or wildlife identification accuracy benchmark.

Reproduce from the project directory:

```powershell
.venv\Scripts\python.exe -u scripts\diagnose_ollama.py --no-think --prefill --timeout 120
.venv\Scripts\python.exe -u scripts\test_local.py --smoke
```

The direct probe uses only Python's standard library, reports local endpoint status,
inference timings and token metrics, and returns a nonzero exit code for failed or
truncated inference. Remaining limitation: CPU-only cold/vision/schema processing
can still take minutes. The previous 180/600-second requests did not retain runtime
timings, so their individual phase costs cannot be reconstructed exactly.

Relevant upstream reports:
[thinking toggle and assistant prefill](https://github.com/ollama/ollama/issues/14798),
[Qwen3-VL renderer thinking behavior](https://github.com/ollama/ollama/issues/13353).

GitHub creation/push was blocked: GitHub CLI was absent and Git Credential Manager
provided no noninteractive GitHub credential. After installing GitHub CLI and running
`gh auth login`, run these commands from this project directory:

```powershell
gh repo create wildscout --public --source . --remote origin --push
```

If a repository with that name already exists in your account, inspect it before
connecting or pushing; do not overwrite unrelated remote history.
