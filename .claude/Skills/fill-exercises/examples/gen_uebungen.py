#!/usr/bin/env python3
"""Generate filled-out ADAI Modul3 Tag1 Uebungen.docx for FitBuddy — no external deps."""

import zipfile
from xml.sax.saxutils import escape as esc

OUT = "/Users/timo/Library/CloudStorage/OneDrive-BernerFachhochschule/fitbuddy/Kursdokumente/Architektur/ADAI Modul3 Tag1 Uebungen.docx"

# ── XML helpers ────────────────────────────────────────────────────────────────

def h(level, text):
    sizes = {1: "32", 2: "26", 3: "24"}
    sz = sizes.get(level, "24")
    return (
        f'<w:p><w:pPr><w:pStyle w:val="Heading{level}"/>'
        f'<w:spacing w:before="320" w:after="80"/></w:pPr>'
        f'<w:r><w:t>{esc(text)}</w:t></w:r></w:p>'
    )

def p(text="", bold=False, italic=False, color=None, size=None, indent=0):
    rpr_parts = []
    if bold:
        rpr_parts += ["<w:b/><w:bCs/>"]
    if italic:
        rpr_parts += ["<w:i/><w:iCs/>"]
    if color:
        rpr_parts += [f'<w:color w:val="{color}"/>']
    if size:
        rpr_parts += [f'<w:sz w:val="{size}"/><w:szCs w:val="{size}"/>']
    rpr = f'<w:rPr>{"".join(rpr_parts)}</w:rPr>' if rpr_parts else ""
    ind = f'<w:ind w:left="{indent}"/>' if indent else ""
    ppr = f'<w:pPr><w:spacing w:after="100"/>{ind}</w:pPr>'
    return f'<w:p>{ppr}<w:r>{rpr}<w:t xml:space="preserve">{esc(text)}</w:t></w:r></w:p>'

def p_runs(*runs):
    """Paragraph with multiple runs. runs = list of (text, bold, italic, color)"""
    ppr = '<w:pPr><w:spacing w:after="100"/></w:pPr>'
    out = f'<w:p>{ppr}'
    for text, bold, italic, color in runs:
        rpr_parts = []
        if bold:   rpr_parts += ["<w:b/><w:bCs/>"]
        if italic: rpr_parts += ["<w:i/><w:iCs/>"]
        if color:  rpr_parts += [f'<w:color w:val="{color}"/>']
        rpr = f'<w:rPr>{"".join(rpr_parts)}</w:rPr>' if rpr_parts else ""
        out += f'<w:r>{rpr}<w:t xml:space="preserve">{esc(text)}</w:t></w:r>'
    out += '</w:p>'
    return out

def blank():
    return '<w:p><w:pPr><w:spacing w:after="80"/></w:pPr></w:p>'

def divider():
    return (
        '<w:p><w:pPr><w:pBdr>'
        '<w:bottom w:val="single" w:sz="6" w:space="1" w:color="2E74B5"/>'
        '</w:pBdr><w:spacing w:after="60"/></w:pPr></w:p>'
    )

def label_bar(text, color="2E74B5"):
    """Section label / exercise header bar"""
    return (
        f'<w:p><w:pPr>'
        f'<w:shd w:val="clear" w:color="auto" w:fill="{color}"/>'
        f'<w:spacing w:before="200" w:after="100"/>'
        f'<w:ind w:left="120"/>'
        f'</w:pPr>'
        f'<w:r><w:rPr><w:b/><w:bCs/><w:color w:val="FFFFFF"/>'
        f'<w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr>'
        f'<w:t>{esc(text)}</w:t></w:r></w:p>'
    )

def note_box(text):
    """Light-gray instructor note"""
    return (
        f'<w:p><w:pPr>'
        f'<w:shd w:val="clear" w:color="auto" w:fill="F2F2F2"/>'
        f'<w:spacing w:after="80"/>'
        f'<w:ind w:left="180" w:right="180"/>'
        f'</w:pPr>'
        f'<w:r><w:rPr><w:i/><w:iCs/><w:color w:val="595959"/><w:sz w:val="18"/></w:rPr>'
        f'<w:t xml:space="preserve">{esc(text)}</w:t></w:r></w:p>'
    )

def answer_p(text, bold=False):
    """Answer paragraph with light-blue background"""
    b = "<w:b/><w:bCs/>" if bold else ""
    return (
        f'<w:p><w:pPr>'
        f'<w:shd w:val="clear" w:color="auto" w:fill="EBF3FB"/>'
        f'<w:spacing w:after="60"/>'
        f'<w:ind w:left="180" w:right="180"/>'
        f'</w:pPr>'
        f'<w:r><w:rPr>{b}<w:color w:val="1F4E79"/></w:rPr>'
        f'<w:t xml:space="preserve">{esc(text)}</w:t></w:r></w:p>'
    )

def code_p(text):
    """Monospace code / diagram paragraph"""
    return (
        f'<w:p><w:pPr>'
        f'<w:shd w:val="clear" w:color="auto" w:fill="F8F8F8"/>'
        f'<w:spacing w:after="40"/>'
        f'<w:ind w:left="180"/>'
        f'</w:pPr>'
        f'<w:r><w:rPr>'
        f'<w:rFonts w:ascii="Courier New" w:hAnsi="Courier New"/>'
        f'<w:sz w:val="16"/><w:szCs w:val="16"/>'
        f'<w:color w:val="1F1F1F"/>'
        f'</w:rPr>'
        f'<w:t xml:space="preserve">{esc(text)}</w:t></w:r></w:p>'
    )

