# Setting Up Claude Code with a Local LLM and Local Web Search

## Overview
This guide shows how to run **Claude Code** (the CLI) with:
1. A large language model served locally by **LM Studio Server**
2. A self-hosted **Whoogle** web search service running in Docker
3. A custom **Claude Code skill** that integrates local web search

This setup gives you a fully self-contained AI development environment without relying on external APIs.

**Note**: This guide applies to any hardware capable of running LM Studio—a gaming PC with a decent GPU, a workstation, or a server. You can adapt the instructions to your own setup and choose a model size that fits your hardware.

---

## Prerequisites

| Item | Description |
|------|-------------|
| **GPU-capable machine** | Any machine with a CUDA-compatible GPU (e.g., RTX 3090, RTX 4090, A100, etc.) |
| **CUDA / cuDNN** | Properly configured for your GPU |
| **Network access** | Claude Code must be able to reach the LM Studio server and Whoogle instance |
| **Disk space** | Varies by model—large models (70B+) can occupy 40-80 GB |
| **Docker** | For hosting Whoogle (can run on any machine with Docker installed) |

---

# Part 1: Local LLM with LM Studio

This setup follows the official LM Studio blog post: <https://lmstudio.ai/blog/claudecode>

## 1. Install LM Studio Server

Install LM Studio on your GPU machine. You can install via the official script (headless) or download the GUI app.

```bash
# Headless installation (recommended for servers)
curl -fsSL https://lmstudio.ai/install.sh | bash
```

After the script finishes, the `lms` CLI will be available in your `$PATH`. Verify:

```bash
lms --version
```

If you prefer the desktop app, download it from <https://lmstudio.ai/download> and run the installer.

---

## 2. Start the LM Studio Server

```bash
# Launch the server on the default port (11234)
lms server start -p 11234 --bind 0.0.0.0
```

The server exposes an OpenAI-compatible `/v1/messages` endpoint.

---

## 3. Set Environment Variables for Claude Code

Claude Code reads `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN` to connect to a custom backend.

**If LM Studio runs on the same machine as Claude Code:**

```bash
export ANTHROPIC_BASE_URL="http://localhost:11234"
export ANTHROPIC_AUTH_TOKEN=lmstudio
```

**If LM Studio runs on a remote machine** (e.g., at `<lm-studio-host-ip>`):

```bash
export ANTHROPIC_BASE_URL="http://<lm-studio-host-ip>:11234"
export ANTHROPIC_AUTH_TOKEN=lmstudio
```

You can add these lines to `~/.bashrc` or your shell profile for persistence.

---

## 4. Choose and Load a Model in LM Studio

**Important**: The LM Studio blog mentions that the server auto-loads models, but in practice you may need to **manually load the model with a large context size**. Claude Code requires substantial context.

List available models:

```bash
lms ls
```

If the desired model is not present, download it:

```bash
lms get "nvidia/nvidia-nemotron-3-super-49b-v1" -y
```

**Manually load the model** with a large context window and full GPU offload:

```bash
lms load nvidia/nvidia-nemotron-3-super-49b-v1 --gpu max -c 131072 -y
```

- `--gpu max` — full GPU offload
- `-c 131072` — 128k token context
- `-y` — auto-approve prompts

This step is critical—without explicitly loading the model with sufficient context, Claude Code may fail or produce truncated responses.

**Loading with parallel request support**:

For higher throughput (e.g., multiple concurrent Claude Code sessions), use the `--parallel` flag:

```bash
lms load nvidia/nvidia-nemotron-3-super-49b-v1 --gpu max -c 131072 -y --parallel 5
```

- `--parallel 5` — allows up to 5 concurrent requests

Increase `--parallel` based on your GPU memory. Monitor utilization with `watch nvidia-smi`.

---

## 5. Run Claude Code Against the LM Studio Backend

With the environment variables set, invoke Claude Code:

```bash
claude --model nvidia/nvidia-nemotron-3-super-49b-v1
```

Claude Code will send requests to your configured `ANTHROPIC_BASE_URL` and use the loaded model.

