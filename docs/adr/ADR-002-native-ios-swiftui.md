# ADR-2: Native iOS (SwiftUI) als Plattform

**Status:** Accepted
**Datum:** 2026-06-03

**Nachtrag (2026-09-02, #108):** Das von [[ADR-1]] geerbte Mindest-Deployment-Target liegt inzwischen bei iOS 26 statt iOS 17 ([[ADR-8]]); die Plattformentscheidung selbst bleibt unverändert. Zwei Konsequenzen unten sind damit überholt: Der Geräteausschluss endet nicht bei iPhone 8 / iPhone X, sondern umfasst alles unterhalb A13 (iPhone 11 / SE 2. Gen.), also auch XS, XS Max und XR; und das Team-Minimum ist nicht mehr Xcode 15 / macOS 14, sondern Xcode 26 mit der dafür nötigen macOS-Version. Begründung und vollständige Konsequenzen in [[ADR-8]].

---

## Kontext

FitBuddy verarbeitet Trainingsdaten (Gesundheitsdaten nach revDSG Art. 5 lit. c) und speichert zwei sensible API-Keys (Hevy, Claude) auf dem Gerät — siehe `REQUIREMENTS.md` §6/§7. Die Plattformwahl entscheidet, wie verlässlich das Versprechen «Keys verlassen das Gerät nie» technisch eingelöst werden kann. [[ADR-1]] hat SwiftData als lokale Persistenz gewählt und damit **iOS 17 als Mindest-Deployment-Target** festgesetzt — die Plattformentscheidung erbt diese Anforderung. Das Team (2–3 Personen, 3 Monate) liefert ausschliesslich für iOS aus (TestFlight, kein App Store).

### Entscheidungstreiber — Top-3-QAs

| QA | Anforderung an die Plattform | Quelle |
|---|---|---|
| **QA-1 Security / Privacy** | Direkter Keychain-Zugriff ohne JS-Bridge/WebView; kein zusätzlicher Drittcode zwischen Key-Material und Hardware | REQUIREMENTS.md §5 QA-1 |
| **QA-3 Maintainability** | Native Integration mit SwiftData ([[ADR-1]]) und Keychain ([[ADR-3]]); keine Cross-Platform-Wrapper, die bei OS-Updates brechen | REQUIREMENTS.md §5 QA-3 |
| **QA-2 Reliability** | Apple-natives Crash-Reporting (Xcode Organizer); klare App-Lifecycle-Semantik für Cache-Loads (US-2 AC2) | REQUIREMENTS.md §5 QA-2 |

### Geprüfte Optionen

| Option | Einschätzung gegen die Top-3-QAs |
|---|---|
| **Native iOS / SwiftUI** *(gewählt)* | Direkter `Security`-Framework-Zugriff (QA-1), `@Query`/`modelContext` aus SwiftData nahtlos integriert (QA-3), iOS-17-konform mit [[ADR-1]]. |
| **Native iOS / UIKit** | Reifer als SwiftUI, mehr StackOverflow-Ressourcen, bewährtere Patterns für ein Team mit unsicherem iOS-Skill-Stand. Kein nativer Hook in SwiftData; mehr Boilerplate für State (QA-3 schwächer). **Bleibt valider Fallback** wenn Skill-Audit negativ ausfällt — Entscheidung in Sprint 1. |
| **UIKit-Basis + SwiftUI-Leaf-Views (Hybrid)** | Kritische Security-Screens (Onboarding, Key-Eingabe) in UIKit, einfache Listen-Views in SwiftUI. Reduziert SwiftUI-Bug-Risiko in sicherheitsrelevanten Flows. Erhöht Komplexität leicht. Für PoC verworfenen, bei negativem Skill-Audit als Alternative zu purem UIKit evaluieren. |
| **React Native / Flutter** | JS-Bridge/Dart-Layer zwischen Keychain-API und App — verletzt QA-1; Plugins für `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` sind Drittanbieter-Code. Verworfen. |
| **Kotlin Multiplatform Mobile (KMM)** | Geteilte Business-Logik attraktiv, UI bleibt aber Native SwiftUI — im 3-Monats-Scope mit nur iOS-Target Mehraufwand ohne Ertrag. Verworfen für PoC, für v2.X erwägen. |

---

## Entscheidung

**Wir bauen FitBuddy als native iOS-App in SwiftUI mit Minimum-Deployment-Target iOS 17 (durch [[ADR-1]] festgelegt).**

Wir nutzen das Apple-`Security`-Framework direkt für Keychain-Zugriffe ([[ADR-3]]), `URLSession` für HTTP-Aufrufe ([[ADR-4]]) und SwiftData mit `@Query`/`modelContext` als Datenquelle für SwiftUI-Views ([[ADR-1]]). Es kommen keine WebViews, JavaScript-Bridges oder Cross-Platform-Frameworks zum Einsatz. Distribution erfolgt ausschliesslich über TestFlight.

**Diese Entscheidung steht unter dem Vorbehalt des Skill-Audits in Sprint 1.** Ergibt der Audit, dass kein Teammitglied produktiv in SwiftUI + async/await entwickeln kann, wird auf UIKit (oder UIKit-Hybrid) gewechselt — mit explizitem Go/No-Go-Entscheid bis Ende Sprint-1-Woche 1.

---

## Konsequenzen

### + Positiv

- **(QA-1) Keine Bridge-Angriffsfläche:** Keychain-Calls gehen direkt über `Security.framework` — kein Plugin-Code, der API-Keys versehentlich an Renderer-Kontexte exponieren könnte.
- **(QA-3) Nahtlose SwiftData-Integration:** `@Query` und `@Environment(\.modelContext)` arbeiten ohne Adapter mit der Persistenzschicht aus [[ADR-1]] — Dashboard-Views binden direkt an den Store.
- **(QA-2) Apple-native Diagnose:** Crashes landen im Xcode Organizer mit symbolisierten Stack-Traces; keine Cross-Platform-Indirection bei Fehleranalyse.
- **TestFlight-Workflow ist Standardpfad:** Privacy Manifest, Code Signing und Beta-Distribution sind dokumentierte Apple-Pfade.

### - Negativ

- **(QA-3-Risiko) Team-Skill ungeklärt:** CAS ADAI fokussiert auf AI, nicht iOS. SwiftUI + async/await + SwiftData hat 4–6 Wochen Lernkurve für Mid-Level. **Mitigation:** Skill-Audit vor Sprint 1; bei Lücken Scaffold-Workshop mit externem Mentor einplanen.
- **(QA-1-Risiko) SwiftUI-Previews und Simulator validieren Keychain-Verhalten nicht vollständig:** Keychain-Accessibility-Attribute, iCloud-Backup-Exklusion und biometrische Gates müssen auf echtem Gerät getestet werden. Jeder Security-AC (US-1) erfordert physisches Device im CI/CD oder manuell.
- **(QA-3) Android-Portierung erfordert zweite Codebase:** KMM oder Cross-Platform würde hier sparen — im 3-Monats-PoC nicht relevant, in v2.X als ADR-Revisit zu prüfen.
- **Hardware- und Kostenanforderung:** Jeder Dev braucht Mac (macOS 14 Sonoma, für Xcode 15+) + Apple Developer Program ($99/Jahr). Muss im Team-Setup adressiert sein.
- **Privacy Manifest (`PrivacyInfo.xcprivacy`) ist Release-Blocker:** Seit iOS 17 / Xcode 15 verlangt Apple für Apps, die `URLSession`, `UserDefaults` oder das Dateisystem nutzen, ein Privacy Manifest. Ohne dieses Manifest scheitert die TestFlight-Beta-Review — **nicht erst der App-Store-Release**.
- **TestFlight External Testing braucht Apple-Review (1–3 Werktage):** Bei Sprint-4-Deadline ist das ein realer Zeitpuffer, der eingeplant werden muss.
- **iOS-17-Ausschluss älterer Geräte:** iPhone 8 / iPhone X bleiben aussen vor — Konsequenz aus [[ADR-1]], hier nur weitergetragen.

---

## Offene Punkte

| Frage | Priorität | Fällig |
|---|---|---|
| **Skill-Audit: Wer im Team kann produktiv SwiftUI + async/await? Go/No-Go mit Fallback-Entscheid (UIKit / Hybrid)** | **Kritisch** | **Sprint 1, Woche 1** |
| **Privacy Manifest (`PrivacyInfo.xcprivacy`) erstellen und in Xcode-Projekt integrieren** | **Hoch** | **Sprint 1** |
| macOS-Version aller Dev-Maschinen prüfen (Xcode 15+ → macOS 14 Sonoma Pflicht) | Hoch | vor Sprint 1 |
| Apple Developer Program: Wer ist Account-Owner (BFH / Privatperson / Team)? | Hoch | Sprint 1 |
| TestFlight External vs Internal Testing — Pfad für Demo-Tester festlegen; Apple-Review-Latenz in Sprint-4-Zeitplan einplanen | Mittel | Sprint 3 |
| Universal App (iPad-Support) — IN oder OUT of Scope für PoC? | Niedrig | Sprint 2 |
