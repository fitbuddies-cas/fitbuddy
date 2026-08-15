"""FitBuddy Review-Agent — Übung 2: Wie entscheidet ein Agent, welches Tool er nimmt?

`fitbuddy_agent.py` hatte genau EIN Tool. Die Entscheidung war damit trivial.
Hier gibt es ACHT Tools, die sich absichtlich überschneiden. Interessant ist
nicht mehr das Ergebnis, sondern der Weg dorthin:

    python project_review_agent.py 2>calls.log

stdout = der Bericht, stderr = jeder einzelne Tool-Aufruf. Das Log ist die Übung.

Zwei Aufgaben, bewusst vermischt:
  1. Deutsche Dokumente finden und auf Rechtschreibung prüfen
  2. Den Swift-Code gegen die Konventionen aus CLAUDE.md prüfen

Der Agent liest nur — er ändert keine Datei.

Die zentrale Lektion steckt im Rechtschreib-Teil: es gibt auf dieser Maschine
kein deutsches Wörterbuch (hunspell fehlt, aspell kennt nur en/fr). Ein
Wörterbuch würde hier ohnehin an "Muskelbelastungsverteilung", "revDSG" oder
"Keychain" scheitern. Also gilt die Arbeitsteilung, um die es bei Agenten geht:

    Das Tool sammelt Kandidaten deterministisch. Das Modell urteilt.
"""

from __future__ import annotations

import asyncio
import json
import re
import sys
from collections import Counter
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent
MODEL = "claude-sonnet-4-6"

SKIP_DIRS = {".git", ".venv", "node_modules", "agent", "Kursdokumente", ".idea", "DerivedData"}

# Fachbegriffe, die selten vorkommen DÜRFEN. Die Liste ist absichtlich kurz:
# Sie soll den offensichtlichen Lärm filtern, nicht die Entscheidung abnehmen.
GLOSSARY = {
    "fitbuddy", "hevy", "strava", "claude", "anthropic", "keychain", "swiftui",
    "xcode", "swift", "testflight", "poc", "adr", "moscow", "revdsg", "ndsg",
    "dsfa", "dpa", "sccs", "bfh", "cas", "adai", "mvvm", "json", "oauth",
    "actor", "connector", "dashboard", "onboarding", "consent", "epic", "story",
    "stories", "backend", "proxy", "token", "tokens", "cardio", "reps", "sets",
}

GERMAN_STOPWORDS = {
    "der", "die", "das", "und", "ist", "für", "mit", "von", "den", "dem", "des",
    "eine", "einen", "einem", "einer", "nicht", "werden", "wird", "sind", "auch",
    "nur", "oder", "aber", "als", "bei", "aus", "nach", "über", "zum", "zur",
    "sich", "kann", "muss", "wenn", "dass", "diese", "dieser", "keine", "durch",
}

ENGLISH_STOPWORDS = {
    "the", "and", "for", "with", "that", "this", "are", "from", "have", "has",
    "not", "but", "you", "your", "all", "can", "will", "into", "when", "which",
    "each", "they", "them", "than", "then", "its", "use", "used", "uses",
}

WORD_RE = re.compile(r"[A-Za-zÄÖÜäöüßéèàç]{3,}")
NON_ENGLISH_CHAR_RE = re.compile(r"[ÄÖÜäöüßéèàçñ]")


# ═══════════════════════════════════════════════════════════════════════════
# Teil A — reine Hilfsfunktionen. Kein LLM, kein SDK, alles deterministisch.
# Genau diese Grenze ist der Lerninhalt: hier unten wird gerechnet, weiter
# unten (im Modell) wird geurteilt.
# ═══════════════════════════════════════════════════════════════════════════


def _relevant_files(pattern: str) -> list[Path]:
    return sorted(
        path
        for path in REPO_ROOT.glob(pattern)
        if not any(part in SKIP_DIRS for part in path.parts)
    )


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def _rel(path: Path) -> str:
    return str(path.relative_to(REPO_ROOT))