def _tc(content_xml, header=False, fill=None, width_pct=None):
    shading = ""
    if header:
        shading = '<w:shd w:val="clear" w:color="auto" w:fill="2E74B5"/>'
    elif fill:
        shading = f'<w:shd w:val="clear" w:color="auto" w:fill="{fill}"/>'
    width = f'<w:tcW w:w="{width_pct}" w:type="pct"/>' if width_pct else ""
    return (
        f'<w:tc><w:tcPr>{width}{shading}'
        f'<w:tcBorders>'
        f'<w:top w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
        f'<w:left w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
        f'<w:bottom w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
        f'<w:right w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
        f'</w:tcBorders></w:tcPr>'
        f'{content_xml}</w:tc>'
    )

def _cell_p(text, header=False, answer=False, bold=False, italic=False):
    """Single paragraph inside a table cell"""
    rpr_parts = []
    if header or bold:
        rpr_parts += ["<w:b/><w:bCs/>"]
    if italic:
        rpr_parts += ["<w:i/><w:iCs/>"]
    if header:
        rpr_parts += ['<w:color w:val="FFFFFF"/>']
    elif answer:
        rpr_parts += ['<w:color w:val="1F4E79"/>']
    rpr = f'<w:rPr>{"".join(rpr_parts)}</w:rPr>' if rpr_parts else ""
    fill_shd = ""
    if answer:
        fill_shd = '<w:shd w:val="clear" w:color="auto" w:fill="EBF3FB"/>'
    return (
        f'<w:p><w:pPr>{fill_shd}'
        f'<w:spacing w:before="60" w:after="60"/></w:pPr>'
        f'<w:r>{rpr}<w:t xml:space="preserve">{esc(text)}</w:t></w:r></w:p>'
    )

def _cell_lines(lines, answer=False, bold_first=False):
    """Multiple paragraphs inside a table cell"""
    out = ""
    fill_shd = '<w:shd w:val="clear" w:color="auto" w:fill="EBF3FB"/>' if answer else ""
    for i, line in enumerate(lines):
        bold = bold_first and i == 0
        rpr_parts = []
        if bold: rpr_parts += ["<w:b/><w:bCs/>"]
        if answer: rpr_parts += ['<w:color w:val="1F4E79"/>']
        rpr = f'<w:rPr>{"".join(rpr_parts)}</w:rPr>' if rpr_parts else ""
        out += (
            f'<w:p><w:pPr>{fill_shd}'
            f'<w:spacing w:before="40" w:after="40"/></w:pPr>'
            f'<w:r>{rpr}<w:t xml:space="preserve">{esc(line)}</w:t></w:r></w:p>'
        )
    return out

def tbl_row(*cells, header=False, answer=False):
    """Simple single-line row. cells = list of strings."""
    tcs = ""
    for c in cells:
        inner = _cell_p(str(c), header=header, answer=answer)
        fill = "EBF3FB" if (answer and not header) else None
        tcs += _tc(inner, header=header, fill=fill)
    return f'<w:tr>{tcs}</w:tr>'

def tbl_row_ml(*cells, answer=False):
    """Multi-line row. cells = list of (line1, line2, ...) or plain strings."""
    tcs = ""
    for c in cells:
        if isinstance(c, (list, tuple)):
            inner = _cell_lines(c, answer=answer)
        else:
            inner = _cell_p(str(c), answer=answer)
        fill = "EBF3FB" if answer else None
        tcs += _tc(inner, fill=fill)
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

def sub_heading(text):
    return (
        f'<w:p><w:pPr><w:spacing w:before="200" w:after="60"/></w:pPr>'
        f'<w:r><w:rPr><w:b/><w:bCs/><w:color w:val="2E74B5"/>'
        f'<w:sz w:val="22"/></w:rPr>'
        f'<w:t>{esc(text)}</w:t></w:r></w:p>'
    )

# ── Document body ──────────────────────────────────────────────────────────────
body = []

# ── Title ─────────────────────────────────────────────────────────────────────
body += [
    '<w:p><w:pPr><w:pStyle w:val="Title"/><w:spacing w:after="80"/></w:pPr>'
    '<w:r><w:t>FitBuddy — Architektur mit AI</w:t></w:r></w:p>',
    p("CAS Application Development with AI (ADAI) · 2026  ·  Modul 3, Tag 1", italic=True, color="595959"),
    p("Ausgefüllte Übungen  ·  BFH Biel  ·  Ilja Rasin", italic=True, color="595959"),
    blank(),
    note_box(
        "Dieses Dokument enthält alle drei Übungen (Ü1–Ü3) mit vorausgefüllten Antworten für das FitBuddy-Projekt. "
        "Blau hinterlegte Felder = unsere Antworten. Grau hinterlegter Text = ursprüngliche Aufgabenstellung."
    ),
    blank(),
]

