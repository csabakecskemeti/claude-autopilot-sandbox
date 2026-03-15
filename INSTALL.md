# Installation Guide

Run Claude Code CLI locally using your own LLM backend (LM Studio, Ollama, vLLM, etc.) in a fully autonomous Docker environment.

## Prerequisites

- **Docker** with compose plugin (Docker Desktop or Docker Engine + docker-compose)
- **LLM Backend** running an OpenAI-compatible API:
  - [LM Studio](https://lmstudio.ai/) (recommended for local)
  - [Ollama](https://ollama.ai/)
  - [vLLM](https://github.com/vllm-project/vllm)
  - Any OpenAI API-compatible server
- **Vision Model** (optional) - A vision-capable model for UI testing and image analysis
- **Whoogle** (optional) - Self-hosted search for web search capability

## Quick Start

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd local-claude-docker
   ```

2. **Copy and configure environment**
   ```bash
   cp .env.example .env
   ```

3. **Edit `.env` with your settings**
   ```bash
   # Edit with your preferred editor
   nano .env
   ```

4. **Start Claude Code**
   ```bash
   ./run.sh
   ```

## Configuration Reference

| Variable | Description | Default |
|----------|-------------|---------|
| `LLM_HOST` | IP/hostname of your LLM backend | `192.168.7.103` |
| `LLM_PORT` | Port of your LLM backend | `11234` |
| `LLM_AUTH_TOKEN` | Auth token for LLM API | `lmstudio` |
| `LLM_MODEL` | Model name to use | `nvidia.nvidia-nemotron-3-super-120b-a12b` |
| `VISION_MODEL` | Vision model for image analysis | `qwen/qwen3-vl-4b` |
| `WHOOGLE_URL` | Full URL to Whoogle instance | (empty = disabled) |
| `MEMORY_LIMIT` | Docker memory limit | `16G` |
| `MEMORY_RESERVATION` | Docker memory reservation | `2G` |
| `WORKSPACE_NAME` | Default workspace name | `default` |

### LM Studio Configuration

See [LM_STUDIO_SETUP.md](LM_STUDIO_SETUP.md) for detailed setup instructions.

**Quick start:**
```bash
# Install and start LM Studio
curl -fsSL https://lmstudio.ai/install.sh | bash
lms server start -p 11234 --bind 0.0.0.0

# Load model with large context (important!)
lms load <model-name> --gpu max -c 131072 -y
```

Set in `.env`:
```env
LLM_HOST=<your-lm-studio-ip>    # e.g., 192.168.1.100 or localhost
LLM_PORT=11234
LLM_AUTH_TOKEN=lmstudio
LLM_MODEL=your-model-name
```

### Ollama Configuration

1. Start Ollama: `ollama serve`
2. Pull a model: `ollama pull llama3.3:70b`
3. Set in `.env`:
   ```env
   LLM_HOST=127.0.0.1
   LLM_PORT=11434
   LLM_AUTH_TOKEN=ollama
   LLM_MODEL=llama3.3:70b
   ```

### Whoogle Setup (Optional)

Whoogle provides self-hosted web search capability.

1. Run Whoogle:
   ```bash
   docker run -d -p 5000:5000 benbusby/whoogle-search
   ```

2. Set in `.env`:
   ```env
   WHOOGLE_URL=http://localhost:5000
   ```

### Vision Model Setup (Optional)

The vision model enables Claude to see and analyze images, take screenshots of web apps, and verify UIs.

1. Load a vision-capable model in your LLM backend:
   - LM Studio: Load a VL (Vision-Language) model like `qwen/qwen3-vl-4b`
   - Ollama: `ollama pull llava:7b`

2. Set in `.env`:
   ```env
   VISION_MODEL=qwen/qwen3-vl-4b
   ```

The vision model uses the same host/port as your main LLM. Claude will use this for:
- UI testing (screenshot and verify web apps look correct)
- Image analysis (describe image contents)
- OCR (extract text from images)

## Building the Image

The image is built automatically on first run, but you can pre-build:

```bash
docker compose build
```

To rebuild after changes:

```bash
docker compose build --no-cache
```

## Troubleshooting

### "Cannot connect to LLM"

- Verify your LLM server is running
- Check `LLM_HOST` and `LLM_PORT` in `.env`
- If Docker uses host network, ensure the LLM is accessible from the host
- Test with: `curl http://<LLM_HOST>:<LLM_PORT>/v1/models`

### "Model not found"

- Verify `LLM_MODEL` matches exactly what your backend expects
- For LM Studio: use the model identifier shown in the UI
- For Ollama: use `ollama list` to see available models

### "Permission denied" on run.sh

```bash
chmod +x run.sh
```

### Container exits immediately

- Check Docker logs: `docker compose logs`
- Ensure the LLM backend is accessible
- Verify model name is correct

### Whoogle search not working

- Verify Whoogle is running: `curl http://<WHOOGLE_URL>/search?q=test`
- Check `WHOOGLE_URL` includes the full URL with protocol
- Leave `WHOOGLE_URL` empty if you don't have Whoogle

### Out of memory

- Increase `MEMORY_LIMIT` in `.env`
- Use a smaller model in your LLM backend
- Close other memory-intensive applications

## Directory Structure

After setup, your directory should look like:

```
local-claude-docker/
├── .env                   # Your configuration (gitignored)
├── .env.example           # Template configuration
├── .gitignore
├── docker-compose.yml
├── Dockerfile
├── run.sh
├── watchdog.sh
├── skills-backup/         # Claude skills
├── agents-backup/         # Claude subagents
├── CLAUDE.md              # Template for new workspaces
└── workspaces/            # Created automatically by run.sh (gitignored)
    └── default/           # Default workspace
```
