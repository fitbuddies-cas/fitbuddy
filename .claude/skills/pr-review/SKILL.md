---
name: pr-review
description: Review a FitBuddy pull request against the project's conventions (CLAUDE.md) and post the review to the PR on GitHub by default. Use when asked to review a PR, do a code review, or pre-review before merging.
---

# FitBuddy PR review

## Gather the diff

```bash
gh pr view <number-or-branch> --json title,body,author,baseRefName,headRefName,state,additions,deletions,changedFiles
gh pr diff <number-or-branch>
```

The PR diff is the only review scope. For surrounding context, read files from the checkout if it is on the PR branch, otherwise fetch via `gh`.

## Project-specific checks (beyond general correctness)

1. **Workflow:** base branch must be `develop` (never `main`); branch named `feature/task-<issue#>-short` or `fix/bug-<issue#>-short`.
2. **Architecture (MVVM):** Views hold no logic; ViewModels are `@MainActor final class ObservableObject`; Services are `actor`s; Models are `struct Codable`. Keychain access only inside Services. One type per file. Feature-first folders: feature code in `Features/<Name>/`, shared code in `Core/`.
3. **Swift style:** no force-unwrap; async/await, not Combine.
4. **Tests:** every new `ViewModel` and `Service` has XCTest unit tests in `FitBuddyTests/`. Views need none.
5. **Language:** code comments and in-app text in English; `README.md`, `docs/`, and ADRs in German.
6. **Terminology:** "PoC", never "MVP"; the PoC is v0, anything beyond is v1 (no v1.1).
7. **UI changes:** compare against the mocks in `design/` and check that design-system tokens are used (`Color.fb*`, `FBRadius`, `.fb(...)` button styles) instead of hard-coded values.

## Do NOT flag

These are deliberate, documented decisions (CLAUDE.md "Checked" section) — raising them wastes review cycles:

- The BYO-key architecture: user-owned Claude/Hevy API keys in the local Keychain, direct-from-mobile API calls, no backend proxy.
- DPA / DSFA / AUP compliance topics for v0.

## Output

Write the review itself in German. This is about the review text only — the language check in item 5 (code comments/in-app text in English) still applies to the code under review, unchanged.

When presenting in the conversation: sections **Übersicht** → **Positives** → **Findings** (nach Schweregrad geordnet) → **Vorschläge** → **Verdict**. Leere Abschnitte weglassen, sonst knapp halten. Verdict stays the fixed English label (`approve` / `approve-after-fixes` / `request changes`) since it's a status tag, not prose.

### Posting to GitHub — inline, not pasted, and on by default

Posting the finished review to the PR is the default outcome of this skill, not an opt-in step — do it right after presenting the review in the conversation, without waiting to be asked. Skip posting only if the user explicitly says not to (e.g. "just show me", "don't post this"), or if posting fails (no write access, PR already merged/closed). Findings that concern a specific line belong as **inline PR review comments** anchored to that diff line, not pasted as a code block into a plain issue comment — GitHub then renders its own syntax-highlighted diff context next to the finding instead of a manual quote.

1. Get the PR's head SHA: `gh pr view <nr> --json headRefOid --jq .headRefOid`.
2. Build one JSON payload for `POST /pulls/<nr>/reviews`: `commit_id` = that SHA, `event` = `COMMENT` / `APPROVE` / `REQUEST_CHANGES` (matching the verdict), `body` = Übersicht + Positives + Vorschläge + Verdict (German, no individual findings — those go in `comments`), and `comments`: one entry per finding on a changed line, `{ "path": "...", "line": <line in the new file>, "side": "RIGHT", "body": "<Finding, German>" }`. Where the fix is a small in-place edit, put a ` ```suggestion\n<replacement>\n``` ` block inside that comment's `body` — GitHub renders it as a one-click-applicable diff.
3. Submit with `gh api --input review.json -X POST repos/<owner>/<repo>/pulls/<nr>/reviews`.

A finding about a file/line that is **not** part of the diff (e.g. a missing change in an untouched config file) has no diff position to anchor an inline comment to — the review API rejects it. For those, don't force one: reference the exact line with a **permalink** instead (`https://github.com/<owner>/<repo>/blob/<head-sha>/<path>#L<n>` or `#L<n>-L<m>`), placed either in the top-level `body` or in an inline comment on the nearest related changed line. Pasted into a GitHub comment, a permalink auto-expands into a highlighted snippet — no manual code block needed.

`gh pr comment` stays fine for a plain-prose follow-up (e.g. "fixed in commit X") that isn't itself pointing at code.