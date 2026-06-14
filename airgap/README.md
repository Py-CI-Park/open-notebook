# Open Notebook — Air-Gapped (Closed Network) Deployment on Windows, No Docker

This folder provides a **Docker-free, fully offline** way to run Open Notebook on a
closed-network Windows machine using just **three batch files**.

The bundle is **self-contained**: it ships its own Python, `uv`, Node.js, SurrealDB and
ffmpeg, so the closed-network machine needs **nothing pre-installed** and **never touches
the internet** at install/run time.

```
1-online-package.bat   →  (internet PC) build a complete bundle
2-airgap-install.bat   →  (closed PC) rebuild the venv fully offline, create config
3-run.bat              →  (closed PC) start all services
stop.bat               →  (closed PC) stop all services
```

---

## 1. How it works

Open Notebook is 4 processes. Docker only bundles them; nothing here requires Docker.

| # | Process | Command (run script) | Port |
|---|---------|----------------------|------|
| 1 | SurrealDB (database) | `surreal.exe start rocksdb:...` | 8000 |
| 2 | API (FastAPI; runs DB migrations on startup) | `uv run python run_api.py` | 5055 |
| 3 | Worker (embeddings, podcasts, background jobs) | `python -m surreal_commands.cli.worker --import-modules commands` | — |
| 4 | Frontend (Next.js) | `next start -p 8502` | 8502 |

The frontend proxies `/api/*` to the API via `INTERNAL_API_URL`, so only port **8502**
needs to be reachable by users.

---

## 2. Network dependency analysis (why this works offline)

