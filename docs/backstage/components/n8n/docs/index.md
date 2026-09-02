# n8n AI Assistant with a custom OpenAI-compatible gateway

N8n's built-in **AI Assistant** (Instance AI, the "Connect a model" dialog) does not
work out of the box with most self-hosted OpenAI-compatible gateways (vLLM,
LiteLLM, custom FastAPI proxies). It fails with a misleading error, and the
obvious fix (an env var) is silently ignored unless you know an undocumented
precedence rule.

**TL;DR:** The "Connect a model" dialog always stores the model as `openai/<name>`,
which makes n8n hardcode `reasoning_effort: "high"` — most self-hosted models
reject that value. The env var `N8N_INSTANCE_AI_REASONING_EFFORT` only applies to
the `custom/` provider, and you can **only** reach the `custom/` provider by
setting the **full env trio** (`MODEL` + `MODEL_URL` + `MODEL_API_KEY`), which then
overrides the UI configuration entirely.

## Symptoms

The assistant chat fails immediately with:

```text
Instance AI error in instance-ai-stream
AI_NoOutputGeneratedError: No output generated. Check the stream for errors.
    at Object.flush (.../node_modules/ai/dist/index.js:...)
```

The gateway log shows the masked upstream truth:

```json
{ "detail": "Unexpected reasoning effort high. Supported types are xhigh (default), medium, and low." }
```

## How we diagnosed it

The error is thrown by the **Vercel AI SDK** (`ai` package, `streamText` flush),
not by n8n. It is a _wrapper_ error: anything that kills the stream (provider 4xx,
timeout, schema validation failure) surfaces as "No output generated". Always
find the real upstream response first — enable:

```env
N8N_LOG_LEVEL=debug
N8N_LOG_FORMAT=json
```

Then verify the gateway itself with plain `curl` — in our case it passed every
shape n8n sends (chat, streaming SSE, tools, streaming+tools,
`stream_options.include_usage`, `/models`), proving the problem was n8n's request,
not the endpoint:

```sh
# endpoint health sweep — all must return 200
BASEURL="https://gateway.example.com/api/v1"

curl -sS "$BASEURL/chat/completions" \
  -H "Authorization: Bearer $APIKEY" -H "Content-Type: application/json" \
  -d '{"model":"MODEL","messages":[{"role":"user","content":"Ping"}],"max_tokens":200}'

curl -sS -N "$BASEURL/chat/completions" \
  -H "Authorization: Bearer $APIKEY" -H "Content-Type: application/json" \
  -d '{"model":"MODEL","messages":[{"role":"user","content":"Ping"}],"stream":true}'

# the smoking gun — most reasoning models' chat templates reject "high":
curl -sS "$BASEURL/chat/completions" \
  -H "Authorization: Bearer $APIKEY" -H "Content-Type: application/json" \
  -d '{"model":"MODEL","messages":[{"role":"user","content":"Ping"}],"reasoning_effort":"high"}'
```

**Watch for non-standard base paths.** Gateways frequently mount the API under
something like `/api/v1` — check the exact path first. `/v1/chat/completions`
answering `405 Method Not Allowed` while `/api/v1/chat/completions` answers `200`
was the first clue here. n8n appends `/chat/completions` to your Base URL verbatim
(it does **not** add `/v1` for OpenAI-compatible endpoints), so the Base URL must
be the full versioned root.

## Root cause (verified against n8n `master`)

Three facts, each confirmed in source:

1. **The dialog always stores `openai/<name>`.** The "Self-hosted or
   OpenAI-compatible endpoint" option uses the same `openAiApi` credential type as
   OpenAI, and the runtime maps it via
   `CREDENTIAL_TO_MODEL_PROVIDER = { openAiApi: 'openai', ... }`. There is no UI
   path that produces a `custom/` prefix — the prefix is derived from the
   credential type, never from the Base URL.

2. **The `openai` branch hardcodes `reasoning_effort: "high"`.** In
   `packages/@n8n/instance-ai/src/agent/apply-agent-thinking.ts` (master):

   ```ts
   if (provider === "openai") {
     agent.thinking("openai", {
       reasoningEffort: isGpt56Model(modelId) ? "medium" : "high", // hardcoded
     })
     return
   }
   ```

   The custom Base URL is **never consulted** at this point, and the only
   exception is `gpt-5.6*` → `medium`.

3. **`N8N_INSTANCE_AI_REASONING_EFFORT` only applies to `custom/*`.** In
   `custom-model-defaults.ts` it is parsed against the enum
   `none|minimal|low|medium|high|xhigh|max` (invalid values are **silently
   dropped**, e.g. `default` does nothing), and it is only read on the `custom`
   provider branch. With an `openai/` model id it is never consulted.

So: dialog-configured compatible endpoint → `openai/<name>` → forced `high` →
chat-template 400 → stream error → `AI_NoOutputGeneratedError`.

## The fix

### Required env vars (the full trio)