def extract_prose(text: str) -> str:
    """Markdown auf reinen Fliesstext reduzieren.

    Codeblöcke, URLs, Inline-Code und HTML fliegen raus — sonst besteht die
    Hälfte der Rechtschreib-Kandidaten aus Variablennamen. Tabellen bleiben
    erhalten (nur die Pipes fallen weg): in REQUIREMENTS.md steckt der meiste
    deutsche Text genau dort, in den Acceptance-Criteria-Tabellen.
    """
    if text.startswith("---"):
        parts = text.split("---", 2)
        if len(parts) == 3:
            text = parts[2]

    text = re.sub(r"```.*?```", " ", text, flags=re.S)
    text = re.sub(r"~~~.*?~~~", " ", text, flags=re.S)
    text = re.sub(r"`[^`]*`", " ", text)
    text = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", text)  # Linktext behalten
    text = re.sub(r"https?://\S+", " ", text)
    text = re.sub(r"<[^>]+>", " ", text)

    lines = []
    for line in text.splitlines():
        if re.fullmatch(r"[\s|:\-+=]*", line):  # Tabellen-Trennzeile
            continue
        line = line.replace("|", " ")
        line = re.sub(r"^\s*#{1,6}\s*", "", line)
        line = re.sub(r"^\s*[>*\-+]\s+", "", line)
        line = line.replace("**", "").replace("*", "").replace("_", " ")
        lines.append(line)
    return "\n".join(lines)


def detect_language(text: str) -> dict:
    """Sprache über Stoppwörter + Umlaute schätzen.

    Gibt bewusst den Score mit zurück, nicht nur das Label — die Sammlung ist
    gemischt (RISK-CLASSIFICATION.md hat einen englischen Titel, design/README.md
    ist Englisch mit deutschen Fragmenten), und ein blosses "de"/"en" würde
    diese Grenzfälle verstecken.
    """
    words = [word.lower() for word in WORD_RE.findall(text)]
    if not words:
        return {"language": "unknown", "german_score": 0.0, "umlauts": 0, "words": 0}

    german_hits = sum(1 for word in words if word in GERMAN_STOPWORDS)
    english_hits = sum(1 for word in words if word in ENGLISH_STOPWORDS)
    total_hits = german_hits + english_hits
    score = german_hits / total_hits if total_hits else 0.0

    if score >= 0.60:
        label = "de"
    elif score <= 0.35:
        label = "en"
    else:
        label = "mixed"

    return {
        "language": label,
        "german_score": round(score, 2),
        "umlauts": len(NON_ENGLISH_CHAR_RE.findall(text)),
        "words": len(words),
    }


def collect_docs() -> list[dict]:
    docs = []
    for path in _relevant_files("**/*.md"):
        prose = extract_prose(_read(path))
        docs.append({"path": _rel(path), "_path": path, **detect_language(prose)})
    return docs


def _edit_distance_at_most(first: str, second: str, limit: int = 2) -> int | None:
    """Levenshtein-Distanz mit frühem Abbruch. None = weiter entfernt als `limit`."""
    if abs(len(first) - len(second)) > limit:
        return None
    previous = list(range(len(second) + 1))
    for index, char_a in enumerate(first, 1):
        current = [index]
        for position, char_b in enumerate(second, 1):
            current.append(
                min(
                    previous[position] + 1,
                    current[position - 1] + 1,
                    previous[position - 1] + (char_a != char_b),
                )
            )
        if min(current) > limit:
            return None
        previous = current
    return previous[-1] if previous[-1] <= limit else None


def _looks_like_inflection(rare: str, common: str) -> bool:
    """Beugung von Tippfehler unterscheiden.

    Deutsch flektiert stark: "abrufen" und "abruft" liegen zwei Editier-
    operationen auseinander und sind beide korrekt. Tippfehler sitzen dagegen
    fast immer im Wortinneren. Regel: steckt der ganze Unterschied in den
    letzten drei Zeichen, ist es Beugung und kein Fehler.
    """
    prefix = 0
    while prefix < min(len(rare), len(common)) and rare[prefix] == common[prefix]:
        prefix += 1
    return max(len(rare), len(common)) - prefix <= 3


# Gemessen am eigenen Korpus: bei Distanz 2 ist praktisch jeder Treffer ein
# Fehlalarm ("Interaktion ~ integration", "Kontrollen ~ controller"), und unter
# 8 Zeichen hat Deutsch zu viele echte Minimalpaare ("fliegen"/"liegen").
# Diese beiden Zahlen sind der Unterschied zwischen 84 und 5 Kandidaten.
MAX_EDIT_DISTANCE = 1
MIN_CANDIDATE_LENGTH = 8


