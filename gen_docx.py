#!/usr/bin/env python3
"""Generate FitBuddy Requirements Document as .docx (no external deps)."""

import zipfile, os
from xml.sax.saxutils import escape as esc

OUT = "/Users/timo/Library/CloudStorage/OneDrive-BernerFachhochschule/fitbuddy/FitBuddy_Requirements.docx"

# ── XML helpers ────────────────────────────────────────────────────────────────

def h(level, text):
    return f'<w:p><w:pPr><w:pStyle w:val="Heading{level}"/></w:pPr><w:r><w:t>{esc(text)}</w:t></w:r></w:p>'

def p(text="", bold=False, italic=False, indent=False):
    rpr = ""
    if bold or italic:
        rpr = "<w:rPr>" + ("<w:b/><w:bCs/>" if bold else "") + ("<w:i/><w:iCs/>" if italic else "") + "</w:rPr>"
    ppr = '<w:pPr><w:ind w:left="360"/></w:pPr>' if indent else ""
    t = f'<w:t xml:space="preserve">{esc(text)}</w:t>'
    return f'<w:p>{ppr}<w:r>{rpr}{t}</w:r></w:p>'

def blank():
    return '<w:p/>'

def bullet(text):
    return (
        '<w:p>'
        '<w:pPr><w:pStyle w:val="ListParagraph"/>'
        '<w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr>'
        f'<w:r><w:t xml:space="preserve">{esc(text)}</w:t></w:r></w:p>'
    )

def tbl_row(*cells, header=False):
    tcs = ""
    for c in cells:
        shading = '<w:shd w:val="clear" w:color="auto" w:fill="4472C4"/>' if header else ''
        font_color = '<w:color w:val="FFFFFF"/>' if header else ''
        bold = "<w:b/><w:bCs/>" if header else ""
        tcs += (
            '<w:tc>'
            '<w:tcPr>'
            f'{shading}'
            '<w:tcBorders>'
            '<w:top w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
            '<w:left w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
            '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
            '<w:right w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
            '</w:tcBorders>'
            '</w:tcPr>'
            f'<w:p><w:pPr><w:spacing w:before="40" w:after="40"/></w:pPr>'
            f'<w:r><w:rPr>{font_color}{bold}</w:rPr><w:t xml:space="preserve">{esc(str(c))}</w:t></w:r></w:p>'
            '</w:tc>'
        )
    return f'<w:tr>{tcs}</w:tr>'

def tbl(*rows):
    inner = "".join(rows)
    return (
        '<w:tbl>'
        '<w:tblPr>'
        '<w:tblStyle w:val="TableGrid"/>'
        '<w:tblW w:w="0" w:type="auto"/>'
        '<w:tblLook w:val="04A0"/>'
        '</w:tblPr>'
        '<w:tblGrid/>'
        f'{inner}'
        '</w:tbl>'
    )

def divider():
    return (
        '<w:p><w:pPr><w:pBdr>'
        '<w:bottom w:val="single" w:sz="6" w:space="1" w:color="4472C4"/>'
        '</w:pBdr></w:pPr></w:p>'
    )

# ── Document content ───────────────────────────────────────────────────────────

body = []

# Title block
body += [
    '<w:p><w:pPr><w:pStyle w:val="Title"/></w:pPr>'
    '<w:r><w:t>FitBuddy — Requirements Document</w:t></w:r></w:p>',
    p("CAS Application Development with AI (ADAI) 2026  ·  BFH Biel", italic=True),
    p("Version: 1.0  ·  Stand: Mai 2026", italic=True),
    blank(),
]

# ── 1. Projektzusammenfassung ─────────────────────────────────────────────────
body += [h(1, "1. Projektzusammenfassung"), divider()]
body += [
    p("FitBuddy ist eine native iOS-App, die Trainingsdaten aus Hevy über die API aggregiert "
      "und in einem einzigen Dashboard anzeigt."),
    blank(),
    p("On-demand analysiert ein AI-Agent (Claude API) die Trainingslast der letzten 90 Tage "
      "und generiert konkrete Progressions-Empfehlungen in Alltagssprache."),
    blank(),
    p("API-Keys werden ausschliesslich lokal im iOS Keychain gespeichert — Trainingsdaten verlassen "
      "das Gerät nur für den direkten AI-Analyse-Call an Anthropic."),
    blank(),
]