# ══════════════════════════════════════════════════════════════════════════════
# Ü1 — Quality Attributes
# ══════════════════════════════════════════════════════════════════════════════
body += [
    label_bar("Ü1 · Quality Attributes für FitBuddy   ·   09:15 – 10:00"),
    blank(),
    note_box(
        "Quality Attributes (QA) sind nicht-funktionale Anforderungen — sie bestimmen WIE das System funktioniert, "
        "nicht WAS es tut. Sie sind die eigentlichen Architektur-Treiber."
    ),
    blank(),
]

# Teil 1
body += [
    sub_heading("Teil 1 · Quality Attributes identifizieren"),
    p("Welche QAs sind für FitBuddy relevant — direkt abgeleitet aus den Requirements (REQUIREMENTS.md)?", italic=True),
    blank(),
    tbl(
        tbl_row("Quality Attribute", "Konkretes Requirement aus FitBuddy", "Warum wichtig?", header=True),
        tbl_row_ml(
            "Performance",
            ["US-1 AC2: Dashboard-Load < 3s nach Kaltstart.",
             "US-3 AC1: Spinner sofort nach Tap, Cancel-Button nach 30s."],
            ["Träge AI-Analyse oder langsamer Start zerstören den «on demand»-Charakter. "
             "Performance ist für den User das wahrnehmbare Qualitätsmerkmal Nr. 1."],
            answer=True,
        ),
        tbl_row_ml(
            "Scalability",
            ["— (nicht relevant)"],
            ["Kein Backend, kein Mehrnutzer-Betrieb. Für eine Einzelnutzer-iOS-App im PoC kein Architektur-Treiber."],
            answer=True,
        ),
        tbl_row_ml(
            "Security",
            ["US-1: Keys ausschliesslich in iOS Keychain (kSecAttrAccessibleWhenUnlockedThisDeviceOnly).",
             "US-4 AC4/AC5: nDSG-Consent für Drittlandübermittlung an Anthropic (USA).",
             "NFR: Keine User-Daten auf eigenen Servern."],
            ["Trainingsdaten sind Gesundheitsdaten (nDSG Art. 5 lit. c). Das Kernversprechen "
             "«deine Daten verlassen nie dein Gerät» ist selbst ein Security-QA. Verlust = Vertrauensbruch."],
            answer=True,
        ),
        tbl_row_ml(
            "Reliability",
            ["US-2 AC2: Offline-Cache mit sichtbarem Sync-Zeitstempel.",
             "US-3 AC1: 30s Timeout + Cancel-Button für Claude-API.",
             "US-10: Pull-to-Refresh mit Cache-Fallback.",
             "US-1 AC3: HTTP 401 → Keychain löschen, kein stilles Weiterlaufen."],
            ["Hevy-API hat explizit «keine Garantien». Claude-Calls können >10s dauern. "
             "Leerer Dashboard-Screen = sofortiger Deinstallationsgrund."],
            answer=True,
        ),
        tbl_row_ml(
            "Maintainability",
            ["ADR-3: FitnessConnector-Protocol vor erstem Hevy-Connector implementieren.",
             "ADR-5: Bedrock-Migrationspfad (eu-central-1) für v1.0 vorbereiten.",
             "Normalisiertes Activity-Datenmodell für alle Quellen."],
            ["Strava (v1.1) und Bedrock-Migration (v1.0) sind dokumentierte Roadmap-Items. "
             "Ohne Abstraktion = Breaking Change bei jeder Erweiterung."],
            answer=True,
        ),
        tbl_row_ml(
            "Testability",
            ["Implizit durch FitnessConnector-Protocol: Mock-Connector für Tests ohne echte API.",
             "Dependency Injection über Protocol-Typen."],
            ["Hevy- und Claude-API können im CI nicht aufgerufen werden. "
             "Ohne testbare Seams sind alle Komponenten nur manuell prüfbar."],
            answer=True,
        ),
    ),
    blank(),
]

# Teil 2
body += [
    sub_heading("Teil 2 · AI analysiert unsere Quality Attributes"),
    note_box(
        "Prompt: Alle 12 User Stories + NFRs aus REQUIREMENTS.md + Architekturkontext wurden als Input verwendet."
    ),
    blank(),
    p("Top 3 QAs laut AI — und warum:", bold=True),
    blank(),
]