def _nearest_common(word: str, by_length: dict[int, list[str]]) -> tuple[str, int] | None:
    best: tuple[str, int] | None = None
    for length in (len(word) - 1, len(word), len(word) + 1):
        for candidate in by_length.get(length, ()):
            if candidate == word or _looks_like_inflection(word, candidate):
                continue
            distance = _edit_distance_at_most(word, candidate, MAX_EDIT_DISTANCE)
            if distance is not None and (best is None or distance < best[1]):
                best = (candidate, distance)
    return best


def collect_typo_candidates(max_count: int) -> dict:
    """Verwechslungspaare im eigenen Korpus finden.

    Erster Versuch war "seltene Wörter melden" — das ergab 1248 Kandidaten,
    also praktisch den ganzen Wortschatz: Deutsch flektiert zu stark, fast
    jede Verbform kommt genau einmal vor.

    Was tatsächlich trägt: ein seltenes Wort, das genau einen Buchstaben von
    einem häufigen Wort desselben Korpus entfernt liegt. Der Korpus ist damit
    sein eigenes Wörterbuch — "geschätzt" neben "geschützt", "verfolgt" neben
    "erfolgt". Beide Schreibweisen sind echte Wörter, weshalb weder ein
    Rechtschreibprüfer noch ein flüchtiger Leser sie findet; ob an der Stelle
    die richtige steht, verrät nur der Kontext.

    Grenzen: findet keinen durchgängig falsch geschriebenen Begriff (der wäre
    nicht selten), und keinen Fehler ohne korrekten Zwilling im Text.
    """
    counts: Counter[str] = Counter()
    first_seen: dict[str, tuple[str, int, str]] = {}
    scanned = []

    for doc in collect_docs():
        if doc["language"] not in ("de", "mixed"):
            continue
        scanned.append(doc["path"])
        for line_number, line in enumerate(extract_prose(_read(doc["_path"])).splitlines(), 1):
            for word in WORD_RE.findall(line):
                key = word.lower()
                counts[key] += 1
                first_seen.setdefault(key, (doc["path"], line_number, word))

    by_length: dict[int, list[str]] = {}
    for word, count in counts.items():
        if count >= 3 and len(word) >= 5:
            by_length.setdefault(len(word), []).append(word)

    rare = [
        key
        for key, count in counts.items()
        if count <= max_count and len(key) >= MIN_CANDIDATE_LENGTH and key not in GLOSSARY
    ]

    findings = []
    for key in rare:
        match = _nearest_common(key, by_length)
        if match is None:
            continue
        path, line_number, original = first_seen[key]
        findings.append(
            {
                "word": original,
                "count": counts[key],
                "similar_to": match[0],
                "similar_count": counts[match[0]],
                "distance": match[1],
                "file": path,
                "line": line_number,
            }
        )

    findings.sort(key=lambda item: (item["distance"], item["word"].lower()))
    return {
        "scanned_docs": scanned,
        "rare_words_examined": len(rare),
        "candidates": findings[:60],
        "total_candidates": len(findings),
        "note": (
            "Verwechslungspaare, keine bestätigten Fehler: das seltene Wort liegt "
            "einen Buchstaben neben einem häufigen. Beide Schreibweisen sind meist "
            "echte Wörter — welche an dieser Stelle stimmt, entscheidet der Kontext. "
            "Lies die Stelle mit extract_prose nach, bevor du etwas meldest."
        ),
    }


TYPE_DECL_RE = re.compile(
    r"^(?P<indent>[ \t]*)"
    r"(?:public\s+|private\s+|internal\s+|fileprivate\s+|final\s+)*"
    r"(?:class|struct|actor|enum|protocol)\s+(?P<name>\w+)",
    re.M,
)


def _declared_types(text: str, top_level_only: bool = False) -> list[str]:
    """Deklarierte Typen einer Datei.

    Einrückung = Verschachtelung: `enum Failure` innerhalb eines States ist
    kein zweiter Typ in der Datei. Ohne diese Unterscheidung meldet die
    Ein-Typ-pro-Datei-Regel lauter Fehlalarme — und ein Tool, dem man nicht
    trauen kann, ist schlimmer als keins.
    """
    return [
        match.group("name")
        for match in TYPE_DECL_RE.finditer(text)
        if not (top_level_only and match.group("indent"))
    ]


