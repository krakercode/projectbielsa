// Model-agnostic provider layer for the manager.
//
// Implements the adapter contract from docs/control-interface.md: one
// `decide()` entry point per decision event, portable JSON-Schema tool
// definitions, and a common DecisionResult shape regardless of which model ran.
//
// DEVIATION FROM PLAN.md, stated rather than silently substituted:
// PLAN.md specifies Python for the controller. This is Node. Reason: Node 24 is
// installed and working on this machine, Python is not (only the Windows Store
// stub), and the repo already uses Node for cheat-table/parse_ct.js and
// generate_dump_lua.js. Nothing in the design depends on the language -- the
// portable part is the tool schemas, which are plain JSON Schema either way.
//
// DEVIATION FROM docs/control-interface.md, likewise stated:
// The doc specifies an agentic tool-use loop for every model. That is right for
// Claude-class models and is implemented here. It is NOT reliable on an 8B local
// model -- small models frequently emit malformed tool calls or loop. So the
// provider supports two strategies and records which one ran:
//
//   "tools"     - true agentic loop (read tools, then act). Claude-class.
//   "oneshot"   - state supplied up front, single structured JSON reply.
//
// oneshot is a fallback, not the design. Any result carries `strategy` so an
// analysis can never silently compare a tool-loop run against a one-shot run and
// treat them as equivalent.

const http = require('node:http');

const DEFAULT_OLLAMA = 'http://127.0.0.1:11434';

// Node's global fetch (undici) enforces a 300s headersTimeout that cannot be
// changed without pulling in undici as a dependency. A cold 8B on an RTX 2080
// can exceed that on the first call -- model load plus a long thinking trace --
// and it surfaces uselessly as "fetch failed". Use node:http directly so
// timeouts are ours to set and stay dependency-free.
function postJson(url, payload, timeoutMs) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const data = Buffer.from(JSON.stringify(payload));
    const req = http.request(
      {
        hostname: u.hostname,
        port: u.port || 80,
        path: u.pathname,
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Content-Length': data.length },
      },
      (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => {
          const body = Buffer.concat(chunks).toString('utf8');
          if (res.statusCode < 200 || res.statusCode >= 300) {
            reject(new Error(`HTTP ${res.statusCode}: ${body.slice(0, 400)}`));
            return;
          }
          try {
            resolve(JSON.parse(body));
          } catch (e) {
            reject(new Error(`bad JSON from ollama: ${body.slice(0, 200)}`));
          }
        });
      }
    );
    req.setTimeout(timeoutMs, () => req.destroy(new Error(`timed out after ${timeoutMs}ms`)));
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

function getJson(url, timeoutMs) {
  return new Promise((resolve, reject) => {
    const req = http.get(url, (res) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => {
        try {
          resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')));
        } catch (e) {
          reject(e);
        }
      });
    });
    req.setTimeout(timeoutMs, () => req.destroy(new Error('timed out')));
    req.on('error', reject);
  });
}

/**
 * @typedef {Object} DecisionResult
 * @property {string} eventType
 * @property {string} model
 * @property {string} strategy      "tools" | "oneshot"
 * @property {Array}  toolCalls     tool calls the model made, in order
 * @property {Object|null} decision parsed final decision, if the event expects one
 * @property {string} reasoning     whatever reasoning the model surfaced
 * @property {Object} tokens        {input, output} where the provider reports them
 * @property {number} wallClockMs
 * @property {string|null} error    non-null if the run failed
 */

function nowMs() {
  return Number(process.hrtime.bigint() / 1000000n);
}

/** Pull the first JSON object out of a model reply that may be wrapped in prose or fences. */
function extractJson(text) {
  if (!text) return null;
  // strip ```json fences if present
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  const candidate = fenced ? fenced[1] : text;
  // find the outermost {...}
  const start = candidate.indexOf('{');
  const end = candidate.lastIndexOf('}');
  if (start === -1 || end === -1 || end <= start) return null;
  try {
    return JSON.parse(candidate.slice(start, end + 1));
  } catch {
    return null;
  }
}

/**
 * Qwen3 emits chain-of-thought inside <think>...</think>. That's reasoning, not
 * output -- strip it before parsing, but keep it for the decision log.
 */
function splitThinking(text) {
  if (!text) return { thinking: '', body: '' };
  const m = text.match(/<think>([\s\S]*?)<\/think>/);
  if (!m) return { thinking: '', body: text };
  return { thinking: m[1].trim(), body: text.replace(m[0], '').trim() };
}

