import Foundation

/// One rendered piece of an AI recommendation (#117).
///
/// Deliberately three cases and no more: the providers answer in prose and
/// structure it with a heading, a paragraph or a bullet, and nothing in the
/// prompt asks for tables, links or code. A richer block model would be a
/// promise about output the app never requested.
enum AnalysisTextBlock: Equatable {
    /// A line the model set as a heading — `**Progressive Overload**`, or a
    /// `#` line. Carried as plain text: the markers are the markup, not part
    /// of the title.
    case heading(String)
    /// A run of prose, with inline emphasis already resolved.
    case paragraph(AttributedString)
    /// One list item, without its marker — the view draws the bullet.
    case bullet(AttributedString)
}
