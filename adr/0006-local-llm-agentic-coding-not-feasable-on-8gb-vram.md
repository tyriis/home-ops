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

This decision must also consider the risks of relying on cloud-based LLM
subscriptions as the alternative.

## Decision Drivers

- Tool calling (function calling) must be reliable - hallucinated tool names
  and malformed JSON schemas break agentic workflows
- Response time must be interactive - waiting multiple minutes per step is not
  acceptable for iterative coding tasks
- VRAM capacity of 8 GB is the hard upper bound; GPU memory cannot be expanded
- The OpenCode CLI sends large system prompts with complex tool definitions
  that models must process accurately
- Cloud LLM costs are rising and subscriptions are being restricted
- Data privacy requires trust in cloud providers' data handling policies

## Considered Options

- **Option 1: Qwen3.5-9B (Q4_K_M, ~6,5 GB VRAM)** - 32 of 33 layers in GPU,
  output layer on CPU. Responses were too slow for interactive use; tool calls
  hallucinated (e.g. `run_shell_command`) and bash schema validation failed
  repeatedly (missing `description` field).

- **Option 2: Qwen3-Coder-30B-A3B (Q4_K_M, MoE, 19 GB)** - only 18 of 49
  layers fit in GPU; remaining layers and output layer on CPU. Inference was
  dominated by CPU fallback (~8-15 t/s estimated). After several minutes no
  response was delivered.

- **Option 3: Llama 3.2 3B (Q4_K_M, ~2 GB VRAM)** - fully fits in VRAM and
  is fast, but the model is too small to reliably process OpenCode's tool
  schemas. Tool calls are frequently incorrect.

- **Option 4: Hybrid approach** - use local models for simple chat and code
  questions, and cloud providers (Hermes Agent, OpenCode Zen) for agentic
  workflows requiring tool calls.

- **Option 5: Hardware upgrade** - acquire a GPU with 16+ GB VRAM (e.g. RTX
  4090, 5090) to run 24-30B models fully in GPU memory.

## Decision Outcome

Chosen option: **Hybrid approach (Option 4)** - local models are used for
ad-hoc code questions and explanation; agentic workflows with tool calling
(review-renovate, multi-file refactoring, supply chain verification) are
delegated to cloud-based providers.

Testing has shown that 8 GB VRAM is a hard barrier for agentic coding with
OpenCode. The output layer cannot be fully offloaded, making every generated
token pay a CPU round-trip penalty, and the model lacks the capacity to
correctly parse and act on the large tool-definition schemas that agentic
frameworks require.

This hybrid approach carries acknowledged risks from the cloud LLM market
trends (see below).

### Consequences

- Good, because agentic tasks complete reliably and fast via cloud providers
- Good, because local models remain available for quick, offline questions
- Good, because no hardware investment is required
- Bad, because agentic tasks depend on network connectivity and cloud APIs
- Bad, because LLM subscriptions are becoming more expensive and restrictive
- Bad, because cloud providers can use submitted data for model training
  unless explicitly opted out (or on business/API plans)
- Bad, because the full potential of offline-first development is not achieved
  with the current GPU

## Risks of Cloud LLM Dependency

Reliance on cloud-based LLM providers for agentic tasks introduces three
categories of risk that should be monitored over time.

### 1. Rising Costs

The assumption that AI model pricing reliably decreases is breaking down:

