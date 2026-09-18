import Foundation

/// The unit a generic metric card states its figure in (US-15 AC5, #186).
///
/// The reason the cards stopped being strength-specific. `.progression` knows
/// only kilograms and `.imbalance` only muscle groups; building a card type
/// per sport does not scale, and "weekly distance 32 → 35 km" is the same card
/// as "weekly volume 12 400 → 13 000 kg" with a different unit. So the unit
/// moved into the payload, and the card layout stopped caring which domain it
/// is showing.
///
/// Each case knows three things and nothing else: how to write a figure in it,
/// how to write a difference in it, and which domain — if any — it belongs to.
/// The last one is what US-15 AC5 turns on: under the "Endurance" profile a
/// card measured in kilograms is not validated, so no kilogram reaches the
/// screen.
///
/// The figures themselves are written by the `Core/DesignSystem` formatters
/// (#181), never here: a distance on a card and the same distance in the
/// prompt behind it have to agree to the digit.
enum MetricUnit: String, Codable, CaseIterable, Sendable {
    /// A weight or a weekly volume, in kilograms.
    case kilograms
    /// A distance, stated in kilometres — not in metres, which is what the
    /// connectors deliver and `DistanceFormatter` consumes. A model asked for
    /// a weekly distance writes `32`, and a card that made it mean 32 metres
    /// would be unreadable.
    case kilometers
    /// A pace, in minutes per kilometre: `5.3333` is `"5:20 /km"`.
    case minutesPerKilometer
    /// A heart rate, in beats per minute.
    case beatsPerMinute
    /// A duration, in hours: `4.5` is `"4 h 30 min"`.
    case hours

    /// The domain a figure in this unit can only belong to, or `nil` where
    /// both record one.
    ///
    /// Kilograms are strength, kilometres and a pace per kilometre are
    /// endurance. A heart rate and a duration are neither: a Polar strength
    /// session carries a heart rate, and every session has a duration.
    ///
    /// `AnalysisReportValidator` refuses a card whose unit names a domain the
    /// user's `AnalysisProfile` did not ask about — which is US-15 AC5 in one
    /// line, and its mirror image: no kilometres under "Strength" either.
    var domain: AnalysisDomain? {
        switch self {
        case .kilograms: return .strength
        case .kilometers, .minutesPerKilometer: return .endurance
        case .beatsPerMinute, .hours: return nil
        }
    }

    /// Whether a *smaller* figure is the better one in this unit.
    ///
    /// True for a pace only: 5:20 /km is faster than 5:40 /km, where more
    /// kilometres, more kilograms and more hours all read as more training. A
    /// heart rate is counted as lower-is-better for the same work — the card
    /// that states one recommends running easier, never harder, because the
    /// app has no target rate to recommend and the ground rules forbid naming
    /// one.
    var isLowerBetter: Bool {
        switch self {
        case .minutesPerKilometer, .beatsPerMinute: return true
        case .kilograms, .kilometers, .hours: return false
        }
    }

    /// `value` as VoiceOver reads it: `"35 kilometres"`, `"5:20 minutes per
    /// kilometre"`, `"148 beats per minute"`, `"4 hours 30 minutes"`.
    ///
    /// The figure is the one the card prints, so the screen and the label over
    /// it cannot state different numbers — only the unit is respelled, because
    /// VoiceOver reads "km", "kg" and "bpm" letter by letter (#184).
    ///
    /// Written out per case rather than by substituting a suffix: below a
    /// kilometre a distance is printed in metres, and a duration carries two
    /// units at once.
    func spoken(_ value: Double, locale: Locale = .current) -> String? {
        switch self {
        case .kilograms:
            guard let text = display(value, locale: locale) else { return nil }
            return text.replacingOccurrences(of: " kg", with: " kilograms")
        case .kilometers:
            guard let text = display(value, locale: locale) else { return nil }
            return text.hasSuffix(" km")
                ? text.replacingOccurrences(of: " km", with: " kilometres")
                : text.replacingOccurrences(of: " m", with: " metres")
        case .minutesPerKilometer:
            guard let text = display(value, locale: locale) else { return nil }
            return text.replacingOccurrences(of: " /km", with: " minutes per kilometre")
        case .beatsPerMinute:
            guard display(value, locale: locale) != nil else { return nil }
            return HeartRateFormatter.value(value, locale: locale) + " beats per minute"
        case .hours:
            guard let text = display(value, locale: locale) else { return nil }
            return text
                .replacingOccurrences(of: " h", with: text.hasPrefix("1 h") ? " hour" : " hours")
                .replacingOccurrences(of: " min", with: " minutes")
        }
    }

    /// `value` written in this unit, or `nil` where the unit cannot state it.
    ///
    /// `nil` rather than `"0 km"` or `"—"`: a figure this unit has no reading
    /// for is a figure the card must not show at all (US-15 AC7). The
    /// validator refuses such a card, so the decision is made once, before
    /// anything is laid out.
    func display(_ value: Double, locale: Locale = .current) -> String? {
        guard value.isFinite, value > 0 else { return nil }
        switch self {
        case .kilograms:
            return AnalysisCardFormatter.weight(value, locale: locale)
        case .kilometers:
            return DistanceFormatter.display(value * 1_000, locale: locale)
        case .minutesPerKilometer:
            return PaceFormatter.perKilometer(minutesPerKilometer: value)
        case .beatsPerMinute:
            return HeartRateFormatter.display(value, locale: locale)
        case .hours:
            return WorkoutDurationFormatter.seconds(value * 3_600)
        }
    }

    /// The signed step from `from` to `to`, in this unit: `"+3 km"`,
    /// `"−4 bpm"`, `"−20 s/km"`.
    ///
    /// `nil` where the difference rounds away in the unit's own precision —
    /// `"+0 km"` is not a recommendation, and the card then shows no delta
    /// rather than a zero (AC7).
    ///
    /// A pace difference is written in **seconds** per kilometre rather than
    /// as a clock: `"−0:20 /km"` reads like a pace of twenty seconds, and
    /// twenty seconds per kilometre is how a runner states the step anyway.
    func delta(from: Double, to: Double, locale: Locale = .current) -> String? {
        guard from.isFinite, to.isFinite else { return nil }
        let step = to - from
        let sign = step < 0 ? "\u{2212}" : "+"
        if self == .minutesPerKilometer {
            let seconds = (abs(step) * 60).rounded()
            guard seconds >= 1 else { return nil }
            return sign + "\(Int(seconds)) s/km"
        }
        guard let magnitude = display(abs(step), locale: locale) else { return nil }
        return sign + magnitude
    }

    /// Whether the step from `from` to `to` is an improvement in this unit —
    /// what decides the card's colour, since #186 asks colour to follow the
    /// meaning rather than the sign of the number.
    func isImprovement(from: Double, to: Double) -> Bool {
        isLowerBetter ? to < from : to > from
    }
}
