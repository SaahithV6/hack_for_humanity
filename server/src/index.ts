import express from "express";
import Anthropic from "@anthropic-ai/sdk";
import { z } from "zod";
import { zodOutputFormat } from "@anthropic-ai/sdk/helpers/zod";

/**
 * Moth's optional enrichment proxy.
 *
 * It exists for exactly one reason: an iOS app cannot hold an API key, because
 * anyone can pull it straight out of the bundle. So the key lives here.
 *
 * Everything about this service is written on the assumption that it is the
 * least trusted part of the system. The app works completely without it, never
 * waits on it, and re-validates everything it returns against the on-device
 * harness in `Sources/MothEngine/Enrichment.swift` before a single word reaches
 * a user. If this server disappeared mid-demo, nobody watching would know.
 */

const app = express();
app.use(express.json({ limit: "16kb" }));

/**
 * Which model writes the prose.
 *
 * Deliberately swappable. The harness on the device is what makes the output
 * safe, not the choice of model -- so this can follow whichever key we can
 * actually get hold of, and a weaker-but-faster model is a perfectly
 * reasonable trade when everything it says is checked anyway.
 *
 * Selected by whichever key is present; PROVIDER overrides.
 */
type Provider = "anthropic" | "gemini" | "cerebras";

/**
 * Everything except Anthropic speaks the OpenAI chat-completions shape, so
 * they share one code path and differ only in these three fields.
 *
 * `maxTokensField` exists because the two endpoints disagree about the name:
 * Cerebras wants `max_completion_tokens`, Gemini's compatibility layer wants
 * `max_tokens`. Sending the wrong one is a 400, so it is stated per provider
 * rather than guessed.
 */
const OPENAI_COMPATIBLE = {
  gemini: {
    url: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
    envKey: "GEMINI_API_KEY",
    defaultModel: "gemini-3.5-flash-lite",
    maxTokensField: "max_tokens",
  },
  cerebras: {
    url: "https://api.cerebras.ai/v1/chat/completions",
    envKey: "CEREBRAS_API_KEY",
    defaultModel: "gpt-oss-120b",
    maxTokensField: "max_completion_tokens",
  },
} as const;

/** Whichever key is present wins; PROVIDER overrides. */
const provider: Provider =
  (process.env.PROVIDER as Provider | undefined) ??
  (process.env.GEMINI_API_KEY
    ? "gemini"
    : process.env.CEREBRAS_API_KEY
      ? "cerebras"
      : "anthropic");

// Constructed lazily: the Anthropic client throws at construction when no key
// is present, which would take the whole service down on a Gemini deploy.
let anthropic: Anthropic | null = null;
function anthropicClient(): Anthropic {
  if (!anthropic) anthropic = new Anthropic();
  return anthropic;
}

/** Deliberately small. Anything not named here is rejected, not ignored. */
const EnrichmentRequestSchema = z
  .object({
    kind: z.enum(["task", "summary"]),
    timeBucket: z.enum(["morning", "afternoon", "evening", "night"]),
    minutesToBedtime: z.number().int().min(-1440).max(1440),
    energy: z.number().int().min(1).max(5),
    mood: z.number().int().min(1).max(5),

    archetype: z
      .enum(["move", "tend", "connect", "create", "sense", "nourish", "rest"])
      .nullish(),
    targetEffort: z.number().int().min(1).max(5).nullish(),
    effortCeiling: z.number().int().min(1).max(5).nullish(),
    seedTask: z.string().max(200).nullish(),

    completedTasks: z.array(z.string().max(200)).max(30).nullish(),
    completedCount: z.number().int().min(0).max(200).nullish(),
    minutes: z.number().int().min(0).max(1440).nullish(),
    streak: z.number().int().min(0).max(3650).nullish(),
    selfWrittenCount: z.number().int().min(0).max(200).nullish(),
  })
  .strict();

type EnrichmentRequest = z.infer<typeof EnrichmentRequestSchema>;

