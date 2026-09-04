import Foundation

/// The shipped ruleset.
///
/// Voice rules this corpus follows, because tone is most of whether somebody
/// does the thing:
///   - Name a specific physical action, never a goal. "Put one mug in the
///     sink", not "tidy up".
///   - Bound it. Every task says or implies where it ends.
///   - Never imply the user is behind, lazy, or failing.
///   - Second person, present tense, no exclamation marks.
public enum Corpus {

    // MARK: - Effort scale
    //  1  under a minute, without standing up
    //  2  a couple of minutes, might involve standing
    //  3  five to ten minutes, a real but small activity
    //  4  fifteen-ish minutes, needs actual activation
    //  5  a genuine push

    public static func grammar() -> TaskGrammar {
        TaskGrammar(frames: frames, slots: slots)
    }

    // MARK: - Slots

    public static let slots: [Slot] = [
        Slot("surface", [
            Option("your desk", weight: 1.2),
            Option("your nightstand"),
            Option("the kitchen counter"),
            Option("one shelf"),
            Option("the table you eat at"),
            Option("the floor by your bed"),
            Option("your bag"),
            Option("the chair things pile up on", weight: 0.8),
        ]),

        Slot("tiny_tidy", [
            Option("one mug"),
            Option("one plate"),
            Option("three things that don't live there"),
            Option("the empties"),
            Option("one piece of clothing"),
            Option("whatever is closest to you"),
            Option("the top layer"),
        ]),

        Slot("someone", [
            Option("someone you haven't heard from in a while", effortDelta: 1),
            Option("a friend"),
            Option("someone in your family"),
            Option("the last person who made you laugh"),
            Option("someone you owe a reply", effortDelta: 1),
            Option("a group chat you've gone quiet in", effortDelta: 1),
            Option("someone who'd be surprised to hear from you", effortDelta: 1),
        ]),

        Slot("message", [
            Option("just say hi"),
            Option("send them one thing you saw today"),
            Option("ask them one question"),
            Option("tell them one true thing"),
            Option("send a photo of where you are"),
            Option("say the thing you keep not saying", effortDelta: 1),
        ]),

        Slot("stretch", [
            Option("roll your shoulders back"),
            Option("reach up as high as you can"),
            Option("let your head hang forward"),
            Option("open your chest and breathe into it"),
            Option("stretch whichever side is tighter"),
            Option("shake out your hands"),
        ]),

        Slot("drink", [
            Option("a full glass of water", weight: 1.4),
            Option("something warm"),
            Option("tea"),
            Option("water, cold"),
        ]),

        Slot("sense_focus", [
            Option("five things you can see"),
            Option("three sounds under the loudest one"),
            Option("the temperature of the air on your arms"),
            Option("where your body meets the chair"),
            Option("the weight of your feet on the floor"),
            Option("one smell in the room"),
        ]),

        Slot("outside", [
            Option("your front door"),
            Option("a window"),
            Option("the hallway"),
            Option("outside", effortDelta: 1),
            Option("the end of your street", effortDelta: 2),
        ]),

        Slot("make", [
            Option("a bad drawing of what's in front of you"),
            Option("a list of six things, any six"),
            Option("one sentence about today"),
            Option("a playlist with three songs on it"),
            Option("a photo of something ordinary"),
            Option("a paper thing -- fold it, don't plan it"),
            Option("the first four bars of something", effortDelta: 1),
        ]),

        Slot("count", [
            Option("four"),
            Option("five"),
            Option("ten"),
            Option("twenty", effortDelta: 1),
        ]),

        Slot("short_time", [
            Option("thirty seconds"),
            Option("one minute"),
            Option("two minutes"),
            Option("five minutes", effortDelta: 1),
        ]),

        Slot("warm", [
            Option("wash your face"),
            Option("change into something softer"),
            Option("put on socks"),
            Option("turn one light off"),
            Option("open a window for a minute"),
        ]),
    ]

    // MARK: - Frames

    public static let frames: [Frame] = moveFrames + tendFrames + connectFrames
        + createFrames + senseFrames + nourishFrames + restFrames

    // MARK: Move

    static let moveFrames: [Frame] = [
        Frame("stand up. that's the whole task.", .move, effort: 1, minutes: 1, weight: 1.3),
        Frame("{stretch}, {short_time}.", .move, effort: 1, minutes: 2),
        Frame("put your phone down and {stretch}.", .move, effort: 1, minutes: 1, weight: 1.2,
              gate: Gate(rescueOnly: true)),
        Frame("walk to {outside} and come back.", .move, effort: 2, minutes: 4),
        Frame("{count} slow squats. they can be terrible squats.", .move, effort: 2, minutes: 3),
        Frame("put one song on and move to it until it ends.", .move, effort: 3, minutes: 4),
        Frame("walk to {outside}. no destination past that.", .move, effort: 3, minutes: 8,
              gate: Gate(minEnergy: 2, minMinutesToBedtime: 60)),
        Frame("go outside for {short_time}, even in what you're wearing.", .move, effort: 3,
              minutes: 6, gate: Gate(minEnergy: 2, minMinutesToBedtime: 60)),
        Frame("walk around the block. one lap, then you're done.", .move, effort: 4, minutes: 15,
              gate: Gate(minEnergy: 3, minMinutesToBedtime: 90,
                         buckets: [.morning, .afternoon, .evening])),
    ]

    // MARK: Tend