# ── 2. Personas ───────────────────────────────────────────────────────────────
body += [h(1, "2. Personas"), divider()]

body += [h(2, "Persona 1 — Marcus Huber")]
body += [tbl(
    tbl_row("Attribut", "Beschreibung", header=True),
    tbl_row("Name", "Marcus Huber"),
    tbl_row("Typ", "Technikaffiner Power-User"),
    tbl_row("Problem", "Trainingsdaten (Kraft + Ausdauer) liegen in verschiedenen Apps; kein ganzheitlicher Überblick ohne manuelles Zusammentragen."),
    tbl_row("Ziel", "Gesamtbelastung aus Kraft- und Ausdauertraining auf einen Blick beurteilen und datenbasierte Entscheidungen für die Progression treffen."),
    tbl_row("Frustration", "Kein Tool kombiniert Datenaggregation und AI-gestütztes Coaching. Hevy-Dashboard zeigt nur Kraftdaten, Strava nur Ausdauer."),
), blank()]

body += [h(2, "Persona 2 — Jana Vogel")]
body += [tbl(
    tbl_row("Attribut", "Beschreibung", header=True),
    tbl_row("Name", "Jana Vogel"),
    tbl_row("Typ", "Krafttraining-Einsteigerin, kein technischer Hintergrund"),
    tbl_row("Problem", "Weiss nicht, ob sie richtig trainiert oder ob Steigerungen sinnvoll und sicher wären — fehlendes Feedback aus Rohdaten."),
    tbl_row("Ziel", "Ohne Selbstinterpretation eine konkrete, verständliche Steigerungsempfehlung erhalten."),
    tbl_row("Frustration", "Onboarding mit API-Keys ist zu technisch. Hevy zeigt Zahlen, erklärt aber nicht was sie bedeuten."),
), blank()]

# ── 3. User Stories ───────────────────────────────────────────────────────────
body += [h(1, "3. User Stories mit Acceptance Criteria"), divider()]

