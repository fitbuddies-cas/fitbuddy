import SwiftUI

/// Static privacy policy reachable from the consent screen (and later from
/// Settings). Content follows the mandatory items required by the project's
/// non-functional requirements: controller, processed data, purpose, third
/// parties, third country, and data-subject rights.
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                intro
                section(
                    title: "Verantwortlich",
                    text: """
                    Verantwortlich für die Datenbearbeitung ist das FitBuddy-Projektteam \
                    (CAS-Studienprojekt, BFH Biel). FitBuddy wird im Rahmen eines \
                    Proof of Concept ausschliesslich über TestFlight an Testpersonen verteilt.
                    """
                )
                section(
                    title: "Welche Daten wir bearbeiten",
                    text: """
                    • Trainingsdaten aus deinem Hevy-Konto (Workouts, Übungen, Sätze) — \
                    diese gelten als Gesundheitsdaten nach Art. 5 lit. c nDSG.
                    • Deine Hevy- und Claude-API-Schlüssel.
                    • Zeitpunkt und Version deiner Einwilligung.
                    """
                )
                section(
                    title: "Zweck",
                    text: """
                    Die Daten werden ausschliesslich genutzt, um dir auf Anfrage eine \
                    KI-gestützte Analyse und Trainingsempfehlungen anzuzeigen. Es findet \
                    kein Tracking, keine Werbung und keine Auswertung über mehrere \
                    Nutzer:innen hinweg statt.
                    """
                )
                section(
                    title: "Empfänger (Dritte)",
                    text: """
                    • Hevy: Quelle deiner Trainingsdaten, abgerufen direkt von deinem Gerät \
                    mit deinem eigenen API-Schlüssel.
                    • Anthropic: Empfänger der Trainingsdaten für die KI-Analyse, aufgerufen \
                    direkt von deinem Gerät mit deinem eigenen API-Schlüssel.
                    Es werden keine Daten an weitere Dritte oder eigene Server des \
                    FitBuddy-Teams übertragen.
                    """
                )
                section(
                    title: "Drittland USA",
                    text: """
                    Die KI-Analyse erfolgt durch Anthropic. Vertragspartner ist Anthropic \
                    Ireland, Limited; die technische Verarbeitung findet in den USA durch \
                    Anthropic PBC statt. Für die USA besteht kein Angemessenheitsbeschluss; \
                    das Datenschutzniveau ist nicht dem Schweizer Recht gleichwertig. \
                    Grundlage der Übertragung ist der Anthropic-DPA deines eigenen Accounts \
                    (inkl. Standardvertragsklauseln und Swiss Addendum), der mit der \
                    Erstellung deines Anthropic-Kontos automatisch gilt.
                    """
                )
                section(
                    title: "Lokale Speicherung",
                    text: """
                    API-Schlüssel und Einwilligungsdaten werden ausschliesslich lokal im \
                    iOS-Schlüsselbund deines Geräts gespeichert (nur auf diesem Gerät, kein \
                    iCloud-Sync). Sie verlassen dein Gerät nur bei deinen eigenen API-Aufrufen \
                    an Hevy bzw. Anthropic.
                    """
                )
                section(
                    title: "Deine Rechte",
                    text: """
                    Du hast das Recht auf Auskunft über die bearbeiteten Daten sowie auf \
                    deren Löschung. Du kannst sämtliche lokal gespeicherten Daten (API-\
                    Schlüssel, Cache, Einwilligung) jederzeit über «Daten löschen / Account \
                    zurücksetzen» in den Einstellungen entfernen; die App kehrt dann in den \
                    Onboarding-Zustand zurück.
                    """
                )
            }
            .padding()
        }
        .navigationTitle("Datenschutzerklärung")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var intro: some View {
        Text("Diese Erklärung beschreibt, welche Daten FitBuddy bearbeitet und warum.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private func section(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
