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

const client = new Anthropic();

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

// MARK: - Handlers

app.get("/health", (_req, res) => {
  res.json({ ok: true });
});

app.post("/v1/enrich", async (req, res) => {
  const parsed = EnrichmentRequestSchema.safeParse(req.body);
  if (!parsed.success) {
    // Never echo the body back -- it is the one thing we promised not to keep.
    return res.status(400).json({ error: "invalid_request" });
  }
  const request = parsed.data;

  try {
    if (request.kind === "task") {
      const response = await client.messages.parse({
        model: "claude-opus-5",
        max_tokens: 1024,
        system: HOUSE_STYLE,
        messages: [{ role: "user", content: taskPrompt(request) }],
        output_config: {
          effort: "low",
          format: zodOutputFormat(TaskCandidateSchema),
        },
      });
      if (response.stop_reason === "refusal" || !response.parsed_output) {
        return res.status(503).json({ error: "no_candidate" });
      }
      return res.json(response.parsed_output);
    }

    // Note on refusals: we deliberately do NOT configure server-side model
    // fallbacks here. For this app the right thing to fall back to is the
    // on-device engine, not another cloud model -- the local result is already
    // good, already validated, and already on the user's screen.

    const response = await client.messages.parse({
      model: "claude-opus-5",
      max_tokens: 1024,
      system: HOUSE_STYLE,
      messages: [{ role: "user", content: summaryPrompt(request) }],
      output_config: {
        effort: "low",
        format: zodOutputFormat(SummaryCandidateSchema),
      },
    });
    if (response.stop_reason === "refusal" || !response.parsed_output) {
      return res.status(503).json({ error: "no_candidate" });
    }
    return res.json(response.parsed_output);
  } catch (error) {
    // Log the shape of the failure, never the payload.
    const name = error instanceof Error ? error.name : "unknown";
    console.error(`enrich failed: ${name}`);
    return res.status(503).json({ error: "upstream_unavailable" });
  }
});

const port = Number(process.env.PORT ?? 3000);
app.listen(port, () => {
  console.log(`moth enrichment proxy listening on ${port}`);
});