stories = [
    {
        "id": "US-1", "moscow": "Must", "title": "API-Key sicher speichern",
        "story": "Als technikaffiner Multi-App-Nutzer möchte ich meinen Hevy API-Key lokal auf meinem iPhone speichern, damit meine Trainingsdaten nie einen fremden Server verlassen.",
        "acs": [
            ("AC1", "App wird erstmals geöffnet / User gibt Key ein und tippt «Speichern»", "Key landet ausschliesslich im iOS Keychain (kSecAttrAccessibleWhenUnlockedThisDeviceOnly); sofort per GET /workouts validiert — HTTP 200 → Dashboard, sonst Fehlermeldung, Key wird verworfen."),
            ("AC2", "Valider Key im Keychain / App wird nach Kaltstart geöffnet", "Innerhalb von 3s wird GET /workouts ausgeführt — HTTP 200 → Dashboard ohne erneute Key-Eingabe."),
            ("AC3", "Key wurde in Hevy widerrufen / API-Call gibt HTTP 401 zurück", "Key wird aus Keychain gelöscht, User landet auf Onboarding mit Meldung «Your API key is invalid. Please enter a new key.»"),
            ("AC4", "Gerät ist beim App-Start noch nicht entsperrt / App versucht Key zu lesen", "Kein API-Call, kein Absturz — App wartet auf nächsten manuellen Start im entsperrten Zustand."),
        ]
    },
    {
        "id": "US-2", "moscow": "Must", "title": "90 Tage Trainingsdaten im Dashboard",
        "story": "Als Power-User mit Kraft- und Ausdauerdaten möchte ich meine letzten 90 Tage Hevy-Trainings in einem einzigen Dashboard sehen, damit ich meine Gesamtbelastung und Progression auf einen Blick beurteilen kann.",
        "acs": [
            ("AC1", "Gültiger API-Key hinterlegt / User öffnet Dashboard", "Angezeigt: Tabelle mit Sessions pro Datum, Gesamtvolumen in kg (Gewicht × Reps × Sets), Ø Trainingstage/Woche, Diagramm Muskelbelastungsverteilung — Zeitraum: letzte 90 Tage."),
            ("AC2", "Hevy API nicht erreichbar / Dashboard wird geladen", "Gecachte Daten werden angezeigt mit sichtbarem Hinweis auf letzten Sync-Zeitstempel."),
            ("AC3", "User hat >90 Tage nicht trainiert / User öffnet Dashboard", "Text: «No training data for the last 90 days»"),
        ]
    },
    {
        "id": "US-3", "moscow": "Must", "title": "AI-Analyse auf Knopfdruck",
        "story": "Als Krafttraining-Einsteigerin möchte ich auf Knopfdruck eine AI-Analyse meiner Trainingslast abrufen, damit ich ohne Selbstinterpretation weiss, ob ich diese Woche steigern kann.",
        "acs": [
            ("AC1", "≥2 Wochen Trainingsdaten vorhanden / Jana tippt «Analysieren»", "Spinner erscheint sofort; Empfehlung angezeigt sobald Claude antwortet; nach 30s ohne Antwort erscheint Cancel-Button mit «Analysis is taking longer than expected — tap to cancel»."),
            ("AC2", "Analyse abgeschlossen / Jana liest Empfehlung", "Empfehlung enthält konkrete Handlung («Increase squat weight by 2.5 kg»), keine allgemeinen Aussagen."),
            ("AC3", "Analyse läuft / LLM-Prompt wird zusammengestellt", "Prompt enthält ausschliesslich Daten des eingeloggten Users — keine Benchmarks fremder Nutzer."),
            ("AC4", "User hat in 4 Wochen Beine, Oberkörper und Rücken trainiert / Empfehlung angezeigt", "Geht auf mindestens 2 verschiedene Muskelgruppen ein."),
            ("AC5", "Hohes Volumen, konstant niedrige Gewichte / Analyse läuft", "AI empfiehlt explizit Intensitätssteigerung (Gewicht), nicht pauschal «mehr trainieren»."),
            ("AC6", "User hat an ≥6 von 7 Tagen trainiert / Analyse läuft", "Empfehlung enthält expliziten Recovery-Hinweis — keine Steigerungsempfehlung ohne diesen Hinweis."),
            ("AC7", "Analyse abgeschlossen / Empfehlung angezeigt", "Nennt mindestens eine konkrete Übung mit konkretem Wert («Increase bench press from 60 kg to 62.5 kg»)."),
            ("AC8", "User trainiert Brust 3×/Woche, Beine 1×/Woche / Empfehlung generiert", "AI weist auf Muskelgruppen-Dysbalance hin."),
            ("AC9", "Empfehlung angezeigt / —", "Unter der Empfehlung erscheinen zwei Buttons: «Helpful» / «Not helpful» — Tap wird lokal gespeichert; kein Backend-Call."),
        ]
    },
    {
        "id": "US-4", "moscow": "Must", "title": "Onboarding in 3 Schritten",
        "story": "Als Nutzerin ohne technischen Hintergrund möchte ich den Hevy und Claude API-Key in maximal 3 verständlichen Schritten einrichten, damit ich die App nutzen kann, ohne eine Dokumentation lesen zu müssen.",
        "acs": [
            ("AC1", "Jana öffnet FitBuddy zum ersten Mal / Onboarding-Flow startet", "Jeder Schritt erklärt mit Screenshot wo in Hevy der API-Key zu finden ist."),
            ("AC2", "Hevy API-Key gespeichert / Jana tippt «Next»", "Claude API-Key kann eingegeben oder vorerst übersprungen werden."),
            ("AC3", "Jana gibt ungültigen Key ein / Sie tippt «Verbinden»", "Fehlermeldung erscheint mit direktem Link zur Hevy API-Key-Seite."),
            ("AC4", "Onboarding-Flow startet / Consent-Screen wird angezeigt", "User sieht und bestätigt explizit: (1) Trainingsdaten werden für die AI-Analyse an Anthropic (USA) übertragen, (2) FitBuddy ist kein medizinisches Produkt — der User trägt selbst Verantwortung für umgesetzte Empfehlungen. Ohne Bestätigung kein Zugang zur App."),
            ("AC5", "User hat Consent gegeben / Consent wird gespeichert", "Datum und Consent-Version werden lokal im Keychain gespeichert — kein erneutes Anzeigen bei App-Updates sofern Version identisch."),
        ]
    },
    {
        "id": "US-5", "moscow": "Should", "title": "Zweite Datenquelle verbinden",
        "story": "Als Nutzer möchte ich einen zweiten Trainings-Account verbinden (z.B. Strava), damit FitBuddy auch meine Ausdauerdaten abruft.",
        "acs": [
            ("AC1", "Nutzer tippt «Quelle hinzufügen» / wählt Quelle und schliesst OAuth-Flow ab", "Aktivitäten der letzten 90 Tage erscheinen normalisiert im Dashboard neben bestehenden Daten."),
            ("AC2", "Token einer Quelle ist abgelaufen / Dashboard lädt", "Hinweis erscheint («Reconnect Strava») mit direktem Link zum Re-Auth-Flow."),
        ]
    },
    {
        "id": "US-6", "moscow": "Should", "title": "Analyse-Kontext transparent machen",
        "story": "Als Nutzer möchte ich sehen, auf welcher Datenbasis die AI-Empfehlung generiert wurde, damit ich die Empfehlung einordnen und ihr vertrauen oder sie hinterfragen kann.",
        "acs": [
            ("AC1", "AI-Analyse abgeschlossen / Empfehlung angezeigt", "Kompakte Zusammenfassung: Quellen, Zeitraum, Anzahl Trainings («Based on 12 Hevy workouts over the last 90 days»)."),
            ("AC2", "Weniger als 5 Trainings im Analysezeitraum / Empfehlung angezeigt", "Kontext-Hinweis enthält explizite Warnung, dass Datenbasis dünn ist."),
        ]
    },
    {
        "id": "US-7", "moscow": "Should", "title": "Übungssuche & Filter",
        "story": "Als datengetriebener Nutzer möchte ich Übungen in meiner Trainingshistorie suchen und nach Muskelgruppe filtern, damit ich bei 50+ Übungen schnell die richtige für die Progressionskurve finde.",
        "acs": [
            ("AC1", "Übungsübersicht mit ≥10 Einträgen / User tippt in Suchfeld", "Liste filtert in Echtzeit (case-insensitive). Keine Treffer → «No exercises found»."),
            ("AC2", "User öffnet Muskelgruppen-Filter / wählt «Legs»", "Nur Übungen der Kategorie Beine angezeigt. Mehrfachauswahl möglich."),
        ]
    },
    {
        "id": "US-8", "moscow": "Could", "title": "Datenquelle-Status sichtbar",
        "story": "Als Nutzer möchte ich auf einen Blick sehen, welche Datenquellen verbunden und aktuell sind, damit ich weiss, ob die AI-Analyse auf vollständigen oder veralteten Daten basiert.",
        "acs": [
            ("AC1", "Datenquelle seit >24h nicht synchronisiert / User öffnet Dashboard", "Sichtbarer Indikator mit Zeitstempel des letzten Syncs und Retry-Button."),
            ("AC2", "API-Key wurde in Quell-App widerrufen / FitBuddy macht Sync-Versuch", "User wird aktiv benachrichtigt — kein stilles Weiterlaufen mit gecachten Daten."),
        ]
    },
    {
        "id": "US-9", "moscow": "Could", "title": "Progressionskurven pro Übung",
        "story": "Als datengetriebener Nutzer möchte ich Progressionskurven pro Übung über Zeit sehen, damit ich Plateaus früh erkenne und meinen Plan gezielt anpassen kann.",
        "acs": [
            ("AC1", "Übung hat ≥2 Sessions in 12 Wochen / User öffnet Detailansicht", "Liniendiagramm mit 1RM-Schätzwert pro Session (Epley: weight × (1 + reps/30)), X=Datum, Y=kg."),
            ("AC2", "3 aufeinanderfolgende Sessions ohne höheren 1RM / Dashboard lädt", "Übung wird visuell als «Plateau» markiert (gelbes Label)."),
            ("AC3", "<2 Sessions mit verwertbaren Daten in 12 Wochen / Detailansicht öffnet", "Kein Diagramm — Hinweis: «Not enough data — at least 2 sessions needed»"),
        ]
    },
    {
        "id": "US-10", "moscow": "Could", "title": "Daten manuell neu laden (Pull-to-Refresh)",
        "story": "Als Nutzer möchte ich die Trainingsdaten manuell neu laden können, damit ich nach einem API-Ausfall sofort aktuelle Daten sehe ohne die App neu zu starten.",
        "acs": [
            ("AC1", "Dashboard zeigt gecachte Daten / User zieht Liste nach unten", "Neuer API-Call wird ausgelöst. Bei Erfolg: Daten aktualisiert, Sync-Zeitstempel erneuert."),
            ("AC2", "Pull-to-Refresh ausgelöst / API gibt erneut Fehler zurück", "Fehlermeldung erscheint, gecachte Daten bleiben sichtbar, Spinner verschwindet."),
        ]
    },
    {
        "id": "US-11", "moscow": "Won't", "title": "Wochenübersicht als Push-Notification",
        "story": "Als Nutzerin möchte ich eine Wochenübersicht als Push-Notification erhalten, damit ich auch ohne aktives App-Öffnen weiss, wie meine Woche war.",
        "acs": [
            ("AC1", "User hat Notifications erlaubt / Sonntag 18:00 Uhr", "Notification mit Trainingsanzahl und einer Zeile AI-Feedback. Bei 0 Trainings: keine Notification."),
        ]
    },
    {
        "id": "US-12", "moscow": "Won't", "title": "Trainingsvorschlag zurück in Hevy schreiben",
        "story": "Als Nutzer möchte ich die vorgeschlagene Progression per Knopfdruck zurück in die Hevy-App schreiben lassen, damit ich in der Trainingsapp die Steigerung sehe.",
        "acs": [
            ("AC1", "AI-Empfehlung mit konkreten Werten / User tippt «Add to Hevy»", "Vorschlag wird über Hevy-API in zugehörige Routine geschrieben; Bestätigung mit Link zur Routine."),
        ]
    },
]