const TaskCandidateSchema = z.object({
  text: z.string(),
  effort: z.number().int(),
  estimatedMinutes: z.number().int(),
});

const SummaryCandidateSchema = z.object({
  greeting: z.string(),
  body: z.string(),
  closing: z.string(),
});

// MARK: - Prompts

/**
 * The rules below mirror the Swift harness one for one. The client rejects
 * anything that breaks them regardless of what this prompt says -- stating them
 * here just means the model usually gets it right on the first try instead of
 * being thrown away and falling back.
 */
const HOUSE_STYLE = `
You write for Moth, a small app that gives people one tiny task at a time in
the evening so they stop doomscrolling and get to bed. Many users are
depressed. Tone is everything.

Voice:
- Second person, present tense, plain words.
- Name a specific physical action, never a goal. "Put one mug in the sink",
  not "tidy up".
- Bound it. Every task implies where it ends.
- Never imply the user is behind, lazy, or failing.
- No exclamation marks. No praise words like "amazing", "crushed it",
  "awesome", "proud of you". Warmth comes from being specific, not loud.
- Never ask a question.

Hard limits:
- No medical, clinical, diagnostic or medication content.
- No alcohol, drugs, or anything that spends money.
- Never suggest any social media, feed, or app. That is the behaviour Moth
  exists to interrupt.
- No strenuous exercise, fasting, or skipping meals.
- No links.
- No preamble. Return the content only, never "Sure, here's...".
`.trim();

function taskPrompt(request: EnrichmentRequest): string {
  return `
${HOUSE_STYLE}

Rewrite the seed task below so it is more specific and more human, keeping it
the same size and the same kind of activity.

Seed task: ${request.seedTask}
Domain: ${request.archetype}
Effort must be between 1 and ${request.effortCeiling} (1 = under a minute from
where they are sitting, 5 = a genuine push). Aim for ${request.targetEffort}.
Their energy right now is ${request.energy}/5 and their mood is ${request.mood}/5.
It is ${request.timeBucket}, ${request.minutesToBedtime} minutes before bedtime.

Return the task text (at most 140 characters), the effort as an integer, and an
honest minute estimate.
`.trim();
}

function summaryPrompt(request: EnrichmentRequest): string {
  const tasks = (request.completedTasks ?? []).map((t) => `- ${t}`).join("\n");
  const selfWritten = request.selfWrittenCount ?? 0;

  return `
${HOUSE_STYLE}

It is bedtime. Read this person's day back to them in two to four sentences.
This is the moment the whole app exists for: going to bed means sitting with an
unnarrated day, and an unnarrated day defaults to "I did nothing."

What they actually did today:
${tasks || "(nothing they let us record)"}
${selfWritten > 0 ? `\nThey also wrote ${selfWritten} task(s) themselves, which we are not showing you. You may mention the count, never invent the content.` : ""}

Totals: ${request.completedCount} things, ${request.minutes} minutes, ${request.streak} day streak.

Absolute rules, because these are factual claims about someone's own life:
- Use ONLY the numbers given above. Do not state any other number.
- If you quote a task, quote one from the list verbatim. Never invent an
  accomplishment, however plausible or kind it would be.
- Do not give advice, tips, or techniques.
- Do not assign anything for tomorrow. The day is over.
- Do not inflate. If they did one small thing, say one small thing.
${request.completedCount === 0 ? "- They completed nothing today. Do not treat that as a failure and do not scold. It is a real thing that happens." : ""}

Return a short greeting, the body, and a closing line that sends them to sleep.
`.trim();
}

// MARK: - OpenAI-compatible providers

/**
 * Calls any OpenAI-shaped chat-completions endpoint.
 *
 * We ask for JSON in the prompt and parse defensively rather than relying on a
 * structured-output parameter, because an unsupported parameter is a hard 400
 * across every provider, whereas a slightly malformed body is recoverable and,
 * failing that, just means the app keeps its local summary.
 */
