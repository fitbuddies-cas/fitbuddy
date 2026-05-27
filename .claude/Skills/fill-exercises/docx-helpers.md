# docx XML helpers — FitBuddy exercise generator

> **Vollständiges Referenz-Beispiel:** [`examples/gen_uebungen.py`](examples/gen_uebungen.py)
> Zeigt alle Helfer im Einsatz für ein echtes Übungsblatt (Modul 3, Tag 1).
> Die `STYLES`-Konstante (Calibri, Heading1-3, TableGrid) steht dort vollständig — hier weggelassen.

Reference for building `.docx` files with pure Python stdlib.
Copy these functions into any `gen_*.py` script verbatim.

## Required imports

```python
import zipfile
from xml.sax.saxutils import escape as esc
```

## Paragraph helpers

```python
def h(level, text):
    """Heading 1–3 in Calibri Light, blue."""
    return (
        f'<w:p><w:pPr><w:pStyle w:val="Heading{level}"/>'
        f'<w:spacing w:before="320" w:after="80"/></w:pPr>'
        f'<w:r><w:t>{esc(text)}</w:t></w:r></w:p>'
    )

def p(text="", bold=False, italic=False, color=None, indent=0):
    """Normal paragraph. color = 6-char hex, e.g. "595959"."""
    rpr = []
    if bold:   rpr += ["<w:b/><w:bCs/>"]
    if italic: rpr += ["<w:i/><w:iCs/>"]
    if color:  rpr += [f'<w:color w:val="{color}"/>']
    rpr_xml = f'<w:rPr>{"".join(rpr)}</w:rPr>' if rpr else ""
    ind_xml = f'<w:ind w:left="{indent}"/>' if indent else ""
    return (
        f'<w:p><w:pPr><w:spacing w:after="100"/>{ind_xml}</w:pPr>'
        f'<w:r>{rpr_xml}<w:t xml:space="preserve">{esc(text)}</w:t></w:r></w:p>'
    )

def blank():
    return '<w:p><w:pPr><w:spacing w:after="80"/></w:pPr></w:p>'

def divider():
    """Horizontal rule in blue."""
    return (
        '<w:p><w:pPr><w:pBdr>'
        '<w:bottom w:val="single" w:sz="6" w:space="1" w:color="2E74B5"/>'
        '</w:pBdr><w:spacing w:after="60"/></w:pPr></w:p>'
    )
```

## Styled box helpers

```python
def label_bar(text, color="2E74B5"):
    """Dark-coloured section header bar — white bold text."""
    return (
        f'<w:p><w:pPr>'
        f'<w:shd w:val="clear" w:color="auto" w:fill="{color}"/>'
        f'<w:spacing w:before="200" w:after="100"/>'
        f'<w:ind w:left="120"/></w:pPr>'
        f'<w:r><w:rPr><w:b/><w:bCs/><w:color w:val="FFFFFF"/>'
        f'<w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr>'
        f'<w:t>{esc(text)}</w:t></w:r></w:p>'
    )

def note_box(text):
    """Gray italic box — original instructor prompts."""
    return (
        f'<w:p><w:pPr>'
        f'<w:shd w:val="clear" w:color="auto" w:fill="F2F2F2"/>'
        f'<w:spacing w:after="80"/>'
        f'<w:ind w:left="180" w:right="180"/></w:pPr>'
        f'<w:r><w:rPr><w:i/><w:iCs/><w:color w:val="595959"/>'
        f'<w:sz w:val="18"/></w:rPr>'
        f'<w:t xml:space="preserve">{esc(text)}</w:t></w:r></w:p>'
    )

def answer_p(text, bold=False):
    """Light-blue answer paragraph."""
    b = "<w:b/><w:bCs/>" if bold else ""
    return (
        f'<w:p><w:pPr>'
        f'<w:shd w:val="clear" w:color="auto" w:fill="EBF3FB"/>'
        f'<w:spacing w:after="60"/>'
        f'<w:ind w:left="180" w:right="180"/></w:pPr>'
        f'<w:r><w:rPr>{b}<w:color w:val="1F4E79"/></w:rPr>'
        f'<w:t xml:space="preserve">{esc(text)}</w:t></w:r></w:p>'
    )

def code_p(text):
    """Monospace line — for ASCII diagrams and code."""
    return (
        f'<w:p><w:pPr>'
        f'<w:shd w:val="clear" w:color="auto" w:fill="F8F8F8"/>'
        f'<w:spacing w:after="40"/>'
        f'<w:ind w:left="180"/></w:pPr>'
        f'<w:r><w:rPr>'
        f'<w:rFonts w:ascii="Courier New" w:hAnsi="Courier New"/>'
        f'<w:sz w:val="16"/><w:szCs w:val="16"/>'
        f'<w:color w:val="1F1F1F"/></w:rPr>'
        f'<w:t xml:space="preserve">{esc(text)}</w:t></w:r></w:p>'
    )

def sub_heading(text):
    """Bold blue paragraph heading (not an outline level)."""
    return (
        f'<w:p><w:pPr><w:spacing w:before="200" w:after="60"/></w:pPr>'
        f'<w:r><w:rPr><w:b/><w:bCs/><w:color w:val="2E74B5"/>'
        f'<w:sz w:val="22"/></w:rPr>'
        f'<w:t>{esc(text)}</w:t></w:r></w:p>'
    )
```

## Table helpers