moscow_colors = {"Must": "C00000", "Should": "ED7D31", "Could": "70AD47", "Won't": "7F7F7F"}

for s in stories:
    body += [h(2, f"{s['id']} · {s['title']}  [{s['moscow']}]")]
    body += [p(s["story"], italic=True), blank()]
    body += [tbl(
        tbl_row("AC", "Given / When", "Then", header=True),
        *[tbl_row(ac[0], ac[1], ac[2]) for ac in s["acs"]],
    ), blank()]

# ── 4. MoSCoW-Tabelle ─────────────────────────────────────────────────────────
body += [h(1, "4. MoSCoW-Tabelle"), divider()]

moscow_rows = [
    ("US-1",  "API-Key sicher speichern",                    "Must",   "Ohne Keychain-Speicherung kein API-Call; sicherheitskritisch; Sprint 1."),
    ("US-2",  "90 Tage Trainingsdaten im Dashboard",         "Must",   "Datenbasis für AI-Analyse (US-3) und alle Visualisierungen."),
    ("US-3",  "AI-Analyse auf Knopfdruck",                   "Must",   "Die AI-Empfehlung IST das Produkt — ohne sie ist FitBuddy ein reiner Hevy-Viewer."),
    ("US-4",  "Onboarding in 3 Schritten",                   "Must",   "Zwei API-Keys sind für Nicht-Techniker (Jana) echtes Produktrisiko."),
    ("US-5",  "Zweite Datenquelle verbinden",                "Should", "Strategische Absicherung; Connector-Interface im PoC verankern, Strava-Connector v1.1."),
    ("US-6",  "Analyse-Kontext transparent machen",          "Should", "Eigenständige Story nur für Warnung bei dünner Datenbasis (<5 Trainings)."),
    ("US-7",  "Übungssuche & Filter",                        "Should", "Nötig ab >20 Übungen in der Historie; im 3-Monats-MVP selten erreicht."),
    ("US-8",  "Datenquelle-Status sichtbar",                 "Could",  "Sync-Zeitstempel aus US-2 AC2 reicht bei einer Quelle; vollwertig ab v1.1."),
    ("US-9",  "Progressionskurven pro Übung",                "Could",  "US-3 deckt den Hauptnutzen ab; Epley-Formel + Plateau-Detection nicht-trivial."),
    ("US-10", "Daten manuell neu laden (Pull-to-Refresh)",   "Could",  "iOS-Pattern das User erwarten — kein Showstopper. 1–2 Tage Aufwand."),
    ("US-11", "Wochenübersicht als Push-Notification",       "Won't",  "iOS-Permission + Background-Scheduling + LLM-Fallback = eigenes Sub-System. Relevant ab v1.2."),
    ("US-12", "Trainingsvorschlag zurück in Hevy schreiben", "Won't",  "Erfordert Hevy PRO; UX-Klärung (Routine vs. Future-Workout); Haftungsrisiko."),
]

