# Devpost submission — copy each section into its field

---

## Project name

```
Moth
```

---

## Elevator pitch

*(Devpost caps this at 200 characters.)*

```
An on-device buddy that catches you mid-doomscroll, hands you one small thing to do, and at bedtime reads your day back — so you can finally put the phone down.
```

---

## Built with

*(Up to 25 tags. Paste as a comma-separated list.)*

```
swift, swiftui, ios, xcode, swift-package-manager, xctest, usernotifications, node.js,
typescript, express, zod, render, google-gemini, anthropic-claude,
thompson-sampling, multi-armed-bandit, n-gram, probabilistic-grammar,
bayesian-inference, on-device-ml, offline-first, behavioral-activation,
mental-health, privacy-by-design, linux
```

---

## About the project

*(Paste everything below into the "About the project" box. Devpost renders
Markdown.)*

---

### Inspiration

Every one of us has lain in bed at 1am, not enjoying the feed, and unable to
put it down. The framing we kept hearing — that this is a willpower problem —
never matched the experience.

What actually happens is a loop with a shape. Stress makes the feed attractive.
The feed delivers unpredictable small rewards, which is the same reinforcement
schedule a slot machine uses. And every hour spent there, the thing you were
avoiding gets slightly worse — so the stress rises, and the feed becomes more
attractive still. Screen-time blockers attack only the last link in that chain.
They tell you no. They don't touch the reason you opened it, which is why most
people delete them inside a week.

The loop also runs at the worst possible hour, and we think that part is not a
coincidence. Going to bed means lying in the dark with your own day. If you
can't point to anything in it, the day defaults to *I did nothing again* — so
you don't go to bed. You scroll, so you don't have to arrive at that thought.

Moth is our attempt at the other approach: give the dopamine somewhere else, in
small real actions, and then **narrate the day back** so bed stops being the
thing you're avoiding.

### What it does

- **Six questions.** A PHQ-2-style screen and a bedtime. That's the setup.
- **One task at a time.** Never a list. A list is something you scan, compare,
  and pick nothing from — the same paralysis the feed causes — and a list of
  undone tasks is a list of small failures.
- **"I'm stuck scrolling."** One button, which hands back something you can
  start in ten seconds.
- **It learns** which kinds of things you actually finish, at which times and
  at what energy, and stops offering the rest.
- **You take over.** After five of Moth's tasks, writing your own unlocks — and
  it predicts them from your own history, so it costs a few taps rather than a
  paragraph at midnight.
- **At bedtime it interrupts you**, stops generating tasks, and reads your day
  back using things that actually happened. Then it says goodnight, and there
  is nothing else in the app to look at.

It is grounded in **behavioural activation**, an established treatment for
depression that inverts the usual intuition: you don't wait until you feel like
it — the action comes first and the motivation follows. Each part of the app
maps onto a piece of that protocol, including handing scheduling back to the
person, which is why the app is designed to get out of your way.

### How we built it

Native SwiftUI with **no third-party dependencies** — open the project, hit Run.
The engine is ~2,600 lines of plain Swift with no Apple-framework imports, so it
builds and tests on Linux as well as in the app. That mattered, because most of
it was written on a Linux machine with no Mac in the room.

The generator is not a wrapper around an API. It is a small model built to run
in a few megabytes on a 4GB phone, offline.

**A context-conditioned probabilistic grammar.** 45 sentence frames and 12
vocabulary slots, each gated on energy, mood, time of day and
minutes-to-bedtime. "Step outside and look at the sky" is a good suggestion at
6pm and a bad one at 1am, and the grammar knows the difference. Frames are
weighted by how close they sit to the difficulty the ladder asked for — exact
matches dominate, but neighbours stay in play, which stops the output
collapsing onto the same handful of sentences. Repeated slots bind once per
sentence, so *"Clear your desk. Only your desk."* names one surface.

**Thompson sampling over seven activity domains.** Each domain keeps a running
belief about how likely you are to actually complete it, held separately for
each combination of time-of-day and energy level. To pick what to offer, we
draw a sample from each of those beliefs and take the winner — so domains we've
never tried stay optimistic and get explored, while ones you keep skipping
quietly recede. It's a Beta-Bernoulli model, which is the natural fit because
the outcome is binary: the task got done or it didn't. It costs two numbers per
domain, which matters when the whole user model has to stay small.

Evidence decays a little every day, giving it a half-life of about five weeks,
so who you were three months ago stops outvoting who you are now. We learn this
rather than asking, because depressed people routinely mispredict what will
help them.

**An asymmetric difficulty ladder.** It climbs slowly on success and drops fast
on a skip — the penalty for a miss is two and a half times the reward for a
hit. That asymmetry is deliberate. Getting difficulty wrong downward costs one
task that was too easy. Getting it wrong upward costs the user's belief that
the app works, and that doesn't come back.

