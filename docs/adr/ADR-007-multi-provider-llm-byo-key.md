# ADR-7: Multi-Provider-LLM (Claude / Gemini / Mistral) im BYO-Key-Modell

**Status:** Vorgeschlagen (Team-Review ausstehend; finale Verhältnismässigkeitsentscheidung beim Datenschutz-Verantwortlichen der BFH)
**Datum:** 2026-08-21
**Treiber-QA:** Security / Privacy (QA-1), Reliability (Analyse-Fallback, #79)

## Kontext

Mit #78 (Multi-Provider-Key-Eingabe im Onboarding) und #79 (Fallback-Kette im `InferenceService`) kann FitBuddy Trainingsdaten neu nicht mehr nur an Anthropic, sondern auch an Google (Gemini) und Mistral AI übermitteln. [[ADR-005]] begründet die Drittlandübermittlung sehr spezifisch für Anthropic (Commercial Terms, DPA inkl. SCCs + Swiss Addendum, Anthropic Ireland Ltd als Vertragspartner, vertragliches Trainings-Verbot). Für Google und Mistral fehlte diese Prüfung bisher — die Konformitätsprüfung in #78 fordert sie mit derselben Prüftiefe ein, bevor der erweiterte Consent-Screen ausgeliefert wird.

Das BYO-Key-Modell bleibt unverändert: Jeder User erstellt seinen eigenen Provider-Account, akzeptiert dabei dessen API-Bedingungen und ist selbst «Customer» des jeweiligen Providers. Keys liegen ausschliesslich im iOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`); persistiert wird zusätzlich nur die Prioritätsreihenfolge (UserDefaults, kein Key-Material).

**Google Gemini API — Recherche (Stand 21.08.2026, Quelle: Gemini API Additional Terms of Service, ai.google.dev/gemini-api/terms):**

- **Paid Services:** Google verwendet Prompts und Responses **nicht** zur Produktverbesserung / zum Modell-Training; Logging nur zeitlich begrenzt zur Missbrauchserkennung.
- **Unpaid Services (Free Tier):** Daten werden zur Produktverbesserung verwendet, inkl. möglicher menschlicher Review.
- **Entscheidender Passus für unsere Nutzergruppe:** «If you're in the European Economic Area, Switzerland, or the United Kingdom, the terms under ‹How Google uses Your Data› in ‹Paid Services› apply to all Services, including Google AI Studio and unpaid quota in the Gemini API, even though they are offered free of charge.» — Für User mit Standort Schweiz/EWR/UK gilt das Trainings-Verbot der Paid Services also **auch im Free Tier**.
- **Verarbeitungsort:** Die Terms erlauben Speicherung «in any country in which Google or its agents maintain facilities» — konservativ als USA-Übermittlung (Drittland ohne Angemessenheitsbeschluss) einzuordnen.
- **Vertragspartner:** gemäss Google-Entity-Verweis der Terms (cloud.google.com/terms/google-entity); für EMEA-Kunden typischerweise eine irische Google-Entität — exakte Entität für Schweizer Privatkunden der Gemini API ist noch zu verifizieren (offener Punkt).

**Mistral La Plateforme — Recherche (Stand 21.08.2026, Quellen: Mistral Privacy Policy / DPA (legal.mistral.ai), Mistral Docs & Help Center):**

- **Training:** API-Daten (Input/Output) werden bei aktiviertem Pay-as-you-go **standardmässig nicht** zum Training verwendet. Im kostenlosen **Experiment-Tier** dürfen API-Daten dagegen per Default für Training genutzt werden — Opt-out ist manuell in der Admin Console (Privacy-Menü) möglich.
- **Retention:** Input/Output werden standardmässig 30 Tage zur Missbrauchserkennung aufbewahrt, danach gelöscht (Zero Data Retention optional, nur mit Pay-as-you-go).
- **Verarbeitungsort:** Mistral AI ist ein französisches Unternehmen (Mistral AI SAS, Paris); La-Plateforme-Daten werden per Default in der EU gehostet. Es liegt **keine** USA-Drittlandübermittlung vor; es gilt das EU-Datenschutzniveau (DSGVO, von der Schweiz als angemessen anerkannt).

## Entscheidung

FitBuddy erlaubt im PoC bis zu drei LLM-Provider (Claude, Gemini, Mistral) im strikten BYO-Key-Modell, unter folgenden Bedingungen:

1. **Rechtsgrundlage bleibt der Provider-Vertrag des Users:** Wie bei Anthropic ([[ADR-005]]) ist der User selbst Customer von Google bzw. Mistral; sein eigener API-Vertrag (inkl. der dortigen DPA/SCC-Mechanismen) trägt die Übermittlung. Das Team schliesst keinen eigenen Vertrag mit einem der Provider.
2. **Consent- und Datenschutztext nennen alle möglichen Empfänger** (Anthropic, Google, Mistral AI) inkl. Drittland-Hinweis USA für Anthropic und Google sowie EU-Verarbeitung für Mistral — und stellen klar, dass nur die Provider Daten erhalten, für die der User einen Key hinterlegt hat (US-4 AC4). Die Consent-Version wird angehoben, sodass bestehende Tester erneut einwilligen.
3. **Mistral-Experiment-Tier-Risiko wird adressiert:** Da der kostenlose Mistral-Tier per Default trainiert, wird in der Dokumentation/Onboarding-Hilfe empfohlen, Pay-as-you-go zu aktivieren oder das Trainings-Opt-out in der Mistral Admin Console zu setzen (offener Punkt: Hinweis direkt im UI, sobald #79 den Provider aktiv nutzt).
4. **Kein Team-Key, für keinen Provider** — die Architekturpflicht aus [[ADR-004]]/[[ADR-005]] gilt unverändert für Google und Mistral.

## Konsequenzen

### + Positiv

- Analyse-Verfügbarkeit steigt: Fällt ein Provider aus oder ist das Guthaben aufgebraucht, greift die Fallback-Kette (#79) statt eines harten Fehlers.
- Für User mit Standort Schweiz gilt bei Gemini das Paid-Services-Datenregime (kein Training) auch im Free Tier — ausdrücklich in den Google-Terms verankert.
- Mistral als EU-Provider senkt das Drittland-Risiko gegenüber der reinen Anthropic-Lösung; für Mistral entfällt der USA-Hinweis.
- BYO-Key-Modell und Keychain-Architektur ([[ADR-003]], [[ADR-004]]) bleiben unverändert — kein neuer Vertrags- oder Infrastrukturaufwand für das Team.

### - Negativ

- **Drei Vertragswerke statt einem:** Änderungen an Google- oder Mistral-Terms muss das Team künftig genauso beobachten wie die Anthropic Commercial Terms; die Prüftiefe von ADR-005 ist für Google/Mistral noch nicht vollständig erreicht (offene Punkte unten).
- **Mistral-Experiment-Tier trainiert per Default:** Ein User, der den kostenlosen Tier ohne Opt-out nutzt, gibt Gesundheitsdaten in ein Trainingsprogramm. Das lässt sich app-seitig nicht technisch verhindern — nur durch klare Hinweise (Entscheidung Punkt 3).
- **Consent-Text wird länger und komplexer**; die Verständlichkeit für nicht-technische User (US-4-Ziel) leidet tendenziell.
- **Gemini-Standortabhängigkeit:** Das Trainings-Verbot im Free Tier hängt am Standort Schweiz/EWR/UK des Users. Für den geschlossenen CAS-PoC (Schweizer Tester) ist das gegeben; bei Ausweitung des Testerkreises wäre es neu zu bewerten.
- Safety-/Abuse-Logging existiert bei allen drei Providern (Anthropic Safety Classifier, Google Missbrauchs-Logging, Mistral 30-Tage-Retention) — im Datenschutztext als Verarbeitung abzubilden.

## Offene Punkte (priorisiert)

| Frage | Priorität | Fällig |
|---|---|---|
| Google-Vertragsentität für Schweizer Privatkunden der Gemini API verifizieren (Entity-Tabelle) und SCC/Swiss-Addendum-Abdeckung im Google-DPA prüfen | Hoch | vor TestFlight-Build mit Gemini-Call (#79) |
| Mistral DPA: SCC-/Schweiz-Abdeckung und Subprozessoren prüfen (EU-Hosting macht dies voraussichtlich unkritisch) | Mittel | vor TestFlight-Build mit Mistral-Call (#79) |
| Hinweis auf Mistral-Trainings-Opt-out (Experiment-Tier) im Onboarding-UI ergänzen | Hoch | mit #79 |
| Einseitige Risikonotiz (PoC) um Google/Mistral erweitern | Mittel | vor v1.0 |
| Verhältnismässigkeits-Freigabe durch Datenschutz-Verantwortlichen der BFH einholen → Status auf «Accepted» heben | Hoch | vor Merge von #79 |

---

*Quellen: Gemini API Additional Terms of Service (ai.google.dev/gemini-api/terms), Gemini API Logs Policy (ai.google.dev/gemini-api/docs/logs-policy), Mistral Privacy & Data Controls (docs.mistral.ai), Mistral Help Center (Training-Opt-out), Mistral DPA (legal.mistral.ai) — alle geprüft 2026-08-21.*