body += [tbl(
    tbl_row("ID", "Titel", "MoSCoW", "Begründung", header=True),
    *[tbl_row(*r) for r in moscow_rows],
), blank()]

# ── 5. Offene Risiken ─────────────────────────────────────────────────────────
body += [h(1, "5. Top 3 offene Risiken"), divider()]

risks = [
    ("R1 — Plattform-Abhängigkeit",
     "Hevy hat explizit keine API-Garantien gegeben («no guarantees — we might abandon this entirely»). "
     "Strava hat 2020 den API-Zugang bereits massiv eingeschränkt.",
     "Hevy ToS auf kommerzielle API-Nutzung sofort prüfen. Connector-Interface so bauen, dass ein zweiter Datenlieferant "
     "ohne Refactor integrierbar ist. Ein Mock-File mit Beispiel-Response committen, gegen das im Notfall entwickelt werden kann."),
    ("R2 — Onboarding-Hürde für Nicht-Techniker (Persona Jana)",
     "Das Onboarding verlangt zwei API-Keys (Hevy + Claude). Für Jana bedeutet das: Anthropic-Konto erstellen, "
     "Kreditkarte hinterlegen, API-Key aus der Console kopieren. Conversion-Rate realistisch nahe Null ohne geführten Flow.",
     "US-4 als Must-have mit 5 Acceptance Criteria. Onboarding mit Screenshots und direktem Link zur Key-Seite. "
     "Claude-Key im ersten Schritt überspringbar (US-4 AC2) — AI-Feature nachrüstbar."),
    ("R3 — Qualität der AI-Empfehlungen ist der eigentliche Kern-Moat",
     "US-3 hat 9 Acceptance Criteria die gleichzeitig erfüllt sein müssen (Recovery, Dysbalance, konkrete Werte, "
     "verständliche Sprache, kein Fachjargon). Das ist Prompt Engineering + Output-Validierung + Retry-Logik — "
     "kein einfacher API-Call. Wer im Team hat LLM-Production-Erfahrung?",
     "Explizite Eval-Woche einplanen: 20 realistische Test-Cases mit echten Userdaten, durch jeden Prompt-Change durchklicken. "
     "Prompt-Iteration ist die eigentliche Arbeit, nicht der iOS-Code."),
]

