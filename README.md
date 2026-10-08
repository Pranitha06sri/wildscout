# WildScout

**Your offline AI companion for exploring nature safely.**

Scout → Identify → WildSafe → Learn → Touch Grass

Initial Python/FastAPI backend using local Ollama **qwen3-vl:2b**. No cloud AI,
database, authentication, location tracking or Flutter frontend.

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
verified. Check the local Ollama runtime/logs and available memory, then rerun the
`--image` test above with a real nature photo.

GitHub creation/push was blocked: GitHub CLI was absent and Git Credential Manager
provided no noninteractive GitHub credential. After installing GitHub CLI and running
`gh auth login`, run these commands from this project directory:

```powershell
gh repo create wildscout --public --source . --remote origin --push
```

If a repository with that name already exists in your account, inspect it before
connecting or pushing; do not overwrite unrelated remote history.