qa_top3 = [
    (
        "#1 — Security / Privacy",
        [
            "Warum kritisch: FitBuddy verarbeitet Gesundheitsdaten (nDSG Art. 5 lit. c). "
            "Ein kompromittierter Hevy-API-Key gewährt Zugang zur vollständigen Trainingshistorie. "
            "Der Wettbewerbsvorteil «kein Backend» ist nur glaubwürdig, wenn die lokale Speicherung wirklich sicher ist. "
            "Dazu kommt die Drittlandübermittlung an Anthropic (USA) ohne Angemessenheitsbeschluss — konkretes Rechtsrisiko.",
            "Architektonische Massnahmen: Keychain-Attribut kSecAttrAccessibleWhenUnlockedThisDeviceOnly (kein iCloud-Sync, "
            "kein Zugriff bei gesperrtem Gerät). Certificate Pinning für Hevy- und Claude-API-Calls. Kein Logging von Key-Material. "
            "Consent-Screen mit versioniertem Zeitstempel im Keychain (US-4 AC5).",
            "Wenn ignoriert: Rechtliche Haftung nach nDSG. Verlust des Nutzervertrauens beim ersten öffentlichen Keychain-Leak. "
            "App-Store-Ablehnung durch Apple bei fehlerhaftem Privacy-Manifest.",
        ]
    ),
    (
        "#2 — Reliability",
        [
            "Warum kritisch: Beide API-Abhängigkeiten (Hevy, Claude) sind ausserhalb der Kontrolle des Teams. "
            "Hevy hat «no guarantees». Claude-Calls können aufgrund von Rate Limits oder Netzproblemen scheitern. "
            "Ein leerer Dashboard-Screen beim Öffnen der App ist ein sofortiger Deinstallationsgrund.",
            "Architektonische Massnahmen: Offline-First — Cache-Layer (CoreData) wird bei jedem erfolgreichen Sync aktualisiert. "
            "UI zeigt immer Daten (Cache) + Staleness-Indikator. 401-Handler löscht Key und startet Onboarding — kein stilles Scheitern. "
            "30s Claude-Timeout mit explizitem Cancel-Button.",
            "Wenn ignoriert: Jeder Hevy-Ausfall = leere App. Jeder Claude-Timeout = hängendes Spinner-UI. "
            "Nutzer verliert Vertrauen in die Datenbasis für AI-Empfehlungen.",
        ]
    ),
    (
        "#3 — Maintainability",
        [
            "Warum kritisch: Strava (v1.1) und Bedrock-Migration (v1.0) sind dokumentierte Roadmap-Items, keine Optionen. "
            "Ohne Abstraktion ist beides ein Breaking Change. Das FitnessConnector-Protocol ist die einzige Stelle, "
            "die verhindert, dass HevyConnector-Code in Dashboard- und AI-Logik verwächst.",
            "Architektonische Massnahmen: FitnessConnector-Protocol vollständig implementieren bevor HevyConnector gebaut wird. "
            "Normalisiertes Activity-Modell als einzige Datenstruktur, die Dashboard und AI-Engine sehen. "
            "ADRs für alle grossen Entscheide (bereits: ADR-1 bis ADR-5).",
            "Wenn ignoriert: Strava-Integration berührt HevyConnector + Dashboard + AI-Prompt. "
            "Bedrock-Migration berührt jeden API-Call statt nur einen Wrapper.",
        ]
    ),
]

for title, lines in qa_top3:
    body += [answer_p(title, bold=True)]
    for line in lines:
        body += [answer_p("    " + line)]
    body += [blank()]

# Teil 3
body += [
    sub_heading("Teil 3 · Teamdiskussion"),
    blank(),
    p_runs(("Stimmt ihr mit AI überein? ", True, False, None),
           ("Ja. ", False, True, "2E74B5"),
           ("Security > Reliability > Maintainability deckt sich mit den bestehenden ADRs. "
            "AI würde Scalability erwähnen — wir widersprechen: kein Backend, kein Mehrnutzer-Betrieb. "
            "Scalability ist für eine Einzelnutzer-iOS-App im PoC kein Architektur-Treiber.", False, False, None)),
    blank(),
    p_runs(("Welcher QA ist technisch am schwierigsten? ", True, False, None),
           ("Reliability — konkret der Offline-First-Cache. ", False, True, "2E74B5"),
           ("Die Kombination aus «gecachte Daten anzeigen + Staleness-Banner + 401-Handling + "
            "Pull-to-Refresh-Fehlerfall» sind vier separate Zustände, die alle korrekt behandelt werden müssen.", False, False, None)),
    blank(),
    p_runs(("Wichtigstes Takeout: ", True, False, None),
           ("Security ist bei FitBuddy kein «auch noch» — es ist die Produktaussage. "
            "Jede Architekturentscheidung, die Keychain-Daten auf einen fremden Server bringt, "
            "zerstört den Core Value Prop.", False, False, None)),
    blank(),
    p_runs(("Was wir ändern: ", True, False, None),
           ("Certificate Pinning war in ARCHITECTURE.md nicht explizit erwähnt — "
            "als NFR ergänzen (einziger verbleibender Angriffsvektor bei kompromittiertem Netzwerk).", False, False, None)),
    blank(),
]

# ══════════════════════════════════════════════════════════════════════════════
# Ü2 — ADR schreiben
# ══════════════════════════════════════════════════════════════════════════════
body += [
    divider(),
    label_bar("Ü2 · Architecture Decision Record schreiben   ·   10:15 – 11:00"),
    blank(),
    note_box(
        "Ein ADR dokumentiert eine Architektur-Entscheidung — damit zukünftige Entwickler verstehen, "
        "warum so gebaut wurde. Format: Titel · Status · Kontext · Entscheidung · Konsequenzen."
    ),
    blank(),
]

