---
name: fill-exercises
description: Fill out a course exercise worksheet (.docx) for the FitBuddy project. Extracts the exercise structure, answers all questions using project documentation (ARCHITECTURE.md, REQUIREMENTS.md, PROJECT.md), and writes a new filled .docx back to the same path. Use when given a Word document with blank exercise fields to complete.
argument-hint: <path/to/exercise.docx>
disable-model-invocation: true
allowed-tools: Bash Read Write
---

# fill-exercises

Fill out a Word exercise worksheet with FitBuddy project content.

## Input

`$ARGUMENTS` — absolute or relative path to the `.docx` file to fill.
If no argument is given, ask the user which file to process.

## Workflow

### 1 — Extract the exercise structure

Unpack the `.docx` (it is a ZIP) and pull the text out of `word/document.xml`:

```python
import zipfile, re, html
with zipfile.ZipFile(path) as z:
    xml = z.read("word/document.xml").decode("utf-8")
text = re.sub(r"</w:p>", "\n", xml)
text = re.sub(r"<[^>]+>", "", text)
text = html.unescape(text)
```

Read the extracted text to understand:
- The exercise headings and numbered parts (Teil 1, Teil 2 …)
- Which fields are blank (tables with empty cells, placeholder text like `[EINFÜGEN]`)
- The expected answer format per field (free text, table row, diagram, ADR block …)

### 2 — Read project documentation

Always read these files before writing a single answer:

| File | What to extract |
|---|---|
| `ARCHITECTURE.md` | Tech stack, ADRs (ADR-1–5), Connector interface, data model, C1/C2 topology |
| `REQUIREMENTS.md` | All 12 user stories with ACs, NFRs, MoSCoW table |
| `PROJECT.md` | Personas (Marcus, Jana), risks, sprint plan, scope boundaries |
| `README.md` | One-line summary, feature list, data sources |

### 3 — Draft all answers

Work through every exercise section in order. For each blank field:
- Map it to the correct project fact — do not invent content
- Keep answers concise but complete; fill every sub-point the exercise asks for
- Use exact terminology from the project docs (e.g. `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, not paraphrases)
- If a field asks for something not yet decided, write the open question explicitly

See [docx-helpers.md](docx-helpers.md) for the XML building blocks to use in the script.
See [examples/gen_uebungen.py](examples/gen_uebungen.py) for a complete, working reference implementation (Modul 3, Tag 1 exercises).

### 4 — Generate and run a Python script

Write a self-contained Python script (stdlib only — no `pip install`) that builds the complete filled document and **overwrites the input file**.

Name the script `gen_<basename>.py` in the project root, then run it:

```bash
python3 gen_<basename>.py
```

Visual conventions:
| Element | Helper | Style |
|---|---|---|
| Exercise section headers | `label_bar(text)` | Dark blue bg, white bold |
| Original instructor prompts | `note_box(text)` | Gray bg, italic |
| Our answers (text) | `answer_p(text)` | Light blue bg `#EBF3FB`, dark blue text |
| Diagrams / ASCII art | `code_p(text)` | Monospace, light gray bg |
| Table header rows | `tbl_row(..., header=True)` | Dark blue bg, white text |
| Table answer rows | `tbl_row_ml(..., answer=True)` | Light blue bg |

### 5 — Verify

After the script runs, confirm the output is valid:

```python
import zipfile, re, html as h
with zipfile.ZipFile(output_path) as z:
    xml = z.read("word/document.xml").decode()
text = re.sub(r"<[^>]+>", "", h.unescape(xml))
# spot-check 3–5 key terms from the answers
```

Report: file size, confirmed key terms, output path.

## Hard constraints

- **No external libraries** — stdlib only (`zipfile`, `xml.sax.saxutils`, `html`, `re`, `os`)
- **Overwrite the original** — output path = input path
- **No invented content** — every answer must be traceable to a project document
- **English-only for UI/code strings** — per ADR-4; exercise prose may be German
