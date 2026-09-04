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
5. **You take over.** After about a week, Moth invites you to write your own
   tasks, and predicts them so it costs a few taps instead of a paragraph.
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
| Hand scheduling back to the person | The `groove` phase, where you write your own |

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

## Responsible AI

- **There is no network code in the app.** Not "we promise not to send your
  data" — there is no networking layer in the binary to send it with. Grep for
  `URLSession`; there are no hits.
- **The model is legible.** A screen in the app shows you exactly what Moth
  inferred about you and how much evidence each belief rests on. Personalise
  someone and you owe them the ability to see it.
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
open Moth.xcodeproj
```

Pick an iPhone simulator and hit Run. There are **no package dependencies** —
nothing to resolve, install or download.

To run on a physical device, set your team under
*Signing & Capabilities* and change the bundle identifier.

### The engine without a simulator

`MothEngine` is plain Swift with no Apple-framework imports, so it builds and
tests anywhere Swift runs, Linux included:

```bash
swift test          # 22 tests
swift run mothdemo  # drives a full simulated day through the engine
```

`mothdemo` walks a low-energy evening, a doomscroll rescue, the bedtime
wind-down gate, the type-ahead, what the bandit learned, and the summary — all
as text. It is the fastest way to see what the engine does.

## Layout

```
Sources/MothEngine/   the engine. No UIKit, no SwiftUI, no network.
App/                  the SwiftUI app.
Tests/                22 tests, including regressions for output quality.
Sources/mothdemo/     headless driver.
Moth.xcodeproj        no dependencies.
Package.swift         same engine sources, for Linux/CI.
```

The Xcode project and the Swift package compile the *same* files in
`Sources/MothEngine`. One source of truth, two build systems, no linking step.
