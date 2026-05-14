---
status: accepted
date: 2026-05-15
decision-makers: [tyriis]
---

# Local LLM Agentic Coding with Tool Calls is not feasible on 8 GB VRAM

## Context and Problem Statement

The desktop workstation (NVIDIA RTX 2060 Super, 8 GB VRAM, 64 GB system RAM)
was evaluated as a platform for running local LLMs with agentic coding tools
(OpenCode CLI). The goal was to perform tasks such as dependency review
(`review-renovate`) with tool-calling capabilities entirely offline, without
relying on cloud APIs.

Multiple model sizes and quantization levels were tested to determine whether
reliable, responsive tool calling is achievable on this hardware.

## Decision Drivers

- Tool calling (function calling) must be reliable — hallucinated tool names
  and malformed JSON schemas break agentic workflows
- Response time must be interactive — waiting multiple minutes per step is not
  acceptable for iterative coding tasks
- VRAM capacity of 8 GB is the hard upper bound; GPU memory cannot be expanded
- The OpenCode CLI sends large system prompts with complex tool definitions
  that models must process accurately

## Considered Options

- **Option 1: Qwen3.5-9B (Q4_K_M, ~6,5 GB VRAM)** — 32 of 33 layers in GPU,
  output layer on CPU. Responses were too slow for interactive use; tool calls
  hallucinated (e.g. `run_shell_command`) and bash schema validation failed
  repeatedly (missing `description` field).

- **Option 2: Qwen3-Coder-30B-A3B (Q4_K_M, MoE, 19 GB)** — only 18 of 49
  layers fit in GPU; remaining layers and output layer on CPU. Inference was
  dominated by CPU fallback (~8–15 t/s estimated). After several minutes no
  response was delivered.

- **Option 3: Llama 3.2 3B (Q4_K_M, ~2 GB VRAM)** — fully fits in VRAM and
  is fast, but the model is too small to reliably process OpenCode's tool
  schemas. Tool calls are frequently incorrect.

- **Option 4: Hybrid approach** — use local models for simple chat and code
  questions, and cloud providers (Hermes Agent, OpenCode Zen) for agentic
  workflows requiring tool calls.

- **Option 5: Hardware upgrade** — acquire a GPU with 16+ GB VRAM (e.g. RTX
  4090, 5090) to run 24–30B models fully in GPU memory.

## Decision Outcome

Chosen option: **Hybrid approach (Option 4)** — local models are used for
ad-hoc code questions and explanation; agentic workflows with tool calling
(review-renovate, multi-file refactoring, supply chain verification) are
delegated to cloud-based providers.

Testing has shown that 8 GB VRAM is a hard barrier for agentic coding with
OpenCode. The output layer cannot be fully offloaded, making every generated
token pay a CPU round-trip penalty, and the model lacks the capacity to
correctly parse and act on the large tool-definition schemas that agentic
frameworks require.

### Consequences

- Good, because agentic tasks complete reliably and fast via cloud providers
- Good, because local models remain available for quick, offline questions
- Good, because no hardware investment is required
- Bad, because agentic tasks depend on network connectivity and cloud APIs
- Bad, because code never leaves the local machine only for non-agentic use
- Bad, because the full potential of offline-first development is not achieved
  with the current GPU

## More Information

Models tested on RTX 2060 Super (8 GB VRAM, 64 GB RAM, Ollama 0.23.4):

| Model                        | VRAM used | GPU layers | Output layer | Result                              |
| ---------------------------- | --------- | ---------- | ------------ | ----------------------------------- |
| Qwen3.5-9B (Q4_K_M)          | ~6,2 GB   | 32/33      | CPU          | Too slow, tool calls unreliable     |
| Qwen3-Coder-30B-A3B (Q4_K_M) | ~7,0 GB   | 18/49      | CPU          | No response after several minutes   |
| Llama 3.2 3B (Q4_K_M)        | ~2 GB     | All        | GPU          | Fast but too small for tool schemas |

Flash attention was enabled automatically (CUDA 7.5+). The correct OpenCode
config property for tool calling is `tool_call: true` (not `tools: true`, which
the official OpenCode schema rejects).