    static let tendFrames: [Frame] = [
        Frame("move {tiny_tidy} off {surface}.", .tend, effort: 1, minutes: 2, weight: 1.3),
        Frame("throw away {count} things. any {count} will do.", .tend, effort: 1, minutes: 2),
        Frame("clear {surface}. only {surface} -- stop when it's done.", .tend, effort: 2, minutes: 5),
        Frame("put {tiny_tidy} where it actually goes.", .tend, effort: 1, minutes: 2),
        Frame("make your bed, badly and quickly.", .tend, effort: 2, minutes: 3,
              gate: Gate(buckets: [.morning, .afternoon])),
        Frame("wash whatever is in the sink. if it's a lot, wash {count}.", .tend, effort: 3, minutes: 8),
        Frame("find one thing that's been bothering you and fix just that.", .tend, effort: 3, minutes: 10,
              gate: Gate(minEnergy: 2)),
        Frame("set out one thing tomorrow-you will be glad to find.", .tend, effort: 2, minutes: 3,
              gate: Gate(buckets: [.evening, .night])),
    ]

    // MARK: Connect

    static let connectFrames: [Frame] = [
        Frame("text {someone} -- {message}.", .connect, effort: 2, minutes: 3, weight: 1.2,
              gate: Gate(minMinutesToBedtime: 30)),
        Frame("react to one thing someone sent you and actually reply.", .connect, effort: 1,
              minutes: 2, gate: Gate(minMinutesToBedtime: 30)),
        Frame("send {someone} a voice note. it can be twelve seconds.", .connect, effort: 3,
              minutes: 4, gate: Gate(minEnergy: 2, minMinutesToBedtime: 45)),
        Frame("tell {someone} one specific thing you like about them.", .connect, effort: 3,
              minutes: 4, gate: Gate(minEnergy: 2, minMinutesToBedtime: 45)),
        Frame("call {someone}. if they don't pick up, that still counts.", .connect, effort: 4,
              minutes: 12, gate: Gate(minEnergy: 3, minMinutesToBedtime: 60,
                                      buckets: [.afternoon, .evening])),
    ]

    // MARK: Create

    static let createFrames: [Frame] = [
        Frame("make {make}.", .create, effort: 2, minutes: 5, weight: 1.2),
        Frame("write {make}. nobody is going to read it.", .create, effort: 2, minutes: 5),
        Frame("spend {short_time} on something you're not good at.", .create, effort: 3, minutes: 6,
              gate: Gate(minEnergy: 2)),
        Frame("open the thing you abandoned and look at it. that's all.", .create, effort: 3,
              minutes: 5, gate: Gate(minEnergy: 2, minMood: 2)),
        Frame("work on the abandoned thing for ten minutes, then stop on purpose.",
              .create, effort: 4, minutes: 12,
              gate: Gate(minEnergy: 3, minMood: 2, minMinutesToBedtime: 60)),
    ]

    // MARK: Sense

    static let senseFrames: [Frame] = [
        Frame("name {sense_focus}.", .sense, effort: 1, minutes: 2, weight: 1.4),
        Frame("look out {outside} for {short_time} without your phone.", .sense, effort: 1, minutes: 3,
              weight: 1.2),
        Frame("put your phone face down and notice {sense_focus}.", .sense, effort: 1, minutes: 2,
              weight: 1.5, gate: Gate(rescueOnly: true)),
        Frame("hold something cold for {short_time}.", .sense, effort: 1, minutes: 2),
        Frame("sit somewhere you don't usually sit for {short_time}.", .sense, effort: 2, minutes: 4),
        Frame("close your eyes and find {sense_focus}.", .sense, effort: 1, minutes: 2),
    ]

    // MARK: Nourish

    static let nourishFrames: [Frame] = [
        Frame("drink {drink}.", .nourish, effort: 1, minutes: 2, weight: 1.4),
        Frame("eat something. it does not have to be a real meal.", .nourish, effort: 2, minutes: 6),
        Frame("take your meds if you haven't.", .nourish, effort: 1, minutes: 1,
              gate: Gate(buckets: [.morning, .evening, .night])),
        Frame("{warm}.", .nourish, effort: 1, minutes: 3, weight: 1.2),
        Frame("brush your teeth, even if it's early.", .nourish, effort: 2, minutes: 3,
              gate: Gate(buckets: [.evening, .night])),
        Frame("make {drink} and drink it before you pick your phone back up.", .nourish,
              effort: 2, minutes: 5, weight: 1.2, gate: Gate(rescueOnly: true)),
    ]

    // MARK: Rest

    static let restFrames: [Frame] = [
        Frame("take {count} slow breaths. count them out.", .rest, effort: 1, minutes: 2, weight: 1.4),
        Frame("breathe in for four, out for six, {count} times.", .rest, effort: 1, minutes: 3),
        Frame("{warm}, then come back.", .rest, effort: 1, minutes: 3),
        Frame("lie down for {short_time} without putting anything on.", .rest, effort: 2, minutes: 5,
              gate: Gate(buckets: [.evening, .night])),
        Frame("put tomorrow's alarm on and leave the phone across the room.", .rest, effort: 2,
              minutes: 3, gate: Gate(buckets: [.night])),
        Frame("name one thing that went okay today. one is enough.", .rest, effort: 1, minutes: 2,
              weight: 1.3, gate: Gate(buckets: [.evening, .night])),
    ]
}
