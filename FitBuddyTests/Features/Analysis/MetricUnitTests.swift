import XCTest
@testable import FitBuddy

/// Unit tests for `MetricUnit` — the unit a generic metric card states its
/// figure in (US-15 AC5, #186).
final class MetricUnitTests: XCTestCase {
    private let english = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")

    // MARK: - Display

    /// The acceptance criterion's own card: `32 km → 35 km`, with no decimal
    /// on either side.
    func testAWholeDistanceCarriesNoDecimal() {
        XCTAssertEqual(MetricUnit.kilometers.display(32, locale: english), "32 km")
        XCTAssertEqual(MetricUnit.kilometers.display(35, locale: english), "35 km")
        XCTAssertEqual(MetricUnit.kilometers.display(8.4, locale: english), "8.4 km")
    }

    /// The criterion's other figure: `5:20 /km`.
    func testAPaceReadsAsAClock() {
        XCTAssertEqual(MetricUnit.minutesPerKilometer.display(5 + 20.0 / 60, locale: english), "5:20 /km")
        XCTAssertEqual(MetricUnit.minutesPerKilometer.display(6, locale: english), "6:00 /km")
    }

    func testEachUnitWritesItsOwnFigure() {
        XCTAssertEqual(MetricUnit.kilograms.display(62.5, locale: english), "62.5 kg")
        XCTAssertEqual(MetricUnit.beatsPerMinute.display(148.4, locale: english), "148 bpm")
        XCTAssertEqual(MetricUnit.hours.display(4.5, locale: english), "4 h 30 min")
        XCTAssertEqual(MetricUnit.hours.display(2, locale: english), "2 h")
    }

    /// The card is display text, so the figure follows the device's locale —
    /// unlike the prompt's, which never does.
    func testTheFigureFollowsTheLocale() {
        XCTAssertEqual(MetricUnit.kilometers.display(8.4, locale: german), "8,4 km")
        XCTAssertEqual(MetricUnit.kilograms.display(62.5, locale: german), "62,5 kg")
    }

    /// A figure the unit has no reading for is `nil`, never `"0 km"` and never
    /// a placeholder: the card is refused before anything is laid out
    /// (US-15 AC7).
    func testAnImpossibleFigureHasNoReading() {
        for unit in MetricUnit.allCases {
            XCTAssertNil(unit.display(0, locale: english), "\(unit) at zero")
            XCTAssertNil(unit.display(-3, locale: english), "\(unit) below zero")
            XCTAssertNil(unit.display(.nan, locale: english), "\(unit) at nan")
            XCTAssertNil(unit.display(.infinity, locale: english), "\(unit) at infinity")
        }
    }

    /// A pace slower than 99:59 per kilometre is a GPS artefact, and the card
    /// that would state it is not built.
    func testAnImpossiblePaceHasNoReading() {
        XCTAssertNil(MetricUnit.minutesPerKilometer.display(100, locale: english))
        XCTAssertEqual(MetricUnit.minutesPerKilometer.display(99 + 59.0 / 60, locale: english), "99:59 /km")
    }

    // MARK: - Delta

    func testTheDeltaCarriesItsSignAndItsUnit() {
        XCTAssertEqual(MetricUnit.kilometers.delta(from: 32, to: 35, locale: english), "+3 km")
        XCTAssertEqual(MetricUnit.kilometers.delta(from: 35, to: 32, locale: english), "\u{2212}3 km")
        XCTAssertEqual(MetricUnit.beatsPerMinute.delta(from: 152, to: 148, locale: english), "\u{2212}4 bpm")
        XCTAssertEqual(MetricUnit.kilograms.delta(from: 60, to: 62.5, locale: english), "+2.5 kg")
        XCTAssertEqual(MetricUnit.hours.delta(from: 6.5, to: 7, locale: english), "+30 min")
    }