def build_swift_inventory() -> dict:
    """Rohdaten über den Swift-Code — absichtlich KEIN Urteil.

    CLAUDE.md verlangt für jedes ViewModel und jeden Service einen Unit-Test.
    Diese Funktion liefert nur, was da ist; ob die Regel erfüllt ist, entscheidet
    das Modell. Ein Tool, das schon "bestanden" zurückgibt, lässt nichts mehr
    zu entscheiden übrig.
    """
    sources, tests = [], []
    for path in _relevant_files("FitBuddy/**/*.swift"):
        sources.append({"file": _rel(path), "types": _declared_types(_read(path))})
    for path in _relevant_files("FitBuddyTests/**/*.swift"):
        tests.append({"file": _rel(path), "types": _declared_types(_read(path))})

    test_names = {name for entry in tests for name in entry["types"]}
    needs_test = []
    for entry in sources:
        for type_name in entry["types"]:
            if type_name.endswith(("ViewModel", "Service", "Validator")):
                needs_test.append(
                    {
                        "type": type_name,
                        "file": entry["file"],
                        "has_test_class": f"{type_name}Tests" in test_names,
                    }
                )

    return {
        "source_files": len(sources),
        "test_files": len(tests),
        "sources": sources,
        "tests": [entry["file"] for entry in tests],
        "viewmodels_and_services": needs_test,
    }


COMMENT_RE = re.compile(r"^\s*(?://|/\*|\*)")


def scan_comment_language() -> dict:
    findings = []
    for path in _relevant_files("FitBuddy/**/*.swift") + _relevant_files("FitBuddyTests/**/*.swift"):
        for line_number, line in enumerate(_read(path).splitlines(), 1):
            if COMMENT_RE.match(line) and NON_ENGLISH_CHAR_RE.search(line):
                findings.append(
                    {"file": _rel(path), "line": line_number, "text": line.strip()}
                )
    return {
        "rule": "CLAUDE.md: alle Kommentare im iOS-Code auf Englisch",
        "findings": findings,
        "note": (
            "Treffer heisst nur: der Kommentar enthält ein nicht-englisches Zeichen. "
            "Ein zitiertes deutsches UI-Label in einem englischen Satz ist korrekt — "
            "das musst du selbst beurteilen."
        ),
    }


CONVENTION_PATTERNS = {
    "force_unwrap": re.compile(r"\btry!|\bas!|\)!|\]!|\b[a-zA-Z_]\w*!\s*\."),
    "combine": re.compile(r"^\s*import\s+Combine\b", re.M),
    "hardcoded_color": re.compile(r"Color\.(?!fb)[a-z]\w*|Color\(\s*(?:\"|red|green|blue|\.s)"),
}


def scan_conventions() -> dict:
    """Die mechanisch prüfbaren Regeln aus CLAUDE.md."""
    hits: dict[str, list] = {name: [] for name in CONVENTION_PATTERNS}
    multi_type_files = []

    for path in _relevant_files("FitBuddy/**/*.swift"):
        text = _read(path)
        types = _declared_types(text, top_level_only=True)
        if len(types) > 1:
            multi_type_files.append({"file": _rel(path), "types": types})
        for line_number, line in enumerate(text.splitlines(), 1):
            code = line.split("//", 1)[0]
            for name, pattern in CONVENTION_PATTERNS.items():
                if pattern.search(code):
                    hits[name].append(
                        {"file": _rel(path), "line": line_number, "text": line.strip()}
                    )

    return {
        "rules": {
            "force_unwrap": "kein Force-Unwrap (Heuristik, prüfe Treffer nach)",
            "combine": "async/await statt Combine",
            "hardcoded_color": "Farben nur über die FB-Tokens (Color.fb…)",
            "one_type_per_file": "ein Typ pro Datei (Extensions zählen nicht)",
        },
        "force_unwrap": hits["force_unwrap"],
        "combine": hits["combine"],
        "hardcoded_color": hits["hardcoded_color"],
        "multi_type_files": multi_type_files,
    }


