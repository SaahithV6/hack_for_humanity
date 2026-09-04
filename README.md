# Moth

**An on-device buddy that catches you in the doomscroll and lands you before bed.**

Hack for Humanity, Summer 2026.

---

## The problem

The scroll that keeps you up until 2am is not a discipline failure. It is a
loop: stress makes the feed attractive, the feed delivers unpredictable small
rewards, the reward makes the stress worse, and the loop closes. Screen-time
blockers attack the last step in that chain and leave the first one intact,
which is why people uninstall them.

The loop also happens to run at the worst possible time. Going to bed means
sitting with an unnarrated day, and an unnarrated day defaults to *I did
nothing today* — so you keep scrolling to avoid arriving at that thought.

## What Moth does

Moth gives you the dopamine somewhere else, and then it narrates the day back
to you so bed stops being the place you avoid.

1. **Six questions.** A PHQ-2-style screen plus a bedtime. That is the whole
   setup.
2. **One task at a time.** Never a list. A list lets you scan, compare and pick
   nothing — the same paralysis the feed causes — and a list of undone tasks is
   a list of small failures.
3. **"I'm stuck scrolling."** One button. Moth hands back something you can
   start in ten seconds.
4. **It learns.** Moth works out which kinds of things *you* actually do, at
   which times, at what energy — and stops offering the rest.
5. **You take over.** After you finish **five of Moth's tasks**, writing your
   own unlocks — and the predictor means it costs a few taps instead of a
   paragraph. A progress bar counts down to it from the start, so the
   scaffolding is visibly temporary rather than a surprise.
6. **At bedtime it interrupts you** and reads your day back, in your own words,
   using things that actually happened. Then it says goodnight and there is
   nothing else in the app to look at.

Every one of those steps runs on the phone.

## Why it's built on behavioural activation

Behavioural activation is an established treatment for depression, and it
inverts the intuition people usually bring: **you do not wait to feel like it.
The action comes first and the motivation follows.** It works by scheduling
small, concrete, bounded activities across a spread of life domains, and it
works best when the person eventually takes over the scheduling themselves.

That maps onto the product exactly:

| BA principle | In Moth |
|---|---|
| Small, concrete, bounded actions | Every task names a physical action and says where it ends |
| Graded task assignment | The `Ladder` — starts at one minute, climbs only as fast as you do |
| Activity monitoring | The `Journal`, shown back to you at bedtime |
| Spread across life domains | Seven archetypes: Move, Tend, Connect, Create, Ground, Nourish, Rest |
| Hand scheduling back to the person | The `groove` phase, unlocked after five completions |

## The engine

The "micro-LLM" is not a wrapper around an API. It is a small generative model
built to run in a few megabytes on a 4GB phone, offline, with no inference
server anywhere:

**`TaskGrammar`** — a context-conditioned probabilistic grammar. 45 frames and
12 slots, each gated on energy, mood, time of day and minutes-to-bedtime.
"Step outside and look at the sky" is a fine suggestion at 6pm and a bad one at
1am, and the grammar knows the difference. Repeated slots in one frame bind to
the same value, so *"Clear your desk. Only your desk."* names one surface.

**`ArchetypeBandit`** — Thompson sampling over the seven domains, with separate
Beta posteriors per (time-of-day × energy) bucket and a daily decay so who you
were three months ago stops outvoting who you are now. We do this rather than
asking, because depressed people routinely mispredict what will help them.

**`Ladder`** — difficulty tracking that is deliberately asymmetric: it climbs
slowly on success and drops fast on a skip. Getting difficulty wrong downward
costs one easy task. Getting it wrong upward costs the user's belief that the
app works.

**`Predictor`** — an order-3 backoff n-gram plus phrase recall, trained on the
shipped corpus so it is useful on day one and on your own writing so it
converges on your vocabulary within a week. This is what turns writing a task
into three taps.

**`Summarizer`** — the bedtime read-back. Quotes your actual tasks, never
inflates, and treats a day where you did nothing as a real thing that happens
rather than a failure state.

**`Safety`** — a PHQ-2-style intake screen and a precision-weighted crisis gate
on every free-text field. If it trips, the app stops being about streaks and
puts three phone numbers on screen.

## The one place a cloud model earns its place

Everything above runs on the phone. There is exactly one optional exception,
and the reasoning behind where we drew the line is most of the point.

