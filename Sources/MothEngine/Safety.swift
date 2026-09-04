import Foundation

/// Screening and crisis routing.
///
/// Moth is an activity-scheduling aid, not treatment, and there is a line it
/// must not cross: if somebody is in crisis, the correct behaviour is to stop
/// being an app about streaks and put a human phone number in front of them.
/// Gamifying distress would be actively harmful, so the gate runs *before* the
/// engine on every entry point that accepts free text or a mood report.
public enum RiskLevel: String, Codable, Sendable, Error {
    /// Normal operation.
    case none
    /// Persistently low mood. Engine keeps running but tone softens, the
    /// ladder is capped, and we surface support resources non-modally.
    case elevated
    /// Explicit self-harm signal. The engine stops offering tasks and the app
    /// shows crisis resources until the user actively dismisses it.
    case crisis
}

public struct SafetyResource: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let detail: String
    /// tel: or sms: URL string. Kept as a string so the engine stays free of
    /// UIKit; the view layer turns it into a URL.
    public let action: String
    public let actionLabel: String

    public init(id: String, name: String, detail: String, action: String, actionLabel: String) {
        self.id = id
        self.name = name
        self.detail = detail
        self.action = action
        self.actionLabel = actionLabel
    }
}

public enum Safety {

    /// US-centric because that is where this hackathon's users are; the list
    /// is a constant rather than a lookup precisely because it must work with
    /// no network and no permissions.
    public static let resources: [SafetyResource] = [
        SafetyResource(
            id: "988",
            name: "988 Suicide & Crisis Lifeline",
            detail: "Free, 24/7, confidential. Call or text 988 from anywhere in the US.",
            action: "tel:988",
            actionLabel: "Call 988"
        ),
        SafetyResource(
            id: "741741",
            name: "Crisis Text Line",
            detail: "Text HOME to 741741 to reach a trained crisis counselor.",
            action: "sms:741741&body=HOME",
            actionLabel: "Text HOME"
        ),
        SafetyResource(
            id: "911",
            name: "Emergency services",
            detail: "If you are in immediate physical danger, call 911.",
            action: "tel:911",
            actionLabel: "Call 911"
        ),
    ]

    /// Phrases that trigger the crisis path.
    ///
    /// This is deliberately a small, blunt list matched on whole phrases. A
    /// cleverer classifier would fire on more true positives and also on far
    /// more false ones, and a false positive here means shoving a crisis
    /// hotline at somebody who typed "this deadline is killing me". The cost
    /// asymmetry favours precision, and the mood questionnaire is the
    /// higher-recall channel.
    private static let crisisPhrases: [String] = [
        "kill myself", "killing myself", "end my life", "ending my life",
        "want to die", "wanna die", "better off dead", "not worth living",
        "no reason to live", "suicidal", "suicide", "hurt myself",
        "hurting myself", "self harm", "self-harm", "cut myself",
        "don't want to wake up", "dont want to wake up",
    ]

    /// Screens free text the user typed. Runs entirely locally -- no text is
    /// ever transmitted, which is the only reason screening it is acceptable
    /// in the first place.
    public static func screen(text: String) -> RiskLevel {
        let normalised = text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
        for phrase in crisisPhrases where normalised.contains(phrase) {
            return .crisis
        }
        return .none
    }

    /// Screens the onboarding answers.
    ///
    /// Modelled on the PHQ-2 stem questions, which are a validated two-item
    /// screen for depression -- we use them to set tone and pacing, and we are
    /// explicit with the user that this is not a diagnosis.
    public static func screen(intake: Intake) -> RiskLevel {
        if intake.hasSelfHarmThoughts { return .crisis }
        // PHQ-2 style: little interest, and low mood, both frequent.
        if intake.lowInterestDays >= 2 && intake.lowMoodDays >= 2 { return .elevated }
        if intake.baselineMood <= 1 { return .elevated }
        return .none
    }

    /// Copy shown alongside resources. Non-clinical, non-alarming, and it does
    /// not pretend the app can help with this part.
    public static let crisisMessage = """
        Moth is a small app for small tasks. What you're carrying sounds bigger \
        than that, and you deserve someone who can actually sit with it.

        These are free, confidential, and open right now.
        """
}