```python
def _cell_p(text, header=False, answer=False):
    rpr = []
    if header: rpr += ["<w:b/><w:bCs/>", '<w:color w:val="FFFFFF"/>']
    if answer: rpr += ['<w:color w:val="1F4E79"/>']
    rpr_xml = f'<w:rPr>{"".join(rpr)}</w:rPr>' if rpr else ""
    fill = "EBF3FB" if answer else None
    shd = f'<w:shd w:val="clear" w:color="auto" w:fill="{fill}"/>' if fill else ""
    return (
        f'<w:p><w:pPr>{shd}'
        f'<w:spacing w:before="60" w:after="60"/></w:pPr>'
        f'<w:r>{rpr_xml}'
        f'<w:t xml:space="preserve">{esc(text)}</w:t></w:r></w:p>'
    )

def _cell_lines(lines, answer=False):
    """Multiple paragraphs in one cell."""
    fill = "EBF3FB" if answer else None
    shd = f'<w:shd w:val="clear" w:color="auto" w:fill="{fill}"/>' if fill else ""
    out = ""
    for line in lines:
        rpr = f'<w:rPr><w:color w:val="1F4E79"/></w:rPr>' if answer else ""
        out += (
            f'<w:p><w:pPr>{shd}'
            f'<w:spacing w:before="40" w:after="40"/></w:pPr>'
            f'<w:r>{rpr}'
            f'<w:t xml:space="preserve">{esc(line)}</w:t></w:r></w:p>'
        )
    return out

def _tc(content_xml, header=False, fill=None):
    shd = f'<w:shd w:val="clear" w:color="auto" w:fill="{"2E74B5" if header else (fill or "")}"/>' if (header or fill) else ""
    borders = (
        '<w:tcBorders>'
        '<w:top    w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
        '<w:left   w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
        '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
        '<w:right  w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
        '</w:tcBorders>'
    )
    return f'<w:tc><w:tcPr>{shd}{borders}</w:tcPr>{content_xml}</w:tc>'

def tbl_row(*cells, header=False, answer=False):
    """Single-line row. Pass strings."""
    tcs = "".join(
        _tc(_cell_p(str(c), header=header, answer=answer),
            header=header, fill="EBF3FB" if answer else None)
        for c in cells
    )
    return f'<w:tr>{tcs}</w:tr>'

def tbl_row_ml(*cells, answer=False):
    """Multi-line row. Each cell can be a list of strings or a plain string."""
    tcs = "".join(
        _tc(
            _cell_lines(c, answer=answer) if isinstance(c, (list, tuple))
            else _cell_p(str(c), answer=answer),
            fill="EBF3FB" if answer else None
        )
        for c in cells
    )
    return f'<w:tr>{tcs}</w:tr>'

def tbl(*rows):
    return (
        '<w:tbl>'
        '<w:tblPr>'
        '<w:tblStyle w:val="TableGrid"/>'
        '<w:tblW w:w="0" w:type="auto"/>'
        '</w:tblPr><w:tblGrid/>'
        + "".join(rows) +
        '</w:tbl>'
    )
```

## Document shell

Wrap the assembled `body` list in this shell and write with `zipfile`:

```python
DOCUMENT_XML = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document
  xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
  mc:Ignorable="">
<w:body>
''' + "\n".join(body) + '''
<w:sectPr>
  <w:pgSz w:w="11906" w:h="16838"/>
  <w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134"
           w:header="709" w:footer="709" w:gutter="0"/>
</w:sectPr>
</w:body></w:document>'''

# --- minimal support files (copy verbatim) ---
CONTENT_TYPES = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml"  ContentType="application/xml"/>
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

SETTINGS  = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:defaultTabStop w:val="720"/></w:settings>'''

NUMBERING = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:abstractNum w:abstractNumId="0">
    <w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/>
    <w:lvlText w:val="•"/><w:lvlJc w:val="left"/>
    <w:pPr><w:ind w:left="360" w:hanging="360"/></w:pPr></w:lvl>
  </w:abstractNum>
  <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
</w:numbering>'''

# STYLES constant: copy from gen_uebungen.py in the project root (too long to repeat here)
# It defines Normal, Title, Heading1-3, ListParagraph, TableGrid styles in Calibri.

with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("[Content_Types].xml",        CONTENT_TYPES)
    z.writestr("_rels/.rels",                RELS)
    z.writestr("word/document.xml",          DOCUMENT_XML)
    z.writestr("word/_rels/document.xml.rels", WORD_RELS)
    z.writestr("word/styles.xml",            STYLES)   # copy from gen_uebungen.py
    z.writestr("word/settings.xml",          SETTINGS)
    z.writestr("word/numbering.xml",         NUMBERING)

print(f"✓ Erstellt: {OUT}")
```

## Quick-reference: helper cheat sheet

| Goal | Call |
|---|---|
| Blue section bar | `label_bar("Ü1 · Quality Attributes · 09:15–10:00")` |
| Gray instructor note | `note_box("Quality Attributes sind …")` |
| Answer text | `answer_p("Security ist kritisch weil …")` |
| Bold answer label | `answer_p("#1 — Security", bold=True)` |
| Diagram line | `code_p("  iOS App → Hevy API")` |
| Table with answers | `tbl(tbl_row("Col A","Col B",header=True), tbl_row_ml(["line1","line2"],"val", answer=True))` |
| Separator | `divider()` |
| Empty line | `blank()` |