# Teil 1
body += [
    sub_heading("Teil 1 · Wichtigste Entscheidung identifizieren"),
    blank(),
    tbl(
        tbl_row("Feld", "Antwort FitBuddy", header=True),
        tbl_row_ml(
            "Unsere Entscheidung für den ADR",
            ["Kein Backend-Proxy im PoC — direkter Claude-API-Call vom iOS-Client.",
             "Dies ist die architektonisch folgenreichste Entscheidung: Sie bestimmt Sicherheitsmodell, "
             "Privacy-Versprechen, Infrastrukturaufwand und den Migrationspfad zu v1.0."],
            answer=True,
        ),
        tbl_row_ml(
            "Alternativen abgewogen",
            ["A: Serverless Function (Vercel / Supabase Edge) als schlanker Proxy",
             "B: AWS Lambda in eu-central-1 (entkoppelt Client vom Claude-Key, löst nDSG-Problem)",
             "C: Direkter Call vom Client — gewählte Option"],
            answer=True,
        ),
    ),
    blank(),
]

# Teil 2 — ADR
body += [
    sub_heading("Teil 2 · ADR-001: Kein Backend-Proxy für Claude-API-Calls im PoC"),
    blank(),
    tbl(
        tbl_row("Feld", "Inhalt", header=True),
        tbl_row_ml(
            "Titel",
            ["ADR-001: Kein Backend-Proxy für Claude-API-Calls im PoC"],
            answer=True,
        ),
        tbl_row_ml(
            "Status",
            ["Accepted"],
            answer=True,
        ),
        tbl_row_ml(
            "Kontext",
            ["FitBuddy ruft die Claude API auf, um AI-Progressionsempfehlungen zu generieren. "
             "Trainingsdaten (Gesundheitsdaten nach nDSG) werden dabei an Anthropic Inc. (USA) übertragen. "
             "Best Practice für Client-Apps wäre ein serverseitiger Proxy, der den API-Key kapselt. "
             "Das PoC-Team hat 3 Monate Zeit, 2–3 Devs, kein Infra-Know-how für serverlose Backends. "
             "Die Zielgruppe (Marcus) verwaltet bereits API-Keys für Hevy Pro — Credentials sind keine Hürde."],
            answer=True,
        ),
        tbl_row_ml(
            "Entscheidung",
            ["Wir rufen die Claude API direkt vom iOS-Client auf. Der Claude API-Key wird im iOS Keychain "
             "unter fitbuddy.claude.apikey mit kSecAttrAccessibleWhenUnlockedThisDeviceOnly gespeichert. "
             "Es gibt keinen serverseitigen Proxy im PoC."],
            answer=True,
        ),
        tbl_row_ml(
            "Positive Konsequenzen",
            ["+ Kein Backend → kein Betrieb, keine Kosten, keine Infra-Komplexität im PoC",
             "+ Deployment-Scope bleibt rein iOS — kein zweites System zu deployen und zu warten",
             "+ Privacy-Versprechen «keine Daten auf eigenen Servern» bleibt vollständig gültig",
             "+ Entwicklungszeit für Backend entfällt komplett (~1 Sprint gespart)",
             "+ Keychain schützt den Key vor anderen Apps und bei gesperrtem Gerät"],
            answer=True,
        ),
        tbl_row_ml(
            "Negative Konsequenzen",
            ["− Claude API-Key liegt auf dem Gerät — bei Gerätekompromittierung exponiert",
             "− Kein serverseitiger Rate-Limit-Schutz → Client muss Cooldown selbst erzwingen (NFR: max. 1 Analyse/6h)",
             "− Direkter API-Call exponiert Anthropic als Drittempfänger in der Netzwerkkommunikation",
             "− AVV/DPA mit Anthropic muss auf Team-Ebene abgeschlossen werden (nicht durch Endnutzer abdeckbar)",
             "− Bei kompromittiertem Key ist die Rotation manuell: Nutzer muss Key selbst im Onboarding neu eingeben",
             "− Vor v1.0-Launch obligatorisches Revisit → Migration zu AWS Bedrock eu-central-1 (Frankfurt)"],
            answer=True,
        ),
    ),
    blank(),
]

# Teil 3
body += [
    sub_heading("Teil 3 · AI reviewt das ADR"),
    blank(),
    p("Was AI an unserem ADR verbessern würde:", bold=True),
    blank(),
    answer_p("Was nicht bedacht wurde:  Der Cooldown (max. 1 Analyse/6h) ist im ADR nicht als direkte "
             "Konsequenz des fehlenden Proxys erwähnt — dabei ist er genau das. Ein Proxy könnte "
             "Rate-Limiting serverseitig erzwingen und wäre robuster gegen clientseitige Umgehung.", bold=False),
    blank(),
    answer_p("Fehlende Alternative:  AWS Bedrock direkt vom iOS-Client (ohne Proxy) mit AWS Signature V4 "
             "wurde nicht explizit bewertet. Das würde das USA-Problem lösen, erhöht aber Client-Komplexität erheblich."),
    blank(),
    answer_p("Grösstes Risiko laut AI:  Anthropic hat keinen publizierten AVV/DPA-Prozess für "
             "Einzelpersonen/Teams. Falls dieser nicht abgeschlossen werden kann, entfällt die "
             "Rechtsgrundlage für die Drittlandübermittlung im PoC."),
    blank(),
    p("Was wir am ADR noch ändern:", bold=True),
    blank(),
    tbl(
        tbl_row("Punkt", "Massnahme", header=True),
        tbl_row_ml(
            "Cooldown als Konsequenz ergänzen",
            ["«NFR max. 1 Analyse/6h ist eine direkte Kompensation für fehlenden serverseitigen Rate-Limiter» "
             "in die negativen Konsequenzen aufnehmen."],
            answer=True,
        ),
        tbl_row_ml(
            "Manuelle Key-Rotation als Risiko",
            ["Explizit nennen: Bei kompromittiertem Keychain-Eintrag gibt es keinen serverseitigen Kill-Switch."],
            answer=True,
        ),
        tbl_row_ml(
            "AVV/DPA-Prozess klären",
            ["Vor Modul 3: Anthropic-Konsolen-Vertrag prüfen, ob AVV für Teams/Akademiker verfügbar ist."],
            answer=True,
        ),
    ),
    blank(),
]