**Setting `N8N_INSTANCE_AI_MODEL` alone is a trap.** `resolveModelConfig()` only
prefers the env-based config when `hasEnvironmentModelConnection()` is true — and
that check looks at `MODEL_URL` / `MODEL_API_KEY`, **not** `MODEL`. With only
`MODEL` set, the UI _shows_ the model as env-managed while the runtime still uses
the DB-stored (dialog) config. Set all three.

```yaml
# Kubernetes / docker env
- name: N8N_INSTANCE_AI_MODEL
  value: custom/qwen3.8-flash-next # custom/ prefix => configurable effort
- name: N8N_INSTANCE_AI_MODEL_URL
  value: https://gateway.example.com/api/v1 # full versioned root
- name: N8N_INSTANCE_AI_MODEL_API_KEY
  value: sk-...
- name: N8N_INSTANCE_AI_REASONING_EFFORT
  value: xhigh # now it actually applies
```

Then **restart the pod** — the model trio is read once at startup via
`GlobalConfig` (the reasoning-effort var is read per call).

Expected behavior after the restart:

- Outgoing requests carry `reasoning_effort: "xhigh"` (accepted by the gateway)
- The admin UI shows the model as _"Found in server configuration"_ and locks the
  dialog fields — correct, not a bug; the old UI config becomes inert
- `PUT /instance-ai/settings` refuses model changes with
  `Cannot update environment-managed fields: modelName` — also correct

### Env var reference (instance-ai, from `configuration.md` + source)

| Variable                                      | Values                                   | Scope           | Notes                                    |
| --------------------------------------------- | ---------------------------------------- | --------------- | ---------------------------------------- |
| `N8N_INSTANCE_AI_MODEL`                       | `custom/<name>` or `provider/<name>`     | all             | bare name => `custom/` prefix            |
| `N8N_INSTANCE_AI_MODEL_URL`                   | full base URL incl. `/v1`                | all             | required to flip env precedence          |
| `N8N_INSTANCE_AI_MODEL_API_KEY`               | key                                      | all             | required to flip env precedence          |
| `N8N_INSTANCE_AI_REASONING_EFFORT`            | `none minimal low medium high xhigh max` | `custom/*` only | invalid values silently ignored          |
| `N8N_INSTANCE_AI_THINKING_ENABLED`            | boolean                                  | all providers   | master switch, kills thinking everywhere |
| `N8N_INSTANCE_AI_SUPPORTS_STRUCTURED_OUTPUTS` | boolean                                  | `custom/*` only |                                          |

**Known-model substring map.** If `N8N_INSTANCE_AI_REASONING_EFFORT` is unset,
n8n applies per-model defaults by **case-insensitive substring match** on the
model id (`kimi-k3` → `low`, `glm-5.2` → `medium`, `deepseek` → structured
outputs). An explicit env value always wins; anything unmatched sends **no**
`reasoning_effort` at all — usually the safest option for gateways, since the
server default then applies.

## Alternatives

**Gateway-side rewrite (no n8n changes).** The rejection typically comes from the
model's chat template (this exact class of issue affects Qwen3-family models on
vLLM/SGLang). Options:

- alias `high` -> `xhigh` in the chat template, or
- vLLM flags `--supported-reasoning-efforts low medium xhigh --reasoning-effort-rounding down`
  (vllm-project/vllm#52739), or
- reverse-proxy rule rewriting `"reasoning_effort":"high"` -> `"xhigh"` in request bodies

**Disable thinking server-side.** For Qwen3-style models, forcing non-thinking
mode makes the model answer directly (`content` streams immediately):

```json
{ "chat_template_kwargs": { "enable_thinking": false } }
```

n8n can't send this — configure it as the gateway/vLLM default
(`--default-chat-template-kwargs`) if the assistant works better without reasoning.

**Plain OpenAI-compatible clients are fine.** Open WebUI and similar don't send
`reasoning_effort`, so the same gateway works there with just the correct base
URL (`.../api/v1`). This failure mode is specific to n8n's Instance AI.

## Related n8n issues

- n8n#33974 — `N8N_INSTANCE_AI_MODEL_URL` ignored for `openai` provider
- n8n#34016 — restores `custom` provider for bare model names
- n8n#37232 — confirms UI config returns only `{id, url, apiKey, headers}`
- n8n#36873 / PR #37156 — "Connect a model" verification on custom Base URLs
- vllm#52738 / #52739 — supported reasoning efforts + rounding

## Checklist

- [ ] `curl` the exact Base URL + `/chat/completions` (expect 200, not 405)
- [ ] `curl` with `"reasoning_effort":"high"` — does the gateway reject it?
- [ ] `N8N_LOG_LEVEL=debug` + `N8N_LOG_FORMAT=json` to surface masked stream errors
- [ ] Set `MODEL` + `MODEL_URL` + `MODEL_API_KEY` together (`custom/` prefix)
- [ ] Set `REASONING_EFFORT` to a value the gateway supports
- [ ] Restart the pod, confirm locked-but-working model in the UI