for title, problem, mitigation in risks:
    body += [h(2, title)]
    body += [p("Problem:", bold=True), p(problem), blank()]
    body += [p("Massnahme:", bold=True), p(mitigation), blank()]

# ── 6. Out-of-Scope ───────────────────────────────────────────────────────────
body += [h(1, "6. Out-of-Scope"), divider()]
body += [p("Folgendes ist für den PoC bewusst ausgeschlossen:"), blank()]

out_of_scope = [
    ("App Store Veröffentlichung", "Distribution im PoC ausschliesslich via TestFlight / Sideload. App-Store-Prozess (Privacy Policy URL, Datenschutz-Manifest, Apple Review) würde 2–4 Wochen Verzug bedeuten."),
    ("Push-Notifications (US-11)", "iOS-Permission-Flow + Background-Scheduling + LLM-Call-Fallback ist ein eigenes Sub-System. Relevant ab v1.2 wenn Retention-Daten zeigen, dass User die App nicht regelmässig öffnen."),
    ("Trainingsvorschlag zurück in Hevy schreiben (US-12)", "Setzt Hevy PRO voraus. Erfordert UX-Klärung (Routine vs. zukünftiges Workout, Bestätigung/Undo). Haftungsrisiko bei falscher AI-Empfehlung."),
    ("Strava-Connector (v1.1)", "Connector-Interface wird im PoC architektonisch verankert, die Strava-Implementierung selbst (OAuth, Token-Refresh, Normalisierung) folgt in v1.1."),
    ("Apple Health Integration", "Offener Entscheid: passive Gesundheitsdaten (Schlaf, HRV, Ruheherzrate) — IN oder OUT of Scope? Muss vor Modul 3 (Architektur) entschieden werden."),
    ("i18n / Lokalisierungsframework", "FitBuddy ist English-only im PoC. Alle UI-Strings, Fehlermeldungen und der System-Prompt sind auf Englisch. Als Definition of Done geführt, nicht als Feature."),
    ("Backend / Server-seitiger Proxy", "API-Keys bleiben lokal im iOS Keychain. Alle API-Calls laufen direkt vom Gerät. Kein serverseitiger Proxy im PoC. Revisit vor v1.0-Launch obligatorisch."),
]