# ══════════════════════════════════════════════════════════════════════════════
# Ü3 — C4 Diagramme
# ══════════════════════════════════════════════════════════════════════════════
body += [
    divider(),
    label_bar("Ü3 · C4 Diagramme — Context + Container   ·   11:15 – 12:00"),
    blank(),
    note_box(
        "C4 Level 1 (System Context): Euer System als schwarze Box — wer interagiert damit von aussen? "
        "C4 Level 2 (Container): Was läuft wo? Welche Technologien?"
    ),
    blank(),
]

# Teil 1 — C1
body += [
    sub_heading("Teil 1 · C1 System Context Diagram"),
    blank(),
    p("System-Name (Mitte):", bold=True),
    answer_p("FitBuddy — AI-gestützter Trainingsassistent  ·  Native iOS App"),
    blank(),
    p("Nutzertypen:", bold=True),
    answer_p("Marcus Huber — Technikaffiner Power-User (Hevy Pro Account, mehrere Fitness-Apps)"),
    answer_p("Jana Vogel — Krafttraining-Einsteigerin (kein technischer Hintergrund, will Empfehlungen ohne Selbstinterpretation)"),
    blank(),
    p("Externe Systeme:", bold=True),
    answer_p("Hevy REST API — primäre Datenquelle (Kraft-Trainings, Exercises, Sets, Volumen)"),
    answer_p("Claude API (Anthropic, USA) — AI-Inference für Progressionsempfehlungen (POST /v1/messages)"),
    answer_p("Strava API (v1.1, geplant) — OAuth, Ausdauerdaten (Cardio-Aktivitäten)"),
    blank(),
    p("C1 Diagramm (ASCII):", bold=True),
    blank(),
]

c1_lines = [
    "  [Marcus Huber]         [Jana Vogel]",
    "  Power-User             Einsteigerin",
    "        |                     |",
    "        +----------+----------+",
    "                   |",
    "                   v",
    "         +-------------------+",
    "         |    FitBuddy       |   <-- iOS Native App",
    "         |   iOS App         |       Trainings-Aggregator",
    "         |                   |       + AI-Empfehlungen",
    "         +----+----------+---+",
    "              |          |",
    "   +----------+          +----------------+",
    "   v                                      v",
    "+-------------+               +--------------------+",
    "| Hevy API    |               | Claude API         |",
    "| REST        |               | Anthropic, USA     |",
    "| /v1/workouts|               | POST /v1/messages  |",
    "+-------------+               +--------------------+",
    "",
    "   (v1.1 geplant)",
    "+-------------+",
    "| Strava API  |",
    "| OAuth REST  |",
    "+-------------+",
]
for line in c1_lines:
    body += [code_p(line)]

body += [
    blank(),
    p("Überraschungen — was AI gefunden hat, das wir vergessen hatten:", bold=True),
    blank(),
    tbl(
        tbl_row("Vergessener Akteur", "Implikation", header=True),
        tbl_row_ml(
            "Apple HealthKit",
            ["Als «offene Frage» bekannt, aber im C1 nicht modelliert. "
             "Wenn Schlaf/HRV/Ruheherzrate in Scope kommen, ist HealthKit ein externer Akteur "
             "(auch wenn er lokal auf dem Gerät läuft — eigene Permission-Domäne)."],
            answer=True,
        ),
        tbl_row_ml(
            "Hevy-Nutzerkonto (hevy.com)",
            ["Streng genommen ein vom API getrenntes System: der User richtet den API-Key dort ein. "
             "Relevant für Onboarding (US-4 AC1: Screenshot-Anleitung, wo in Hevy der Key zu finden ist)."],
            answer=True,
        ),
        tbl_row_ml(
            "TestFlight / Apple App Store",
            ["Als Distributions-System nicht im C1, aber technisch ein Deployment-Akteur. "
             "Relevant für Privacy Manifest und App-Review-Anforderungen."],
            answer=True,
        ),
    ),
    blank(),
]

# Teil 2 — C2
body += [
    sub_heading("Teil 2 · C2 Container Diagram"),
    blank(),
    p("C2 Diagramm (ASCII):", bold=True),
    blank(),
]

