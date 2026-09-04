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

Every one of us has lain in bed at 1am, not enjoying the feed, unable to put the
phone down. Calling that a willpower problem never matched the experience.

What happens is a loop. Stress makes the feed attractive. The feed pays out
small unpredictable rewards on the schedule a slot machine uses. Every hour you
spend there, the thing you were avoiding gets worse, so the stress rises and the
feed gets more attractive. Screen-time blockers cut the last link in that chain
and leave the first one alone, which is why people uninstall them inside a week.

The loop runs hardest at night. Going to bed means lying in the dark with your
own day, and a day you cannot account for defaults to "I did nothing again." So
you scroll instead of sleeping.

### What it does

Setup is six questions and a bedtime. After that, Moth gives you one task at a
time, never a list, because a list is something you scan and close. Each task
names a physical action and says where it ends.

You mark it done or skip it, and both answers teach the model. It learns what
you finish at each time of day and energy level, then stops offering the rest. A
separate button hands you a ten-second task when you are already scrolling.
After five tasks, you start writing your own, and word prediction from your
history turns that into a few taps.

At your bedtime Moth interrupts you, stops generating tasks, and reads the day
back using what you actually did. Then it says goodnight, and the app has
nothing else in it to look at.

The design follows behavioural activation, an established treatment for
depression in which action precedes motivation rather than following it. The
protocol ends with the patient scheduling their own activity, which is why Moth
hands the writing over after five tasks.

### How we built it

Native SwiftUI with no third-party dependencies. The engine is 2,600 lines of
plain Swift with no Apple-framework imports, so it builds and tests on Linux as
well as on iOS. Most of it was written on a Linux machine with no Mac available.

The generator is a probabilistic grammar of 45 sentence frames and 12 vocabulary
slots, each gated on energy, mood, time of day and minutes to bedtime. "Step
outside and look at the sky" is a good suggestion at 6pm and a bad one at 1am,
and the gates encode the difference.

Selection uses Thompson sampling over seven activity domains, with a separate
belief held per time-of-day and energy bucket. Domains we have never tried stay
optimistic and get explored; domains you keep skipping recede. Evidence decays
daily, giving it a half-life near five weeks. We learn this instead of asking,
because people who are depressed routinely mispredict what will help them.

Difficulty tracking is deliberately asymmetric: a skip costs 2.5 times what a
completion gains. Aiming too low wastes one easy task. Aiming too high costs the
user's belief that the app works, and that does not come back.

Type-ahead uses a backoff word model trained on the shipped corpus and on your
own writing, so it is useful on day one and sounds like you within a week.

One optional cloud call writes the bedtime summary, which is the only job a
language model does better than our own code. Everything it returns is validated
on the device against 16 rejection rules before it reaches the screen. Two of
those carry most of the weight: every number in the summary has to be a number
we supplied, and every quotation has to be a task that actually happened. The
model writes prose only. Counts, minutes, streaks and highlights all come from
the local engine. The request type has no field for your journal, your mood
history or the model state, so a later edit to the networking layer cannot leak
them by accident. Tasks you wrote yourself are counted and never sent.

The whole app works with the network off, on a 4GB phone. The app also shows you
what it has inferred about you, how many model responses the validator accepted,
how many it threw away, and why it rejected the last one.

If the intake screen or any text field indicates crisis, the app stops being
about streaks and puts three phone numbers on the screen. That path skips the
engine entirely.

### Challenges we ran into

Our validator passed every handwritten adversarial fixture we wrote. Then we
pointed it at a live model and watched it produce "four things in thirteen
minutes", spelled out. The anti-hallucination check only scanned digits, so an
invented count would have gone straight through. In the other direction, it was
rejecting correct output for saying "five" when the task really was "Name five
things you can see", which punished the model for quoting us accurately. Fixing
both took live acceptance from 6 out of 8 to 10 out of 10.

A time bug broke the whole morning. Our minutes-to-bedtime figure wrapped the
wrong way, so an 11pm bedtime came out as ten hours past at 9am instead of
fourteen hours before. The bedtime screen fired over breakfast, and because
every grammar rule requires that number to be positive, the generator had no
usable frames at all until the afternoon. The app would have appeared to stop
working every morning, which is close to undiagnosable from a bug report.

A test caught the engine offering a fifteen-minute task to somebody forty
minutes from bed, because the difficulty target was a soft preference the
grammar could drift past. Repeated slots inside one frame were sampling
independently, which produced "Clear your bag. Only your nightstand."

Writing an iOS app from Linux meant no compiler for the UI layer. We moved
everything we could into a platform-free Swift package that builds and tests
locally, kept the SwiftUI layer thin, and syntax-checked it with swiftc -parse,
which caught six invalid string literals before they reached a teammate's
machine. Two bugs still got through and were found on the first real build.

### What we learned

Test a guardrail against the thing it guards, not against your idea of it. Ours
was perfect against fixtures and had two real holes the moment a live model
touched it. Adversarial tests written by the person who wrote the code inherit
that person's blind spots.

Deciding where a model should not go took longer than wiring up the call. A
language model picks worse than our bandit, sets difficulty worse than a
constant, and has no business doing crisis screening. It writes one paragraph.

Tone is a technical requirement here. For this user at this hour, "Amazing work
today!" makes everything else the app says untrustworthy, so the validator
rejects it in code.

We wrote the failing test first for every bug above. Two of them turned out to
be different from what we had assumed.

### What's next for Moth

Screen Time's DeviceActivity API can report that a session is running long
without reporting what is in it, so Moth could offer the rescue before you think
to ask for it.

Apple's Foundation Models framework would let newer hardware write the summary
on-device, with the existing engine still covering older phones. The validator
already sits behind a protocol.

The crisis resources are US-only and the corpus is small. Both need widening.

Everything here rests on the claim that a narrated day makes bed easier to
arrive at. Bedtime drift over a few weeks is measurable entirely on-device, and
we would like to find out.