body += [tbl(
    tbl_row("Ausgeschlossen", "Begründung", header=True),
    *[tbl_row(title, reason) for title, reason in out_of_scope],
), blank()]

# ── Assemble document XML ──────────────────────────────────────────────────────

DOCUMENT_XML = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document
  xmlns:wpc="http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas"
  xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
  xmlns:o="urn:schemas-microsoft-com:office:office"
  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"
  xmlns:v="urn:schemas-microsoft-com:vml"
  xmlns:wp14="http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing"
  xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
  xmlns:w10="urn:schemas-microsoft-com:office:word"
  xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
  xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml"
  xmlns:wpg="http://schemas.microsoft.com/office/word/2010/wordprocessingGroup"
  xmlns:wpi="http://schemas.microsoft.com/office/word/2010/wordprocessingInk"
  xmlns:wne="http://schemas.microsoft.com/office/word/2006/wordml"
  xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"
  mc:Ignorable="w14 wp14">
<w:body>
''' + "\n".join(body) + '''
<w:sectPr>
  <w:pgSz w:w="11906" w:h="16838"/>
  <w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="709" w:footer="709" w:gutter="0"/>
</w:sectPr>
</w:body>
</w:document>'''

CONTENT_TYPES = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
  <Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>
  <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
</Types>'''

RELS = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>'''

WORD_RELS = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>
</Relationships>'''