c2_lines = [
    "+──────────────────── iOS App ────────────────────────────────────+",
    "|                                                                 |",
    "|  +--------------+  +--------------+  +----------------------+  |",
    "|  |OnboardingView|  |DashboardView |  |  AIAnalysisView      |  |",
    "|  |  SwiftUI     |  |  SwiftUI     |  |  SwiftUI             |  |",
    "|  | Key-Eingabe  |  | 90d Übersicht|  | Analyse-Button       |  |",
    "|  | Consent-Scrn.|  | Vol./Muskeln |  | Empfehlung anzeigen  |  |",
    "|  +------+-------+  +------+-------+  +---------+------------+  |",
    "|         |                 |                    |                |",
    "|  +------+-----------------+--------------------+------------+   |",
    "|  |              Connector Layer (Swift Protocol)             |   |",
    "|  |     connect / validate / fetchActivities / disconnect     |   |",
    "|  |   +--------------------+   +-------------------------+   |   |",
    "|  |   | HevyConnector      |   | StravaConnector (Stub)  |   |   |",
    "|  |   | Swift / URLSession |   | v1.1 — nicht impl.      |   |   |",
    "|  |   +--------+-----------+   +-------------------------+   |   |",
    "|  +------------+--------------------------------------------------+   |",
    "|               |                                                  |",
    "|  +------------+------------------+  +------------------------+  |",
    "|  | Activity Cache (CoreData)     |  |    iOS Keychain        |  |",
    "|  | [Activity], sync timestamp    |  | fitbuddy.hevy.apikey   |  |",
    "|  | AI feedback (helpful/not)     |  | fitbuddy.claude.apikey |  |",
    "|  +-------------------------------+  | consent version+date   |  |",
    "|                                     +------------------------+  |",
    "|  +------------------------------------------------------+        |",
    "|  | AI Analysis Engine (Swift / async-await)             |        |",
    "|  | Liest Cache -> baut Prompt -> ruft Claude API auf    |        |",
    "|  | Cooldown-Logik: max. 1 Call / 6h (lokal erzwungen)  |        |",
    "|  | Prompt-Builder (eigene, testbare Komponente)         |        |",
    "|  +------------------------------------------------------+        |",
    "+─────────────────────────────────────────────────────────────────+",
    "         |  HTTPS/REST                        |  HTTPS/REST",
    "         v                                    v",
    "+------------------+               +----------------------+",
    "|  Hevy API        |               |  Claude API          |",
    "|  REST            |               |  Anthropic, USA      |",
    "|  /v1/workouts    |               |  POST /v1/messages   |",
    "+------------------+               +----------------------+",
]
for line in c2_lines:
    body += [code_p(line)]

body += [blank()]

body += [
    p("Container-Entscheidungen (finalisiert):", bold=True),
    blank(),
    tbl(
        tbl_row("Container", "Technologie", "Aufgabe", "Kommuniziert mit", header=True),
        tbl_row_ml(
            "OnboardingView / DashboardView / AIAnalysisView",
            ["SwiftUI"],
            ["UI-Rendering, Nutzereingaben, Zustandsanzeige"],
            ["Connector Layer, Keychain, AI Engine"],
            answer=True,
        ),
        tbl_row_ml(
            "HevyConnector",
            ["Swift / URLSession"],
            ["REST-Calls zu Hevy API, Normalisierung auf Activity-Modell, 401-Handling"],
            ["Hevy API (extern), Activity Cache"],
            answer=True,
        ),
        tbl_row_ml(
            "StravaConnector",
            ["Swift (Stub / Interface)"],
            ["Platzhalter; OAuth-Flow + Normalisierung in v1.1"],
            ["— (nicht impl. im PoC)"],
            answer=True,
        ),
        tbl_row_ml(
            "Activity Cache",
            ["CoreData"],
            ["Persistenz normalisierter Activity-Daten, Sync-Zeitstempel, AI-Feedback-Flags"],
            ["HevyConnector (write), Views + AI Engine (read)"],
            answer=True,
        ),
        tbl_row_ml(
            "iOS Keychain",
            ["Security.framework"],
            ["Sichere Credential-Speicherung, Consent-Version + Datum, Cooldown-Timestamp"],
            ["OnboardingView (write), alle Komponenten (read)"],
            answer=True,
        ),
        tbl_row_ml(
            "AI Analysis Engine + Prompt-Builder",
            ["Swift / async-await"],
            ["Prompt-Konstruktion aus Activity-Daten, Claude-API-Call, Cooldown-Erzwingung"],
            ["Activity Cache (read), Claude API (extern)"],
            answer=True,
        ),
    ),
    blank(),
    p("Überraschungen und Änderungen nach AI-Empfehlung:", bold=True),
    blank(),
    tbl(
        tbl_row("Überraschung", "Entscheid", header=True),
        tbl_row_ml(
            "Prompt-Builder als eigener Container",
            ["AI würde Prompt-Builder aus AI Analysis Engine herauslösen — sinnvoll, "
             "weil er separat testbar ist (Unit-Test ohne Claude-API-Call). "
             "Entscheid: Prompt-Builder als eigene, mockbare Komponente innerhalb der AI Analysis Engine."],
            answer=True,
        ),
        tbl_row_ml(
            "CoreData vs. UserDefaults",
            ["AI empfiehlt CoreData für Activity-Daten (Relationsmodell: Activity → Exercise → ExerciseSet). "
             "UserDefaults nur für Sync-Zeitstempel, Cooldown-Timer. Entscheid: CoreData für Activity-Persistenz."],
            answer=True,
        ),
        tbl_row_ml(
            "Cooldown-Persistenz explizit modellieren",
            ["Wo wird der 6h-Cooldown-State persistiert? Nicht in-memory (reset bei App-Kill). "
             "Entscheid: UserDefaults für lastAnalysisTimestamp — einfach, ausreichend, kein Sicherheitsrisiko."],
            answer=True,
        ),
    ),
    blank(),
]

