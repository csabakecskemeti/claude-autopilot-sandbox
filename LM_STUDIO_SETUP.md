# Setting Up Claude Code with a Local LLM

## Overview
This guide shows how to run **Claude Code** (the CLI) with a large language model served locally by **LM Studio Server**.

This setup gives you a fully self-contained AI development environment without relying on external APIs.

**Note**: This guide applies to any hardware capable of running LM Studio—a gaming PC with a decent GPU, a workstation, or a server.

---

## Prerequisites

| Item | Description |
|------|-------------|
| **GPU-capable machine** | Any machine with a CUDA-compatible GPU (e.g., RTX 3090, RTX 4090, A100, etc.) |
| **CUDA / cuDNN** | Properly configured for your GPU |
| **Network access** | Claude Code must be able to reach the LM Studio server |
| **Disk space** | Varies by model—large models (70B+) can occupy 40-80 GB |
| **Docker** | For running the Claude Autopilot Sandbox |

---

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

## 3. Choose and Load a Model

**Important**: You need to **manually load the model with a large context size**. Claude Code requires substantial context.

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

**Loading with parallel request support** (for multiple concurrent sessions):

```bash
lms load nvidia/nvidia-nemotron-3-super-49b-v1 --gpu max -c 131072 -y --parallel 5
```

---

## 4. Configure the Sandbox

Edit your `.env` file:

```env
LLM_HOST=<your-lm-studio-ip>    # e.g., 192.168.1.100
LLM_PORT=11234
LLM_AUTH_TOKEN=lmstudio
LLM_MODEL=nvidia/nvidia-nemotron-3-super-49b-v1
```

---

## 5. Build and Run

```bash
./build.sh
./run.sh myproject "Build a todo app"
```

---

## 6. Vision Model Setup (Optional)

For UI verification and image analysis, load a vision-capable model:

```bash
# In LM Studio, also load a vision model
lms load qwen/qwen3-vl-4b --gpu max -y
```

Configure in `.env`:

```env
VISION_MODEL=qwen/qwen3-vl-4b
```

---

## Troubleshooting

| Issue | Suggested Fix |
|-------|---------------|
| **Model fails to load** | Ensure enough free GPU memory (`nvidia-smi`). Try a smaller quantization. |
| **Connection refused** | Verify the LM Studio server is running and listening on the configured port. Check firewall rules. |
| **Out-of-memory during generation** | Reduce context length (`-c`) or use `--gpu 0.8` to offload part of the model to CPU. |
| **Slow responses** | Increase `--parallel` for higher throughput, but monitor GPU utilization. |
| **Truncated or failing responses** | Manually load the model with larger context (e.g., `-c 131072`). |

---

## Summary

1. **Install LM Studio** on your GPU machine
2. **Start the server**: `lms server start --port 11234 --bind 0.0.0.0`
3. **Manually load a model** with large context: `lms load <model> --gpu max -c 131072 -y`
4. **Configure `.env`** with LLM_HOST, LLM_PORT, LLM_MODEL
5. **Build and run** the sandbox: `./build.sh && ./run.sh myproject`

---

## References

- [LM Studio + Claude Code Blog Post](https://lmstudio.ai/blog/claudecode)
- [LM Studio Download](https://lmstudio.ai/download)
- [Claude Code Documentation](https://docs.anthropic.com/claude-code)
