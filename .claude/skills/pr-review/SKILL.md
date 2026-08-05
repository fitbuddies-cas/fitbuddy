---
name: pr-review
description: Review a FitBuddy pull request against the project's conventions (CLAUDE.md). Use when asked to review a PR, do a code review, or pre-review before merging.
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

Sections: overview → what's good → issues (ordered by severity, each with file/line and a concrete fix) → suggestions → verdict (approve / approve-after-fixes / request changes). Keep it concise; skip empty sections.

Only post to GitHub when explicitly asked: `gh pr comment` for an informal comment, `gh pr review --approve|--request-changes|--comment` for a formal review. Otherwise present the review in the conversation.