# Moth — 2:00 shooting script

Narration timed at ~135 wpm, which leaves the UI room to breathe. Read slower
than feels natural; the pauses are where the app gets seen.

| Time | On screen | Narration |
|---|---|---|
| **0:00–0:16** | Dark room, phone, feed scrolling. Cut to lock screen: **11:47 PM**. Hold a beat too long. | It's almost midnight. You meant to sleep an hour ago. You're not even enjoying this — you just can't put it down. |
| **0:16–0:30** | Plain motion graphic: stress → feed → stress, closing into a loop. No stock footage. | Doomscrolling isn't a discipline problem. Stress makes the feed attractive, and the feed makes the stress worse. It peaks at bedtime — because going to bed means sitting with a day you can't account for. |
| **0:30–0:42** | App launches, moth settles. Three fast cuts through onboarding. Land on home screen. | This is Moth. Six questions, then it gives you one small thing at a time. Never a list — a list is something you scan, and pick nothing from. |
| **0:42–1:00** | Read one task card fully. Tap **Done**, buddy reacts. Tap **I'm stuck scrolling** — new task instantly. | Every task names one physical action and says where it ends. And when you're already in the scroll, one button pulls you out. It answers instantly — because at midnight on a bad connection, a spinner means you go back to the feed. |
| **1:00–1:20** | Five-segment bar filling. Flash **What Moth learned**. Compose screen: two taps, task written, no keyboard. | It learns which kinds of things you actually do, at what time, at what energy — and stops offering the rest. After five, you write your own. It predicts them, so it's three taps instead of a paragraph at midnight. |
| **1:20–1:42** | Bedtime notification. Summary reveals line by line — let it play. Stats row, closing line. | Then at your bedtime, it interrupts you, and reads the day back. Your actual tasks, in your words. Because the reason bed is hard is that an unnarrated day defaults to *I did nothing.* Then it says goodnight — and there's nothing else in the app to look at. |
| **1:42–2:00** | Airplane mode ON, app keeps working. Terminal: harness printing **REJECTED — made up a number**. End card: *Built in 30 hours. Swift, 59 tests, zero dependencies.* Moth closes its eyes. | All of this runs on the phone. Offline, a few megabytes, on a four-gigabyte phone. One optional cloud model writes the goodnight — and if it invents a number, or something you didn't do, it gets thrown away. |

255 words, 7 beats.

## How to shoot it

Record everything silent first, then lay narration over the top. Narrating live
while tapping is how a two-minute video takes four hours.

1. **Simulator, not a device.** iPhone 15 sim, then `File > Record Screen`.
   Clean status bar, no notifications, perfect framing.
2. **Reset before recording.** Delete the app from the sim so onboarding is
   fresh — otherwise it launches into the home screen and beat 3 has nothing.
3. **Get to bedtime fast.** Set the bedtime a few minutes ahead during
   onboarding rather than waiting for 11pm.
4. **Use the previews for the hard screens.** `HomeView.swift` has a *Groove*
   preview; `BedtimeView.swift` has a seeded day. No tapping through five tasks.
5. **Harness shot.** `swift run mothdemo --validate` with a bad candidate piped
   in. Full-screen terminal, large font.
6. **Narrate last**, in one pass. Re-record single beats, not the whole thing.

### The airplane-mode shot is the one to get right

It is the whole Responsible AI argument in four seconds, and no competitor's
demo can show it. Film it as one unbroken take — pull down Control Centre, tap
airplane mode, tap through two more tasks. No cuts, or it reads as staged.

### If the cloud toggle is on, warm the proxy first

Render's free tier sleeps after 15 minutes and takes up to a minute to wake —
past the client's 3-second timeout. The app would silently fall back to its
local summary and you would film the wrong thing without knowing. Hit the URL
once immediately before recording, or shoot with the toggle off.