    /// A pace step is stated in seconds per kilometre: `"−0:20 /km"` reads
    /// like a pace of twenty seconds.
    func testAPaceStepIsStatedInSeconds() {
        XCTAssertEqual(
            MetricUnit.minutesPerKilometer.delta(from: 6, to: 5 + 40.0 / 60, locale: english),
            "\u{2212}20 s/km"
        )
        XCTAssertEqual(
            MetricUnit.minutesPerKilometer.delta(from: 5.5, to: 5.75, locale: english),
            "+15 s/km"
        )
    }

    /// A step that rounds away in the unit's own precision is no step, and the
    /// card shows no delta rather than `"+0 km"` (AC7).
    func testAStepThatRoundsAwayHasNoDelta() {
        XCTAssertNil(MetricUnit.kilometers.delta(from: 32, to: 32, locale: english))
        XCTAssertNil(MetricUnit.minutesPerKilometer.delta(from: 5.5, to: 5.505, locale: english))
        XCTAssertNil(MetricUnit.beatsPerMinute.delta(from: 148, to: 148.2, locale: english))
    }

    // MARK: - Domain and direction

    /// US-15 AC5 in one property: kilograms are strength, kilometres and a
    /// pace are endurance, a heart rate and a duration are neither.
    func testOnlyTheUnitsThatBelongToOneDomainNameOne() {
        XCTAssertEqual(MetricUnit.kilograms.domain, .strength)
        XCTAssertEqual(MetricUnit.kilometers.domain, .endurance)
        XCTAssertEqual(MetricUnit.minutesPerKilometer.domain, .endurance)
        XCTAssertNil(MetricUnit.beatsPerMinute.domain)
        XCTAssertNil(MetricUnit.hours.domain)
    }

    /// The colour follows the meaning: more kilometres is an improvement, a
    /// *lower* pace is too.
    func testAnImprovementDependsOnTheUnitNotOnTheSign() {
        XCTAssertTrue(MetricUnit.kilometers.isImprovement(from: 32, to: 35))
        XCTAssertFalse(MetricUnit.kilometers.isImprovement(from: 35, to: 32))
        XCTAssertTrue(MetricUnit.minutesPerKilometer.isImprovement(from: 6, to: 5.5))
        XCTAssertFalse(MetricUnit.minutesPerKilometer.isImprovement(from: 5.5, to: 6))
        XCTAssertTrue(MetricUnit.beatsPerMinute.isImprovement(from: 152, to: 148))
    }

    // MARK: - VoiceOver

    /// Spelled out, because VoiceOver reads "km" and "bpm" letter by letter.
    func testTheSpokenFormNamesTheUnitInWords() {
        XCTAssertEqual(MetricUnit.kilometers.spoken(35, locale: english), "35 kilometres")
        XCTAssertEqual(MetricUnit.kilograms.spoken(62.5, locale: english), "62.5 kilograms")
        XCTAssertEqual(MetricUnit.beatsPerMinute.spoken(148, locale: english), "148 beats per minute")
        XCTAssertEqual(
            MetricUnit.minutesPerKilometer.spoken(5 + 20.0 / 60, locale: english),
            "5:20 minutes per kilometre"
        )
        XCTAssertEqual(MetricUnit.hours.spoken(4.5, locale: english), "4 hours 30 minutes")
        XCTAssertEqual(MetricUnit.hours.spoken(1, locale: english), "1 hour")
    }

    /// Below a kilometre a distance is printed in metres, so the spelled-out
    /// form has to follow the figure rather than the case.
    func testASpokenDistanceBelowAKilometreSaysMetres() {
        XCTAssertEqual(MetricUnit.kilometers.spoken(0.85, locale: english), "850 metres")
    }

    func testAFigureWithoutAReadingIsNotSpoken() {
        for unit in MetricUnit.allCases {
            XCTAssertNil(unit.spoken(0, locale: english), "\(unit)")
        }
    }

    // MARK: - Wire

    /// The raw values are what the schema's `unit` enum lists and what a
    /// stored card decodes back.
    func testTheRawValuesAreTheWireForm() {
        XCTAssertEqual(
            MetricUnit.allCases.map(\.rawValue),
            ["kilograms", "kilometers", "minutesPerKilometer", "beatsPerMinute", "hours"]
        )
    }
}