A cloud model is **worse** than the local engine at choosing what to offer (the
bandit learns from what you actually did; a model would be guessing), at
setting difficulty, and at crisis screening (you want that deterministic, not a
model's judgement). And the rescue button has to answer in under a tenth of a
second — a network round-trip at 11pm on bad wifi is precisely when somebody
gives up and reopens the feed.

It is **better** at exactly one thing: writing the goodnight. That is the
emotional payload of the app, it is the one screen where a two-second wait is
fine, and templates are the weakest part of what we built.

So: **the bedtime summary can optionally be written by Claude, and nothing
else.** It is off by default.

### The harness

The model is treated as an unreliable narrator that is never given the benefit
of the doubt. `Harness` in `Sources/MothEngine/Enrichment.swift` re-validates
every response **on the device**, after the server, before a word reaches a
screen. Anything that fails any check is discarded whole — there is no repair
step and no partial acceptance, because a half-trusted summary is worse than a
template.

The two checks that matter most:

- **Every number must be one we supplied.** A model saying "you did 8 things
  today" when you did 3 is rejected. This is the anti-hallucination gate, and
  it is the only reason a cloud-written summary can be trusted at all.
- **Every quotation must be a task that really happened.** A model inventing a
  plausible, kind-sounding accomplishment is the single worst failure this app
  could have, and it is the one an LLM is most likely to produce.

Plus: no invented praise, no exclamation marks, no advice, no assigning
tomorrow's work, no clinical content, no links, and the crisis screen runs over
the model's output too.

**The model only ever writes prose.** The counts, the minutes, the streak and
the highlight list are always the local engine's numbers, merged in after
validation. Even a fully validated candidate never gets to tell you what you
did.

Two of its rules exist because a real model broke them in testing: Gemini
writes *"four things in thirteen minutes"* rather than digits, so a digits-only
grounding check waved invented counts straight through; and it legitimately
restates numbers that appear inside the tasks we sent it ("Name **five** things
you can see"), which the first version wrongly flagged as fabrication. Both are
now pinned by tests.

`Tests/MothEngineTests/HarnessTests.swift` fires 31 adversarial outputs at it —
assistant preamble, fabricated counts, invented accomplishments, "amazing work",
bedtime advice, a suggestion to go scroll Instagram — and asserts each is caught
for the right reason.

### What is sent, and what cannot be

Privacy here is enforced by the type system, not by discipline.
`EnrichmentRequest` is a narrow struct with no field for your journal, your
mood history, the bandit's posteriors, or anything you typed. No future edit to
the networking layer can leak them by accident; someone would have to add a
field in a diff a human reviews.

Tasks **you** wrote are the most personal text in the app, so they are counted
and never sent. There is a test asserting the word "sister" cannot reach the
wire.

## Responsible AI

- **It works completely offline.** The cloud path is opt-in, off by default,
  and additive. If the proxy is down, slow, or unreachable, the app behaves
  exactly as it does without it and the user is never shown an error — from
  their side nothing went wrong.
- **The guardrail is visible.** The app shows you how many model responses the
  harness accepted, how many it threw away, and why it threw away the last one.
  A guardrail whose hit rate nobody watches is decoration.
- **The model is legible.** A screen shows you exactly what Moth inferred about
  you and how much evidence each belief rests on. Personalise someone and you
  owe them the ability to see it.
- **Deletion is real.** All state is one JSON file. "Delete everything" unlinks
  it.
- **No dark patterns.** No infinite feed, no variable-ratio rewards, no loss
  framing. The streak forgives the day you went to bed on time. The one push
  notification the app can send is the one asking you to stop using it.
- **It knows what it isn't.** Moth is an activity-scheduling aid, not
  treatment, and it says so.

## Running it

Requires Xcode 16 or newer.

```bash
git clone https://github.com/SaahithV6/hack_for_humanity
cd hack_for_humanity
open Moth.xcodeproj        # <- the .xcodeproj, NOT Package.swift
```

Pick the **Moth** scheme and an iPhone simulator, then Run. There are **no
package dependencies** — nothing to resolve, install or download.

> **Opening `Package.swift` instead gives you the engine, not the app.** Xcode
> will build it happily and offer a `mothdemo` scheme that prints a simulated
> day to the console — no simulator, no UI, and no previews, because the
> package deliberately contains only `Sources/`. If you are looking at terminal
> output, that is what happened. Open `Moth.xcodeproj`.

To run on a physical device, set your team under
*Signing & Capabilities* and change the bundle identifier.

### The engine without a simulator

`MothEngine` is plain Swift with no Apple-framework imports, so it builds and
tests anywhere Swift runs, Linux included:

```bash
swift test          # 57 tests
swift run mothdemo  # drives a full simulated day through the engine
```

To reach the write-your-own screen in the app, complete five tasks — tap
**Done** five times.

`mothdemo` walks a low-energy evening, a doomscroll rescue, the bedtime
wind-down gate, the type-ahead, what the bandit learned, and the summary — all
as text. It is the fastest way to see what the engine does.

### The enrichment proxy (optional)

`server/` is a small Express service that holds the API key an iOS app cannot.
Deploy to Render with the included `render.yaml`, set one provider key in the
dashboard, and point `EnrichmentClient.defaultEndpoint` at it.

The provider follows whichever key is present — `GEMINI_API_KEY`,
`CEREBRAS_API_KEY`, or `ANTHROPIC_API_KEY` — because the harness is what makes
the output safe, not the choice of model. Gemini is the default (`gemini-3.5-flash-lite`,
about 1.2s round-trip, free tier).

You can watch the harness work against a live provider:

```bash
curl -s -X POST localhost:3000/v1/enrich -H 'Content-Type: application/json' -d @request.json \
  | swift run mothdemo --validate
```

**The app does not need it.** With the toggle off — which is the default — it
is never contacted.

```bash
cd server && npm install && npm run typecheck
```

## Layout

```
Sources/MothEngine/   the engine. No UIKit, no SwiftUI, no network.
App/                  the SwiftUI app.
Tests/                22 tests, including regressions for output quality.
Sources/mothdemo/     headless driver.
server/               optional enrichment proxy (Node, deploys to Render).
Moth.xcodeproj        no dependencies.
Package.swift         same engine sources, for Linux/CI.
```

The Xcode project and the Swift package compile the *same* files in
`Sources/MothEngine`. One source of truth, two build systems, no linking step.