def grep_sources(pattern: str, limit: int = 40) -> dict:
    try:
        regex = re.compile(pattern)
    except re.error as error:
        return {"error": f"Ungültiger regulärer Ausdruck: {error}"}

    matches = []
    for path in _relevant_files("FitBuddy/**/*.swift") + _relevant_files("FitBuddyTests/**/*.swift"):
        for line_number, line in enumerate(_read(path).splitlines(), 1):
            if regex.search(line):
                matches.append({"file": _rel(path), "line": line_number, "text": line.strip()})
                if len(matches) >= limit:
                    return {"pattern": pattern, "matches": matches, "truncated": True}
    return {"pattern": pattern, "matches": matches, "truncated": False}


# ═══════════════════════════════════════════════════════════════════════════
# Teil B — der Agent
# ═══════════════════════════════════════════════════════════════════════════

# Import so gekapselt, dass `--selftest` auch ohne installiertes SDK läuft:
# Teil A oben ist reines Python und soll ohne Abhängigkeiten prüfbar bleiben.
try:
    from claude_agent_sdk import (
        AssistantMessage,
        ClaudeAgentOptions,
        ResultMessage,
        TextBlock,
        ToolUseBlock,
        create_sdk_mcp_server,
        query,
        tool,
    )

    SDK_AVAILABLE = True
except ImportError:  # pragma: no cover
    SDK_AVAILABLE = False

    def tool(name, description, schema):  # type: ignore[misc]
        def decorate(function):
            return function

        return decorate


def _ok(payload: dict) -> dict:
    """Rückgabeformat für Tools — identisch zu fitbuddy_agent.py."""
    return {"content": [{"type": "text", "text": json.dumps(payload, ensure_ascii=False)}]}


# ── Schritt 1: Acht Tools definieren ───────────────────────────────────────
# Die Beschreibung ist das, was das Modell zur Auswahl liest. Sie ist der
# eigentliche Hebel: `read_doc` und `extract_prose` lesen dieselbe Datei —
# nur die Beschreibung sagt, wann welches richtig ist.

@tool(
    "list_docs",
    "Listet alle Markdown-Dateien im Projekt mit erkannter Sprache, "
    "Deutsch-Score und Wortzahl. Immer der erste Schritt, wenn es um "
    "Dokumentation geht — danach weisst du, welche Dateien überhaupt deutsch sind.",
    {},
)
async def list_docs(args):
    docs = [
        {key: value for key, value in doc.items() if key != "_path"}
        for doc in collect_docs()
    ]
    return _ok({"docs": docs, "count": len(docs)})


@tool(
    "extract_prose",
    "Gibt den reinen Fliesstext EINER Markdown-Datei zurück: ohne Codeblöcke, "
    "URLs, Inline-Code und HTML. Das richtige Tool für Rechtschreibung, Sprache "
    "und Formulierung — es spart den ganzen technischen Ballast.",
    {"path": str},
)
async def extract_prose_tool(args):
    path = REPO_ROOT / str(args.get("path") or "")
    if not path.is_file():
        return _ok({"error": f"Datei nicht gefunden: {args.get('path')}"})
    return _ok({"path": str(args.get("path")), "prose": extract_prose(_read(path))})


@tool(
    "read_doc",
    "Gibt eine Markdown-Datei komplett und unverändert zurück, inklusive "
    "Codeblöcken und Tabellen-Markup. Nötig für Fragen zu Struktur, Aufbau oder "
    "Formatierung. Für Rechtschreibprüfung ist extract_prose die bessere Wahl.",
    {"path": str},
)
async def read_doc(args):
    path = REPO_ROOT / str(args.get("path") or "")
    if not path.is_file():
        return _ok({"error": f"Datei nicht gefunden: {args.get('path')}"})
    return _ok({"path": str(args.get("path")), "content": _read(path)})


@tool(
    "spellcheck_candidates",
    "Sucht in den deutschen Dokumenten Verwechslungspaare: seltene Wörter "
    "(höchstens N Vorkommen), die genau einen Buchstaben von einem häufigen "
    "Wort desselben Korpus entfernt liegen — je mit Datei, Zeile und "
    "Vergleichswort. Es gibt kein deutsches Wörterbuch auf diesem System, der "
    "Korpus dient als sein eigenes. Meist sind beide Schreibweisen echte "
    "Wörter; welche hier stimmt, sagt nur der Kontext.",
    {"max_count": int},
)
async def spellcheck_candidates(args):
    try:
        max_count = int(args.get("max_count") or 1)
    except (TypeError, ValueError):
        max_count = 1
    return _ok(collect_typo_candidates(max(1, min(max_count, 5))))


