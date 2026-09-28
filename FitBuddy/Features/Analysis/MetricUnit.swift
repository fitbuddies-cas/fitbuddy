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
    ///
    /// **The time the sessions recorded, not the time they lasted.** The
    /// anchor it is checked against sums `WorkoutSummary.durationSeconds`,
    /// which is the sum over the counted sets for a Hevy session and the
    /// session time for a source that reports whole sessions — so an ordinary
    /// barbell week has no figure in this unit at all, and a card in it is
    /// downgraded to a note rather than anchored on something else.
    case hours

    /// The domain a figure in this unit can only belong to, or `nil` where
    /// both record one.
    ///
    /// Kilograms are strength, kilometres and a pace per kilometre are
    /// endurance. A heart rate and a duration are neither: a Polar strength
    /// session carries a heart rate, and both domains record time where the
    /// source reports it. Note that a duration is *recorded*, not implied —
    /// `WorkoutSummary.durationSeconds` sums the counted sets, so an ordinary
    /// barbell session has none. `AnalysisReportEvidence.weeklyMetrics` says
    /// exactly what the `hours` anchor therefore adds up.
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

    /// Whether the **model** may state a figure in this unit.
    ///
    /// False for `beatsPerMinute`, and that is a ground-rule decision rather
    /// than a formatting one. Prompt rule 7 forbids naming a target heart
    /// rate, a heart-rate zone or a percentage of maximum: those are derived
    /// from population norms, which US-3 AC3 bans, and the app was given
    /// neither this person's maximum nor the model any zone scheme rests on. A
    /// metric card is a figure *and a target for it*, so offering the unit to
    /// the model is offering it a way to prescribe a heart rate — "148 bpm →
    /// 160 bpm" is exactly the sentence rule 7 exists to prevent, and the card
    /// would lay it out as a measurement.
    ///
    /// The case itself stays: the app computes heart rates (the recovery
    /// card's "Avg HR"), and a card the *app* builds from its own figure
    /// breaks no rule. What is closed is the path from the model's answer —
    /// the schema's `unit` enum does not list it and
    /// `AnalysisReportValidator` refuses a card in it.
    var isStatableByTheModel: Bool {
        self != .beatsPerMinute
    }

    /// The units the schema offers and the prompt names, in `allCases` order.
    static var modelStatableCases: [MetricUnit] {
        allCases.filter(\.isStatableByTheModel)
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
            return WorkoutDurationFormatter.duration(seconds: value * 3_600)
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
    ///
    /// **Taken between the two figures as printed**, not between the values
    /// behind them (#186 review). `32.44 → 35.55` prints `"32.4 km"` and
    /// `"35.6 km"`; a delta from the raw values reads `"+3.1 km"` next to two
    /// numbers three point two apart, and three figures on one row that do not
    /// add up read as a bug whichever of them is right. It also decides what
    /// "no step" means: `148 → 148.2 bpm` prints the same figure twice, so
    /// there is no delta to show rather than `"+0 bpm"` (US-15 AC7).
    ///
    /// The magnitude is then written in the unit of the two figures, never in
    /// a smaller one: a step of 300 m reads `"+0.3 km"` rather than switching
    /// to metres halfway across the row.
    func delta(from: Double, to: Double, locale: Locale = .current) -> String? {
        guard from.isFinite, to.isFinite else { return nil }
        let start = displayRounded(from)
        let target = displayRounded(to)
        let step = target - start
        guard abs(step) > figureEpsilon else { return nil }
        let sign = step < 0 ? "\u{2212}" : "+"
        let magnitude = abs(step)
        switch self {
        case .kilograms:
            return sign + AnalysisCardFormatter.weight(magnitude, locale: locale)
        case .kilometers:
            let figure = magnitude.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
            return sign + figure + " km"
        case .minutesPerKilometer:
            return sign + "\(Int((magnitude * 60).rounded())) s/km"
        case .beatsPerMinute:
            return sign + HeartRateFormatter.display(magnitude, locale: locale)
        case .hours:
            let seconds = (magnitude * 3_600).rounded()
            guard let text = WorkoutDurationFormatter.duration(seconds: seconds) else { return nil }
            return sign + text
        }
    }

    /// Whether two values are **the same figure** in this unit — equal once
    /// each is rounded to the precision anything prints it with.
    ///
    /// What `AnalysisReportValidator` checks a metric card's `from` against
    /// (#186 review). The model is quoting a figure the prompt gave it, so it
    /// has to quote it: `32.4` matches an app figure of `32.44` because the
    /// prompt printed `"32.4 km"`, and `31` does not.
    func statesTheSameFigure(_ value: Double, as other: Double) -> Bool {
        guard value.isFinite, other.isFinite else { return false }
        return abs(promptRounded(value) - promptRounded(other)) <= figureEpsilon
    }

    /// `value` rounded the way the **card** prints it, still as a number.
    ///
    /// The precision each formatter actually uses: two decimals for a weight
    /// (`AnalysisCardFormatter.weight`), `DistanceFormatter`'s own ranges for
    /// a distance, whole seconds for a pace, whole beats for a heart rate,
    /// whole minutes — **truncated**, as `WorkoutDurationFormatter` truncates
    /// them — for a duration.
    private func displayRounded(_ value: Double) -> Double {
        switch self {
        case .kilograms:
            return PlainNumberFormatter.rounded(value)
        case .kilometers:
            return DistanceFormatter.displayedMeters(value * 1_000) / 1_000
        case .minutesPerKilometer:
            return (value * 60).rounded() / 60
        case .beatsPerMinute:
            return PlainNumberFormatter.rounded(value, decimals: 0)
        case .hours:
            return (value * 60).rounded(.down) / 60
        }
    }

    /// `value` rounded the way the **prompt** printed it.
    ///
    /// The same as `displayRounded` everywhere except `kilograms`, the one
    /// unit where the prompt is coarser than the card: `PromptFigures.kg`
    /// writes whole kilograms while the card shows two decimals. A card's
    /// `from` is a figure the model is quoting back, so it is compared at the
    /// precision the model was shown — anything finer would reject a correct
    /// quote for digits it was never given.
    private func promptRounded(_ value: Double) -> Double {
        self == .kilograms ? value.rounded() : displayRounded(value)
    }

    /// Absorbs floating-point noise between two figures that print identically.
    private var figureEpsilon: Double { 1e-9 }

    /// Whether the step from `from` to `to` is an improvement in this unit —
    /// what decides the card's colour, since #186 asks colour to follow the
    /// meaning rather than the sign of the number.
    func isImprovement(from: Double, to: Double) -> Bool {
        isLowerBetter ? to < from : to > from
    }
}