# Teil 3 — Plenum
body += [
    sub_heading("Teil 3 · Plenum-Vorbereitung (5 Min)"),
    blank(),
    tbl(
        tbl_row("Frage", "FitBuddy-Antwort", header=True),
        tbl_row_ml(
            "C1: Wer interagiert mit dem System?",
            ["2 Nutzer-Personas (Marcus, Jana) + Hevy API + Claude API (Anthropic). "
             "Strava in v1.1. Kein Backend-Betreiber, kein Admin, kein Support-System."],
            answer=True,
        ),
        tbl_row_ml(
            "C2: Wichtigste Technologie-Entscheidung?",
            ["Kein Backend-Container — alles läuft on-device. "
             "CoreData für den Activity Cache (Relationsmodell, Queries, Migrations-Support für Strava-Daten in v1.1). "
             "FitnessConnector-Protocol als einzige Abstraktion zwischen UI und Datenquellen."],
            answer=True,
        ),
        tbl_row_ml(
            "ADR: Was haben wir entschieden?",
            ["ADR-001: Kein Backend-Proxy — direkter Claude-API-Call. Accepted für PoC. "
             "Obligatorisches Revisit vor v1.0 → Migration zu AWS Bedrock eu-central-1 (Frankfurt)."],
            answer=True,
        ),
        tbl_row_ml(
            "Überraschung: Was hat AI gefunden?",
            ["Certificate Pinning war in der ursprünglichen Architektur nicht explizit erwähnt. "
             "Ist aber der einzige verbleibende Angriffsvektor bei einem kompromittierten Netzwerk, "
             "wenn API-Keys im Keychain liegen. Als NFR ergänzen."],
            answer=True,
        ),
    ),
    blank(),
]

# Footer
body += [
    divider(),
    p("CAS ADAI 2026  ·  BFH Biel  ·  Modul 3 Tag 1  ·  Ilja Rasin  ·  FitBuddy-Projekt", italic=True, color="595959"),
]

# ── Assemble XML ───────────────────────────────────────────────────────────────

DOCUMENT_XML = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document
  xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
  xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml"
  mc:Ignorable="w14">
<w:body>
''' + "\n".join(body) + '''
<w:sectPr>
  <w:pgSz w:w="11906" w:h="16838"/>
  <w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134"
           w:header="709" w:footer="709" w:gutter="0"/>
</w:sectPr>
</w:body>
</w:document>'''

CONTENT_TYPES = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml"
    ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml"
    ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
  <Override PartName="/word/settings.xml"
    ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>
  <Override PartName="/word/numbering.xml"
    ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
</Types>'''

RELS = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1"
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
    Target="word/document.xml"/>
</Relationships>'''

WORD_RELS = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1"
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles"
    Target="styles.xml"/>
  <Relationship Id="rId2"
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings"
    Target="settings.xml"/>
  <Relationship Id="rId3"
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering"
    Target="numbering.xml"/>
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
        <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/>
        <w:sz w:val="21"/>
        <w:szCs w:val="21"/>
      </w:rPr>
    </w:rPrDefault>
    <w:pPrDefault>
      <w:pPr>
        <w:spacing w:after="120" w:line="240" w:lineRule="auto"/>
      </w:pPr>
    </w:pPrDefault>
  </w:docDefaults>

  <w:style w:type="paragraph" w:styleId="Normal">
    <w:name w:val="Normal"/>
    <w:pPr><w:spacing w:after="100"/></w:pPr>
    <w:rPr>
      <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/>
      <w:sz w:val="21"/><w:szCs w:val="21"/>
    </w:rPr>
  </w:style>

  <w:style w:type="paragraph" w:styleId="Title">
    <w:name w:val="Title"/>
    <w:pPr><w:spacing w:before="0" w:after="200"/><w:jc w:val="left"/></w:pPr>
    <w:rPr>
      <w:rFonts w:ascii="Calibri Light" w:hAnsi="Calibri Light"/>
      <w:color w:val="2E74B5"/>
      <w:sz w:val="52"/><w:szCs w:val="52"/>
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
      <w:sz w:val="32"/><w:szCs w:val="32"/>
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
      <w:sz w:val="26"/><w:szCs w:val="26"/>
    </w:rPr>
  </w:style>

  <w:style w:type="paragraph" w:styleId="Heading3">
    <w:name w:val="Heading 3"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr>
      <w:keepNext/>
      <w:spacing w:before="200" w:after="60"/>
      <w:outlineLvl w:val="2"/>
    </w:pPr>
    <w:rPr>
      <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/>
      <w:b/><w:bCs/>
      <w:color w:val="2E74B5"/>
      <w:sz w:val="24"/><w:szCs w:val="24"/>
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
        <w:top    w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>
        <w:left   w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>
        <w:bottom w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>
        <w:right  w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>
        <w:insideH w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>
        <w:insideV w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>
      </w:tblBorders>
    </w:tblPr>
    <w:rPr><w:sz w:val="20"/><w:szCs w:val="20"/></w:rPr>
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

print(f"✓ Erstellt: {OUT}")