| Item | Build time (internet) | Runtime (closed network) |
|------|-----------------------|--------------------------|
| Python packages | `uv sync` from PyPI (seeds `uv-cache\`) | **None** — venv rebuilt from bundled cache |
| Frontend | `npm ci` + `npm run build` | **None** — prebuilt `.next` + `node_modules` shipped |
| tiktoken `o200k_base` encoding | downloaded once | **Must be pre-baked** → shipped in `tiktoken-cache\`, injected via `TIKTOKEN_CACHE_DIR` |
| SurrealDB / ffmpeg / Node / Python / uv | downloaded into `tools\` & `uv-python\` | shipped in the bundle, added to `PATH` |
| DB migrations | — | run locally from bundled `migrations/*.surql` |
| **AI inference / embeddings** | — | **must use an on-prem endpoint** (Ollama / LM Studio / OpenAI-compatible) — cloud providers will not work |

Verified facts (tested on Windows 11 x64, uv 0.7.20):

- `uv sync --frozen --offline` rebuilds the full 207-package venv from a seeded cache with
  the network forced off (dead proxy) — including the Rust-compiled `tiktoken`.
- The only lockfile package without a prebuilt wheel is `langdetect` (pure Python), so **no
  MSVC build tools** are needed on either machine.
- Worker entry point `surreal_commands.cli.worker` has a `__main__` guard, so the
  `python -m ...` invocation behaves exactly like the `surreal-commands-worker` console script.

---

## 3. Bundle layout (= deployment layout)

`1-online-package.bat` produces `<repo>\dist\AeroOne-bundle\`. The **deploy layout is
identical** — you copy this whole folder to the closed machine and run `2` then `3` in place.

```
<bundle root>\
├── 2-airgap-install.bat
├── 3-run.bat
├── stop.bat
├── BUNDLE-INFO.txt
├── app\              ← Open Notebook source + prebuilt frontend (.next + node_modules)
│                       (.venv is created by 2-airgap-install.bat, offline)
├── tools\            ← uv.exe, node\, surreal.exe, ffmpeg\bin\
├── uv-python\        ← bundled, relocatable CPython 3.12 (uv-managed)
├── uv-cache\         ← seeded wheel/dist cache for offline `uv sync`
├── tiktoken-cache\   ← pre-baked o200k_base encoding
└── data\             ← created by install: surrealdb\, uploads\, sqlite-db\
```

---

## 4. Step-by-step

### Step 1 — Online PC (internet): build the bundle

From a checkout of this repository, on a **Windows x64** machine with internet:

```bat
cd <repo>\airgap
1-online-package.bat
```

Produces `<repo>\dist\AeroOne-bundle\`. This is the only step that needs the internet.

### Step 2 — Closed PC: install (run once)

Copy the whole bundle folder to **any empty folder** on the closed machine
(path must contain **no spaces**), then:

```bat
2-airgap-install.bat
```

This rebuilds `app\.venv` fully offline from `uv-cache\`, creates `data\`, and writes a
starter `app\.env`. Then **edit `app\.env`**:

- set `OPEN_NOTEBOOK_ENCRYPTION_KEY` to a secret string (≥16 chars)
- set your on-prem AI endpoint, e.g. `OLLAMA_BASE_URL=http://<lan-ip>:11434`

### Step 3 — Closed PC: run

```bat
3-run.bat
```

Opens 4 service windows. When the Frontend window says "Ready", open:

- Frontend: <http://127.0.0.1:8502>
- API docs: <http://127.0.0.1:5055/docs>

Stop everything with `stop.bat`.

---

## 5. Prerequisites & hard rules

- **Online PC and closed PC must both be Windows x64** — the seeded cache, `node_modules`
  and native binaries are platform-specific.
- **Deployment path must not contain spaces.**
- **AI must be on-prem.** Cloud APIs (OpenAI/Anthropic/Google) are unreachable in a closed
  network. Use Ollama, LM Studio, or any OpenAI-compatible endpoint on the LAN. For vector
  search you need an **embedding-capable** model (e.g. Ollama `nomic-embed-text`); podcasts
  need an on-prem TTS endpoint.
- Closed PC needs **nothing pre-installed** — Python/uv/Node/SurrealDB/ffmpeg all come from
  the bundle.

---

## 6. AI provider setup (in the UI)

1. Open <http://127.0.0.1:8502> → **Models** → **Add Configuration**.
2. Choose **Ollama** / **OpenAI Compatible** / **LM Studio** and set the base URL to the LAN
   endpoint.
3. If **Sync Models** tries to reach the internet and fails, **add the model names manually**.
4. Under **Default Model Assignments**, assign chat / embedding / (TTS) models.

---

## 7. Data persistence & upgrades

- All user data lives in `<bundle root>\data\` (`surrealdb\`, `uploads\`, `sqlite-db\`),
  driven by the `DATA_FOLDER` env var set by `3-run.bat`.
- To upgrade: build a new bundle on the online PC, deploy it to a new folder, and copy the
  old `data\` folder over. Your notebooks and DB are preserved.

---

## 8. Windows gotchas (handled by the scripts)

| Symptom | Cause | Handled by |
|---------|-------|------------|
| "Database is offline" / health check timeout | `.env` uses `localhost` but SurrealDB binds `127.0.0.1` | `.env` uses `ws://127.0.0.1:8000/rpc` |
| `No module named 'langgraph.checkpoint.sqlite'` | system Python shadows the venv | scripts always use `uv run` |
| Worker "Failed to canonicalize script path" | calling the `.exe` with a script path | scripts use `python -m surreal_commands.cli.worker` + `PYTHONPATH` |
| tiktoken tries to download at runtime | missing encoding cache | pre-baked `tiktoken-cache\` + `TIKTOKEN_CACHE_DIR` |
| `Failed to parse environment file .env` | Windows backslash paths in `.env` | `DATA_FOLDER`/`TIKTOKEN_CACHE_DIR` set in the batch, not `.env` |
| media/podcast processing fails | ffmpeg missing | `tools\ffmpeg\bin` added to `PATH` |

---

## 9. Version pins

Edit the top of `1-online-package.bat` to change versions:

```bat
set "SURREAL_VER=2.3.7"
set "NODE_VER=20.18.1"
```

Python is pinned to 3.12 (matches `.python-version`).

## 9b. Single ZIP & GitHub Release

`1-online-package.bat` also produces a single carry-able archive next to the folder bundle:

```
<repo>\dist\AeroOne-bundle.zip
```

Copy just this one `.zip` to the closed network, unzip it into any empty (no-spaces)
folder, then run `2-airgap-install.bat` → `3-run.bat`. (The unzipped contents are identical
to the folder bundle layout in section 3.)

### Publishing as a GitHub Release (optional)

On the online PC, after the ZIP is built, publish it as a release asset with `release.bat`
(requires the GitHub CLI `gh`, authenticated for the repo):

```bat
cd <repo>\airgap
release.bat                 REM tag defaults to: airgap-win-x64
release.bat airgap-v1.9.0   REM or pin a tag
```

This creates the release (or replaces the asset if the tag already exists) and prints the
download URL. On the closed-network side, anyone can then download `AeroOne-bundle.zip`
from the release page and run the 2 → 3 steps.

> Notes: the asset is **Windows x64 specific** and ~1–1.5 GB (GitHub's per-asset limit is
> 2 GB). The bundle binaries (Python/uv/Node/SurrealDB/ffmpeg) are **not** committed to git —
> they only ever live inside the release asset / local `dist\`.

---

## 10. Verification status

End-to-end tested on Windows 11 x64 (uv 0.7.20, Node 20.18.1, SurrealDB v2.3.7):

- **Online package**: downloads + `uv sync` (207 pkgs) + tiktoken pre-bake + frontend build — OK.
- **Offline install** (network forced off via dead proxy): venv rebuilt from cache, data + `.env` created — OK.
- **Run**: SurrealDB `:8000` 200, API `:5055/health` healthy (migrations ran), frontend `:8502`
  serving, `/api/*` proxy reaches the backend — OK.

Smoke-test on first deployment: after `3-run.bat`, confirm the API window logs "Migrations
completed", the Frontend window says "Ready", <http://127.0.0.1:8502> loads, and a model
**Test** passes in **Models**.