**A word-prediction model for type-ahead.** It looks at the last few words you
typed, and if it hasn't seen that exact run before, it backs off to a shorter
one until it finds something it recognises. Trained on the shipped corpus so
it's useful on day one, and on your own writing so it converges on your
vocabulary within a week. This is what turns writing a task into three taps
instead of a paragraph at midnight.

**One optional cloud call.** A language model is *worse* than our bandit at
choosing what to offer, worse than a constant at setting difficulty, and
inappropriate for crisis screening. It is better at exactly one thing: writing
warmly. So it writes the bedtime summary and nothing else — and every response
is re-validated **on the device** before a word reaches the screen. Sixteen
rejection reasons, of which two carry most of the weight:

- **Every number must be one we supplied.** A model claiming "you did 8 things"
  when you did 3 is discarded.
- **Every quotation must be a task that really happened.** A model inventing a
  plausible, kind-sounding accomplishment is the single worst failure this app
  could have.

The model only ever writes prose. The counts, minutes, streak and highlights are
always the local engine's, merged in after validation. Privacy is structural
rather than promised: the request type has no field for your journal, your mood
history, or the model's posteriors, so no future edit to the networking layer
can leak them by accident. Tasks *you* wrote are counted and never sent.

### Challenges we ran into

**Two holes in our guardrails that only a live model found.** We built the
validator against handwritten adversarial fixtures and it passed everything.
Then we pointed it at a real model and watched it write *"four things in
thirteen minutes"* — spelled out. Our anti-hallucination check only scanned
digits, so an invented count would have sailed straight through. In the other
direction, it was rejecting correct output for saying "five" when the real task
was *"Name five things you can see"* — punishing the model for quoting us
accurately. Fixing both took live acceptance from 6/8 to 10/10.

**A time bug that silently broke the whole morning.** Our "minutes until
bedtime" figure wrapped the wrong way, so an 11pm bedtime came out as *ten hours
past* at 9am rather than fourteen hours before. That made the bedtime screen
fire over breakfast — and, far worse, since every grammar rule requires that
number to be positive, the generator had *no usable frames at all* until the
afternoon. The app would have appeared to simply stop working every morning,
which is close to undiagnosable from a bug report.

**Effort ceilings that didn't bind.** A test caught the engine offering a
fifteen-minute task to someone forty minutes from bed. The ladder's target was a
soft preference the grammar could drift past — fine most of the time, wrong
exactly when it mattered.

**Sentences that fell apart in the middle.** Repeated slots in one frame sampled
independently, producing *"Clear your bag. Only your nightstand."*

**Writing an iOS app from Linux.** No Mac, so no compiler for the UI layer. We
pushed everything possible into a platform-free Swift package that builds and
tests locally, kept the SwiftUI layer thin, and syntax-checked it with
`swiftc -parse` — which caught six invalid string literals before they reached a
teammate's machine. Two bugs still got through and were found on the first real
build, including one assignment to a `private(set)` property.

### Accomplishments that we're proud of

**It works with the network off.** Not "we promise not to send your data" — the
entire product functions in airplane mode, on a 4GB phone, because the generator
is ours and it's tiny.

**We used a language model in exactly one place, and we don't trust it.** The
app shows you its own accept and reject counts and why it rejected the last one,
because a guardrail nobody can see isn't a guardrail.

**The safety gate outranks the product.** If the intake screen or any text field
indicates crisis, the app stops being about streaks and puts three phone numbers
on screen. Gamifying someone in distress would be actively harmful, so that path
bypasses the engine entirely.

**A zero day is not a failure state.** The summary for a day where nothing got
done is written with as much care as any other, because *"you completed 0 of 4
tasks"* is precisely the input that starts the next doomscroll.

**63 tests**, including regressions for tone and output quality — not just
correctness.

### What we learned

**Test guardrails against the thing they guard, not your imagination of it.**
Our validator was perfect against fixtures and had two real holes the moment a
live model touched it. Adversarial tests written by the person who wrote the
code inherit that person's blind spots.

**Knowing where *not* to use a model is the design work.** It took us longer to
decide the model should write one paragraph than it did to wire up the call.

**Tone is a technical requirement, not copywriting polish.** For this user, at
this hour, "Amazing work today!" makes everything else the app says
untrustworthy — so the validator rejects it in code.

**Write the failing test first, even at 2am.** Every bug above was pinned with a
test that reproduced it before we touched the fix. Two of them turned out to be
different from what we'd assumed.

### What's next for Moth

**Learn the scroll, not just the tasks.** Screen Time's DeviceActivity API can
tell us a session is running long without telling us what's in it, so Moth could
offer the rescue before you think to ask.

**Move the summary on-device too.** Apple's Foundation Models framework would
let newer hardware write it locally, with the heuristic engine still covering
everything older. The validator already sits behind a protocol.

**Widen the corpus and localise the crisis resources**, which are US-only today.

**Actually test the hypothesis.** Everything rests on the claim that a narrated
day makes bed easier to arrive at. We believe it, and we'd like to find out —
bedtime drift over a few weeks is measurable entirely on-device.