SETTINGS = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:defaultTabStop w:val="720"/>
</w:settings>'''

NUMBERING = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:abstractNum w:abstractNumId="0">
    <w:lvl w:ilvl="0">
      <w:start w:val="1"/>
      <w:numFmt w:val="bullet"/>
      <w:lvlText w:val="•"/>
      <w:lvlJc w:val="left"/>
      <w:pPr><w:ind w:left="360" w:hanging="360"/></w:pPr>
    </w:lvl>
  </w:abstractNum>
  <w:num w:numId="1">
    <w:abstractNumId w:val="0"/>
  </w:num>
</w:numbering>'''

STYLES = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
          xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <w:docDefaults>
    <w:rPrDefault>
      <w:rPr>
        <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/>
        <w:sz w:val="22"/>
        <w:szCs w:val="22"/>
      </w:rPr>
    </w:rPrDefault>
    <w:pPrDefault>
      <w:pPr>
        <w:spacing w:after="160" w:line="259" w:lineRule="auto"/>
      </w:pPr>
    </w:pPrDefault>
  </w:docDefaults>

  <w:style w:type="paragraph" w:styleId="Normal">
    <w:name w:val="Normal"/>
    <w:pPr><w:spacing w:after="120"/></w:pPr>
    <w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="22"/></w:rPr>
  </w:style>

  <w:style w:type="paragraph" w:styleId="Title">
    <w:name w:val="Title"/>
    <w:pPr><w:spacing w:before="0" w:after="280"/><w:jc w:val="left"/></w:pPr>
    <w:rPr>
      <w:rFonts w:ascii="Calibri Light" w:hAnsi="Calibri Light"/>
      <w:color w:val="2E74B5"/>
      <w:sz w:val="52"/>
      <w:szCs w:val="52"/>
    </w:rPr>
  </w:style>

  <w:style w:type="paragraph" w:styleId="Heading1">
    <w:name w:val="Heading 1"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr>
      <w:keepNext/>
      <w:spacing w:before="360" w:after="80"/>
      <w:outlineLvl w:val="0"/>
    </w:pPr>
    <w:rPr>
      <w:rFonts w:ascii="Calibri Light" w:hAnsi="Calibri Light"/>
      <w:color w:val="2E74B5"/>
      <w:sz w:val="32"/>
      <w:szCs w:val="32"/>
    </w:rPr>
  </w:style>

  <w:style w:type="paragraph" w:styleId="Heading2">
    <w:name w:val="Heading 2"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr>
      <w:keepNext/>
      <w:spacing w:before="280" w:after="80"/>
      <w:outlineLvl w:val="1"/>
    </w:pPr>
    <w:rPr>
      <w:rFonts w:ascii="Calibri Light" w:hAnsi="Calibri Light"/>
      <w:color w:val="2E74B5"/>
      <w:sz w:val="26"/>
      <w:szCs w:val="26"/>
    </w:rPr>
  </w:style>

  <w:style w:type="paragraph" w:styleId="ListParagraph">
    <w:name w:val="List Paragraph"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr>
      <w:ind w:left="360"/>
      <w:spacing w:after="80"/>
    </w:pPr>
  </w:style>

  <w:style w:type="table" w:styleId="TableGrid">
    <w:name w:val="Table Grid"/>
    <w:tblPr>
      <w:tblBorders>
        <w:top w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>
        <w:left w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>
        <w:bottom w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>
        <w:right w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>
        <w:insideH w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>
        <w:insideV w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>
      </w:tblBorders>
    </w:tblPr>
    <w:rPr><w:sz w:val="20"/></w:rPr>
  </w:style>
</w:styles>'''

# ── Write .docx ────────────────────────────────────────────────────────────────
with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("[Content_Types].xml", CONTENT_TYPES)
    z.writestr("_rels/.rels", RELS)
    z.writestr("word/document.xml", DOCUMENT_XML)
    z.writestr("word/_rels/document.xml.rels", WORD_RELS)
    z.writestr("word/styles.xml", STYLES)
    z.writestr("word/settings.xml", SETTINGS)
    z.writestr("word/numbering.xml", NUMBERING)

print(f"Created: {OUT}")