- OpenAI GPT-5 launched at $1.25/M tokens (Aug 2025). GPT-5.5 launched at
  $5/M tokens - a **4x increase** in under a year.
  ([Source: Moov AI](https://www.linkedin.com/pulse/llm-progress-slowing-getting-more-expensive-moov-ai-ac1te))

- Claude Code is reported to average **$150-$250/developer/month** before
  subagent fan-out, which has produced four-figure bills in single sessions.
  ([Source: Moov AI](https://www.linkedin.com/pulse/llm-progress-slowing-getting-more-expensive-moov-ai-ac1te))

- GitHub Copilot transitioned to **usage-based billing** (June 2026). Model
  multipliers increased sharply: Sonnet 4.5 went from 1x to 6x, Opus 4.6 from
  3x to **27x**.
  ([Source: GitHub Blog](https://github.blog/news-insights/company-news/github-copilot-is-moving-to-usage-based-billing/))

- Platform economics are under pressure: OpenAI reportedly loses ~$12
  billion/quarter while signing ~$1.4 trillion in compute commitments over 8
  years.

### 2. Subscription Restrictions

Providers are actively restricting how subscriptions can be used:

- **April 2026**: Anthropic prohibited Claude Pro and Max subscribers from
  using their plan limits to power third-party agent frameworks (OpenClaw,
  etc.). Users must switch to pay-as-you-go API bundles.
  ([Source: PYMNTS](https://www.pymnts.com/artificial-intelligence-2/2026/third-party-agents-lose-access-as-anthropic-tightens-claude-usage-rules/))

- Anthropic stated subscriptions were "never designed for the kind of
  continuous, automated demand these tools generate."

- Google Gemini Advanced caps at **100 prompts/day** (Free: 5/day).
  ([Source: PYMNTS](https://www.pymnts.com/artificial-intelligence-2/2026/third-party-agents-lose-access-as-anthropic-tightens-claude-usage-rules/))

- This pattern is expected to spread across the industry as agentic workloads
  increase infrastructure pressure.

### 3. Data Privacy & Training Risk

Cloud providers can use submitted code and conversations for model training
unless explicitly prevented:

- **Anthropic (Claude)**: Free, Pro, and Max plans default to training on user
  data. Data can be retained for up to **5 years** when training is enabled.
  Opt-out is manual in Privacy Settings. Only Team/Enterprise and API plans
  exclude data from training by default.
  ([Source: Anthropic](https://www.anthropic.com/news/updates-to-our-consumer-terms))

- **OpenAI (ChatGPT)**: Free and Plus default to training. Must manually opt
  out in Settings > Data Controls. Team/Enterprise plans are safe.
  ([Source: drainpipe.io](https://drainpipe.io/ai-data-privacy-2026-the-ai-privacy-trap/))

- **Google (Gemini)**: Free and Advanced default to training with frequent
  human review. Opting out forces loss of chat history.
  ([Source: drainpipe.io](https://drainpipe.io/ai-data-privacy-2026-the-ai-privacy-trap/))

- **API access** (all major providers) is generally safer: data is not used
  for training and retention is limited to ~30 days. However, this is more
  expensive than flat-rate subscriptions.

The risk is that proprietary code or infrastructure configurations submitted
to cloud models could influence future model outputs, or be exposed through
memorization. Even with opt-out, one must trust the provider's data handling.

## More Information

### Test results

Models tested on RTX 2060 Super (8 GB VRAM, 64 GB RAM, Ollama 0.23.4):

| Model                        | VRAM used | GPU layers | Output layer | Result                              |
| ---------------------------- | --------- | ---------- | ------------ | ----------------------------------- |
| Qwen3.5-9B (Q4_K_M)          | ~6,2 GB   | 32/33      | CPU          | Too slow, tool calls unreliable     |
| Qwen3-Coder-30B-A3B (Q4_K_M) | ~7,0 GB   | 18/49      | CPU          | No response after several minutes   |
| Llama 3.2 3B (Q4_K_M)        | ~2 GB     | All        | GPU          | Fast but too small for tool schemas |

Flash attention was enabled automatically (CUDA 7.5+). The correct OpenCode
config property for tool calling is `tool_call: true` (not `tools: true`, which
the official OpenCode schema rejects).

### Sources

1. ["LLM progress is slowing and getting more expensive" - Moov AI](https://www.linkedin.com/pulse/llm-progress-slowing-getting-more-expensive-moov-ai-ac1te)
2. ["Third-party agents lose access as Anthropic tightens Claude usage rules" - PYMNTS, April 2026](https://www.pymnts.com/artificial-intelligence-2/2026/third-party-agents-lose-access-as-anthropic-tightens-claude-usage-rules/)
3. ["GitHub Copilot is moving to usage-based billing" - GitHub Blog](https://github.blog/news-insights/company-news/github-copilot-is-moving-to-usage-based-billing/)
4. ["Updates to Consumer Terms and Privacy Policy" - Anthropic, August 2025](https://www.anthropic.com/news/updates-to-our-consumer-terms)
5. ["AI Data Privacy 2026: The AI Privacy Trap" - drainpipe.io](https://drainpipe.io/ai-data-privacy-2026-the-ai-privacy-trap/)
6. ["Privacy Risks in LLMs: Governance Frameworks for Enterprise AI" - Secure Privacy](https://secureprivacy.ai/blog/privacy-risks-llms-enterprise-ai-governance)