class OllamaProvider {
  /**
   * @param {Object} opts
   * @param {string} [opts.model]    e.g. "qwen3:8b"
   * @param {string} [opts.baseUrl]  Ollama host
   * @param {number} [opts.numCtx]   context window; see note in MANAGER.md about
   *                                 8GB VRAM -- large values spill the KV cache.
   */
  /**
   * @param {boolean} [opts.think]  Qwen3 reasons inside <think>...</think> by
   *   default, which on an 8B costs thousands of tokens and minutes of wall
   *   clock before any answer appears. Off by default here. Turn it on
   *   deliberately when comparing reasoning quality -- and record it, because a
   *   thinking run and a non-thinking run are not the same condition.
   */
  constructor({
    model = 'qwen3:8b',
    baseUrl = DEFAULT_OLLAMA,
    numCtx = 8192,
    temperature = 0.4,
    think = false,
    timeoutMs = 900000,
  } = {}) {
    this.model = model;
    this.baseUrl = baseUrl;
    this.numCtx = numCtx;
    this.temperature = temperature;
    this.think = think;
    this.timeoutMs = timeoutMs;
  }

  get name() {
    return `ollama:${this.model}${this.think ? '+think' : ''}`;
  }

  async health() {
    return getJson(`${this.baseUrl}/api/version`, 10000);
  }

  /** Load the model into VRAM so the first real call isn't paying for it. */
  async warm() {
    return postJson(
      `${this.baseUrl}/api/chat`,
      {
        model: this.model,
        messages: [{ role: 'user', content: 'ok' }],
        stream: false,
        think: this.think,
        options: { num_ctx: this.numCtx, num_predict: 1 },
        keep_alive: '10m',
      },
      this.timeoutMs
    );
  }

  async chat(messages, { tools } = {}) {
    const body = {
      model: this.model,
      messages,
      stream: false,
      think: this.think,
      keep_alive: '10m',
      options: { num_ctx: this.numCtx, temperature: this.temperature },
    };
    if (tools && tools.length) body.tools = tools;
    return postJson(`${this.baseUrl}/api/chat`, body, this.timeoutMs);
  }

  /**
   * One decision event. See DecisionResult.
   * @param {Object} req
   * @param {string} req.eventType
   * @param {string} req.systemPrompt
   * @param {string} req.initialContext
   * @param {Array}  [req.tools]      JSON-Schema tool defs (portable)
   * @param {Object} [req.toolImpls]  name -> async fn(args) for the agentic loop
   * @param {string} [req.strategy]   "tools" | "oneshot"
   * @param {number} [req.maxTurns]
   */
  async decide({ eventType, systemPrompt, initialContext, tools = [], toolImpls = {}, strategy = 'oneshot', maxTurns = 8 }) {
    const started = nowMs();
    const result = {
      eventType,
      model: this.name,
      strategy,
      toolCalls: [],
      decision: null,
      reasoning: '',
      tokens: { input: 0, output: 0 },
      wallClockMs: 0,
      error: null,
    };

    const messages = [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: initialContext },
    ];

    try {
      if (strategy === 'tools') {
        for (let turn = 0; turn < maxTurns; turn++) {
          const res = await this.chat(messages, { tools });
          result.tokens.input += res.prompt_eval_count || 0;
          result.tokens.output += res.eval_count || 0;
          const msg = res.message || {};
          messages.push(msg);

          const calls = msg.tool_calls || [];
          if (!calls.length) {
            const { thinking, body } = splitThinking(msg.content || '');
            result.reasoning = thinking || body;
            result.decision = extractJson(body);
            break;
          }
          for (const call of calls) {
            const fnName = call.function?.name;
            const args = call.function?.arguments || {};
            let toolOut;
            try {
              const impl = toolImpls[fnName];
              // Mirrors the design doc: unknown/invalid tool use returns an error
              // to the model so it can self-correct, rather than crashing.
              toolOut = impl ? await impl(args) : { is_error: true, content: `unknown tool: ${fnName}` };
            } catch (e) {
              toolOut = { is_error: true, content: String(e.message || e) };
            }
            result.toolCalls.push({ tool: fnName, args, result: toolOut });
            messages.push({ role: 'tool', content: JSON.stringify(toolOut) });
          }
        }
      } else {
        const res = await this.chat(messages);
        result.tokens.input = res.prompt_eval_count || 0;
        result.tokens.output = res.eval_count || 0;
        const { thinking, body } = splitThinking(res.message?.content || '');
        result.reasoning = thinking;
        result.decision = extractJson(body);
        if (!result.decision) result.error = 'no parsable JSON in model reply';
        result.rawReply = body;
      }
    } catch (e) {
      result.error = String(e.message || e);
    }

    result.wallClockMs = nowMs() - started;
    return result;
  }
}

/**
 * Placeholder for the Claude adapter. Deliberately not implemented here: the
 * design doc specifies client.beta.messages.tool_runner, which needs the
 * Anthropic SDK and an API key, and neither is set up yet. Keeping the shape
 * visible so the interface stays honest about what exists.
 */
class ClaudeProvider {
  constructor() {
    throw new Error('ClaudeProvider not implemented yet -- see docs/control-interface.md');
  }
}

module.exports = { OllamaProvider, ClaudeProvider, extractJson, splitThinking };