@tool(
    "swift_inventory",
    "Rohdaten zum Swift-Code: alle Dateien mit den darin deklarierten Typen, "
    "alle Testdateien, und für jedes ViewModel/Service/Validator ob eine "
    "passende Testklasse existiert. Liefert Fakten, kein Urteil.",
    {},
)
async def swift_inventory(args):
    return _ok(build_swift_inventory())


@tool(
    "check_comment_language",
    "Sucht Kommentare im Swift-Code, die nicht-englische Zeichen enthalten "
    "(Umlaute, Akzente). CLAUDE.md verlangt englische Kommentare im iOS-Code. "
    "Achtung: ein zitiertes deutsches UI-Label in einem englischen Satz ist "
    "kein Verstoss — die Treffer brauchen dein Urteil.",
    {},
)
async def check_comment_language(args):
    return _ok(scan_comment_language())


@tool(
    "check_conventions",
    "Prüft den Swift-Code gegen die mechanischen Regeln aus CLAUDE.md: kein "
    "Force-Unwrap, kein Combine, Farben nur über FB-Tokens, ein Typ pro Datei. "
    "Gibt für jede Regel die Treffer zurück — eine leere Liste heisst sauber.",
    {},
)
async def check_conventions(args):
    return _ok(scan_conventions())


@tool(
    "grep_swift",
    "Freie Regex-Suche über alle Swift-Dateien. Der Notausgang für Fragen, für "
    "die es kein eigenes Tool gibt. Wenn ein spezifisches Tool passt, nimm das — "
    "es liefert strukturierte Daten statt roher Zeilen.",
    {"pattern": str},
)
async def grep_swift(args):
    return _ok(grep_sources(str(args.get("pattern") or "")))


TOOLS = [
    list_docs,
    extract_prose_tool,
    read_doc,
    spellcheck_candidates,
    swift_inventory,
    check_comment_language,
    check_conventions,
    grep_swift,
]


SYSTEM_PROMPT = """\
Du bist ein Review-Assistent für das FitBuddy-Repository (CAS-Projekt, native \
iOS-App). Du prüfst zwei Dinge: die deutschsprachige Dokumentation auf \
Rechtschreibung, und den Swift-Code gegen die Konventionen aus CLAUDE.md.

Arbeite ausschliesslich mit den Tools. Du hast das Repository nicht im Kopf — \
was kein Tool zurückgegeben hat, weisst du nicht.

Wähle das engste Tool, das die Frage beantwortet, und rufe kein Tool zweimal \
mit denselben Argumenten auf.

Kein Tool hier fällt ein Urteil, sie liefern nur Daten. Bei der Rechtschreibung \
gibt es kein Wörterbuch: du bekommst seltene Wörter und entscheidest selbst, \
was Tippfehler und was Fachbegriff ist. Melde ein Wort nur, wenn du die \
korrekte Schreibweise angeben kannst.

Wenn ein Tool nichts findet, ist das ein Ergebnis. Sag "keine Treffer" und \
erfinde nichts dazu.

Gib pro Fund an: Datei, Zeile, was falsch ist, wie es richtig heisst. Am Ende \
ein Satz dazu, was du geprüft hast und was nicht.

Antworte auf Deutsch."""


DEFAULT_PROMPT = (
    "Prüfe die deutschen Dokumente auf Rechtschreibfehler und den Swift-Code "
    "auf Verstösse gegen die Konventionen. Fasse beides zusammen."
)


def build_options():
    # ── Schritt 2: Tools in einen In-Process-MCP-Server packen ─────────────
    server = create_sdk_mcp_server(name="review", version="1.0.0", tools=TOOLS)

    # ── Schritt 3: Server anschliessen + jedes Tool einzeln erlauben ───────
    # Der Schlüssel "review" landet im Toolnamen: mcp__review__<tool-name>.
    # Nur die gelisteten Tools sind erlaubt — die eingebauten Read/Grep/Glob
    # bleiben absichtlich draussen, sonst weisst du nachher nicht, ob das
    # Modell dein Tool gewählt hat oder das generische.
    return ClaudeAgentOptions(
        model=MODEL,
        system_prompt=SYSTEM_PROMPT,
        mcp_servers={"review": server},
        allowed_tools=[f"mcp__review__{function.name}" for function in TOOLS],
        max_turns=20,
        max_budget_usd=1.50,
    )


