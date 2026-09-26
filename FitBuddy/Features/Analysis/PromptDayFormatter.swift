import Foundation

/// The one date format the prompt uses: `yyyy-MM-dd`, fixed locale, the
/// window's own time zone.
///
/// One instance per prompt, handed to the sections that need it. A prompt
/// renders up to ~40 dates and `DateFormatter` is expensive to create; it is
/// also not safe to share across calls, so the instance lives exactly as long
/// as the build that owns it.
///
/// Lifted out of `AnalysisPromptBuilder` in #183, where the prompt grew a
/// second and a third domain section that render dates of their own.
struct PromptDayFormatter {
    private let formatter: DateFormatter

    init(calendar: Calendar) {
        let formatter = DateFormatter()
        // Fixed locale and the window's own time zone: the date is data here,
        // not display text, and must not shift with the device's region.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        self.formatter = formatter
    }

    func string(_ date: Date) -> String {
        formatter.string(from: date)
    }
}
