# Moth — read-aloud script

**3:44 · 543 words · Devpost caps at 4:00.**

Everything in **bold** is spoken word for word. The *italic* lines are what to
have on screen while you say it. Replace `PARTNER` with your partner's name.

Record the screen silent first, then read this over it. Reading and tapping at
the same time is how one take becomes thirty. Delete the app from the simulator
before you start, or you'll launch straight past onboarding.

---

## Intro · 0:05

> Hey judges. I'm Saahith, and this is `PARTNER`. Our submission is called Moth.

*App open on the home screen, or just your faces. Don't over-produce the opening.*

---

## The problem · 0:52

> The mental health problem we're trying to solve is doomscrolling before bed.

> We picked that because it does double damage. The obvious harm is sleep —
> you're on your phone until two in the morning, so you sleep badly, and
> everything is harder the next day.

*A phone in a dark room. A lock screen clock reading something past midnight.*

> The second harm is worse. Every night in the feed, you're training yourself to
> take dopamine from the cheapest available source. Endless, effortless, and it
> never actually satisfies anything. So the next night, the pull is stronger.

*Keep the scrolling footage running. This is the line that separates you from a
screen-time app — slow down on it.*

> And it's hardest to break at night. Going to bed means lying in the dark with
> your own day — and if you can't point to anything in it, your brain fills that
> silence with: *I did nothing again.* So you scroll instead.

*Go to black for a second before the app appears.*

---

## The solution · 0:46

> We're solving that with Moth. Moth is a copilot for your day. It gives you
> small steps — real, finishable tasks that are good for your mental health —
> and helps you actually do them. Then at bedtime, it recites them back to you.

*Moth appears. Then a task card, then a flash of the bedtime summary.*

> That last part is the whole point. Your brain doesn't keep score of the small
> good things you did. It keeps score of what you didn't. So Moth keeps that
> score, and reads it back when you need it.

> That gives you dopamine from the good source — achievement instead of a feed —
> and it closes the day out, so you can put the phone down and sleep.

---

## Walkthrough · 1:12

> Setup is six questions and a bedtime.

*Three quick cuts through onboarding.*

> Then Moth gives you one thing at a time. Never a list — a list is something you
> scan, feel bad about, and close. One task, that names something physical and
> tells you where it ends.

*Home screen, one card. Hold long enough that it can be read.*

> You hit done, or not this one. Both are useful, because Moth is learning. It
> works out what you actually finish, at what time of day, at what energy, and
> stops offering the rest.

*Tap Done. Tap Not this one. Then open **What Moth learned**.*

> If you're already stuck scrolling, there's a button for that. Something you can
> start in ten seconds, instantly.

*Tap **I'm stuck scrolling**. The point is that nothing loads.*

> After five tasks you start writing your own, and Moth predicts what you're
> typing from your own history — so it's a few taps, not a paragraph at midnight.

*The countdown bar, then compose — tap two suggestions, never touch the keyboard.*

> Then at your bedtime, Moth interrupts you and tasks stop for the night. It
> reads your day back, in your words. If you got nothing done, it says so kindly,
> because "you completed zero of four" is exactly the sentence that starts the
> next scroll.

*Set bedtime a minute ahead beforehand and it fires on camera by itself. **Let
the summary reveal at its own pace — don't talk over it.***

> Then goodnight. Nothing else to look at.

---

## Under the hood · 0:43

> All of that runs on your phone. The generator, the learning, the word
> prediction — all ours, a few megabytes, working with the network off.

***Turn on airplane mode here and keep tapping through tasks.** One unbroken take.*

> We use an AI model in one place, writing the goodnight, and we don't trust it.
> Everything it writes is checked on the phone first. Every number has to be one
> we gave it, and anything in quotes has to be something you really did. If it
> invents an accomplishment you never had, we throw it out.

*Terminal: `swift run mothdemo --validate` printing **REJECTED — made up a number**.*

> And if you tell Moth you're in crisis, it stops being an app about streaks and
> puts three phone numbers in front of you.

*The crisis screen. Two seconds, then move on.*

---

## Close · 0:03

> That's Moth. Small things, then sleep. Thanks for watching.

*Moth closes its eyes. Cut to black.*

---

**3:44 against a 4:00 cap — sixteen seconds of headroom, so don't ad-lib.** If a
take runs long, the two safest cuts are "Then goodnight, nothing else to look
at" and the crisis line. That buys about twenty seconds.