# ── Schritt 4: Laufen lassen und jeden Tool-Aufruf mitschreiben ────────────

async def run_agent(prompt: str) -> int:
    async for message in query(prompt=prompt, options=build_options()):
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if isinstance(block, ToolUseBlock):
                    # Nach stderr, damit stdout der reine Bericht bleibt.
                    print(f">>> TOOL {block.name}  {block.input}", file=sys.stderr)
                elif isinstance(block, TextBlock):
                    print(block.text)
        elif isinstance(message, ResultMessage):
            cost = message.total_cost_usd or 0.0
            print(f"\n--- Turns: {message.num_turns} · Kosten: ${cost:.4f} ---", file=sys.stderr)
    return 0


def selftest() -> int:
    """Alle acht Tools direkt aufrufen — ohne Modell, ohne API-Key.

    Zeigt, was das Modell später zu sehen bekommt. Wer die Tool-Beschreibungen
    ändert, sollte vorher hier schauen, ob die Daten überhaupt taugen.
    """
    docs = collect_docs()
    print(f"[1] list_docs — {len(docs)} Dateien")
    for doc in docs:
        print(f"    {doc['language']:<6} score={doc['german_score']:<5} "
              f"umlauts={doc['umlauts']:<5} {doc['path']}")

    sample = "docs/REQUIREMENTS.md"
    prose = extract_prose(_read(REPO_ROOT / sample))
    raw = len(_read(REPO_ROOT / sample))
    print(f"\n[2/3] extract_prose vs read_doc auf {sample}: "
          f"{len(prose)} von {raw} Zeichen ({100 * len(prose) // raw}%)")

    rare = collect_typo_candidates(1)
    print(f"\n[4] spellcheck_candidates — {rare['total_candidates']} Paare aus "
          f"{rare['rare_words_examined']} seltenen Wörtern in "
          f"{len(rare['scanned_docs'])} Dokumenten")
    for item in rare["candidates"][:15]:
        print(f"    d={item['distance']}  {item['word']:<24} ~ {item['similar_to']:<24}"
              f" {item['file']}:{item['line']}")

    inventory = build_swift_inventory()
    missing = [e for e in inventory["viewmodels_and_services"] if not e["has_test_class"]]
    print(f"\n[5] swift_inventory — {inventory['source_files']} Quelldateien, "
          f"{inventory['test_files']} Testdateien, "
          f"{len(inventory['viewmodels_and_services'])} testpflichtige Typen, "
          f"{len(missing)} ohne Test")

    comments = scan_comment_language()
    print(f"\n[6] check_comment_language — {len(comments['findings'])} Treffer")
    for finding in comments["findings"]:
        print(f"    {finding['file']}:{finding['line']}  {finding['text'][:80]}")

    conventions = scan_conventions()
    print("\n[7] check_conventions")
    for key in ("force_unwrap", "combine", "hardcoded_color", "multi_type_files"):
        print(f"    {key:<20} {len(conventions[key])} Treffer")

    grep = grep_sources(r"actor\s+\w+")
    print(f"\n[8] grep_swift 'actor \\w+' — {len(grep['matches'])} Treffer")
    for match in grep["matches"]:
        print(f"    {match['file']}:{match['line']}  {match['text'][:60]}")
    return 0


def main() -> int:
    args = sys.argv[1:]
    if args and args[0] == "--selftest":
        return selftest()

    if not SDK_AVAILABLE:
        print(
            "claude_agent_sdk ist nicht installiert. Für den Agenten:\n"
            "  pip install claude-agent-sdk\n"
            "Die Tools allein laufen auch ohne:\n"
            "  python project_review_agent.py --selftest",
            file=sys.stderr,
        )
        return 1

    prompt = " ".join(args).strip() or DEFAULT_PROMPT
    return asyncio.run(run_agent(prompt))


if __name__ == "__main__":
    raise SystemExit(main())