---

## 6. Using Extended Context

Because we started LM Studio with `-c 131072`, the model can consider up to **128k tokens** of prior conversation or code. For smaller models or limited GPU memory, reduce the `-c` value accordingly.

---

# Part 2: Local Web Search with Whoogle

Since a local LLM does not have access to Anthropic's built-in web search, we deploy a self-hosted Whoogle instance and create a Claude Code skill to use it.

## 7. Deploy Whoogle with Docker

You can run Whoogle on any machine with Docker installed—your local machine, a NAS, a home server, or a cloud VM.

```bash
docker run -d \
    --name whoogle \
    -p 5000:5000 \
    -e WHOOGLE_RESULTS_PER_PAGE=10 \
    benbusby/whoogle-search
```

**Port binding explained**:
- `-p 5000:5000` maps **host port 5000** to **container port 5000** (Whoogle's internal port)
- You can change the host port to any available port

The service exposes `GET /search?q=<query>&format=json`.

**Verify it works**:

```bash
# If running locally
curl "http://localhost:5000/search?q=Claude+Code&format=json"

# If running on another machine
curl "http://<whoogle-host-ip>:5000/search?q=Claude+Code&format=json"
```

You should receive a JSON payload with search results.

---

# Part 3: Using with Claude Autopilot Sandbox

If you're using the **claude-autopilot-sandbox** Docker setup, the web search skill is already included.

1. Configure your `.env` file:
   ```env
   LLM_HOST=<your-lm-studio-ip>
   LLM_PORT=11234
   LLM_MODEL=nvidia/nvidia-nemotron-3-super-49b-v1
   WHOOGLE_URL=http://<your-whoogle-ip>:5000
   ```

2. Build and run:
   ```bash
   docker compose build
   ./run.sh myproject
   ```

3. Use `/websearch` inside Claude to search the web.

---

# Maintenance & Troubleshooting

## LM Studio Issues

| Issue | Suggested Fix |
|-------|---------------|
| **Model fails to load** | Ensure enough free GPU memory (`nvidia-smi`). Try a smaller quantization. |
| **Connection refused** | Verify the LM Studio server is running and listening on the configured port. Check firewall rules. |
| **Out-of-memory during generation** | Reduce context length (`-c`) or use `--gpu 0.8` to offload part of the model to CPU. |
| **Slow responses** | Increase `--parallel` for higher throughput, but monitor GPU utilization. |
| **Truncated or failing responses** | Manually load the model with larger context (e.g., `-c 131072`). |

## Whoogle Issues

| Issue | Suggested Fix |
|-------|---------------|
| **Search returns empty** | Check that Whoogle container is running: `docker ps`. Restart if needed. |
| **Network timeout** | Ensure the machine running Claude Code can reach Whoogle. Check firewall rules. |
| **Rate limiting** | Whoogle may get rate-limited by Google. Wait and retry, or configure proxies. |
| **Container not starting** | Check if port is already in use: `lsof -i :5000`. Use a different port if needed. |

---

# Summary

1. **Install LM Studio** on your GPU machine (`curl … | bash`)
2. **Start the server**: `lms server start --port 11234 --bind 0.0.0.0`
3. **Set environment variables**: `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN=lmstudio`
4. **Manually load a model** with large context (e.g., `lms load <model> --gpu max -c 131072 -y`)
5. **Deploy Whoogle** with Docker on any machine
6. **Run Claude Code** or use **claude-autopilot-sandbox** for autonomous operation

You now have a self-contained AI development environment: **Claude Code** for prompting, **LM Studio Server** delivering a local LLM, and a local **Whoogle-based web search**—all running on your own infrastructure.

---

## References

- [LM Studio + Claude Code Blog Post](https://lmstudio.ai/blog/claudecode)
- [LM Studio Download](https://lmstudio.ai/download)
- [Whoogle Search on Docker Hub](https://hub.docker.com/r/benbusby/whoogle-search)
- [Claude Code Documentation](https://docs.anthropic.com/claude-code)