async function openAICompatible(
  which: keyof typeof OPENAI_COMPATIBLE,
  system: string,
  user: string
): Promise<unknown> {
  const config = OPENAI_COMPATIBLE[which];
  const key = process.env[config.envKey];
  if (!key) throw new Error(`${which}_no_key`);

  const model = process.env[`${which.toUpperCase()}_MODEL`] ?? config.defaultModel;

  const response = await fetch(config.url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${key}`,
    },
    body: JSON.stringify({
      model,
      [config.maxTokensField]: 700,
      temperature: 0.7,
      messages: [
        { role: "system", content: system },
        { role: "user", content: user },
      ],
    }),
  });

  if (!response.ok) throw new Error(`${which}_${response.status}`);
  const payload = (await response.json()) as {
    choices?: { message?: { content?: string } }[];
  };
  const text = payload.choices?.[0]?.message?.content;
  if (!text) throw new Error(`${which}_empty`);
  return extractJSON(text);
}

/**
 * Pulls a JSON object out of a model's reply.
 *
 * Open models routinely wrap JSON in markdown fences or add a sentence of
 * preamble. Recovering from that here costs a few lines; failing on it would
 * throw away an otherwise good summary.
 */
function extractJSON(raw: string): unknown {
  const cleaned = raw
    .replace(/^\s*```(?:json)?/i, "")
    .replace(/```\s*$/, "")
    .trim();
  try {
    return JSON.parse(cleaned);
  } catch {
    const start = cleaned.indexOf("{");
    const end = cleaned.lastIndexOf("}");
    if (start === -1 || end <= start) throw new Error("unparseable");
    return JSON.parse(cleaned.slice(start, end + 1));
  }
}

// MARK: - Handlers

app.get("/health", (_req, res) => {
  res.json({ ok: true, provider });
});

app.post("/v1/enrich", async (req, res) => {
  const parsed = EnrichmentRequestSchema.safeParse(req.body);
  if (!parsed.success) {
    // Never echo the body back -- it is the one thing we promised not to keep.
    return res.status(400).json({ error: "invalid_request" });
  }
  const request = parsed.data;

  const isTask = request.kind === "task";
  const prompt = isTask ? taskPrompt(request) : summaryPrompt(request);
  const schema = isTask ? TaskCandidateSchema : SummaryCandidateSchema;

  try {
    let candidate: unknown;

    if (provider === "gemini" || provider === "cerebras") {
      candidate = await openAICompatible(
        provider,
        `${HOUSE_STYLE}\n\nReply with JSON only. No markdown, no commentary.`,
        `${prompt}\n\nReturn JSON with exactly these keys: ${Object.keys(schema.shape).join(", ")}.`
      );
    } else {
      // Note on refusals: we deliberately do NOT configure server-side model
      // fallbacks. For this app the right thing to fall back to is the
      // on-device engine, not another cloud model -- the local result is
      // already good, already validated, and already on the user's screen.
      const response = await anthropicClient().messages.parse({
        model: "claude-opus-5",
        max_tokens: 1024,
        system: HOUSE_STYLE,
        messages: [{ role: "user", content: prompt }],
        output_config: {
          effort: "low",
          format: zodOutputFormat(schema),
        },
      });
      if (response.stop_reason === "refusal") {
        return res.status(503).json({ error: "no_candidate" });
      }
      candidate = response.parsed_output;
    }

    // Shape check before it goes on the wire. The device re-validates content
    // regardless; this only catches a malformed body early.
    const checked = schema.safeParse(candidate);
    if (!checked.success) {
      return res.status(503).json({ error: "no_candidate" });
    }
    return res.json(checked.data);
  } catch (error) {
    // Log the shape of the failure, never the payload. The messages we throw
    // are status codes and parse states, so they carry no user content.
    const detail = error instanceof Error ? error.message : "unknown";
    console.error(`enrich failed (${provider}): ${detail}`);
    return res.status(503).json({ error: "upstream_unavailable" });
  }
});

const port = Number(process.env.PORT ?? 3000);
app.listen(port, () => {
  console.log(`moth enrichment proxy listening on ${port} (provider: ${provider})`);
});
