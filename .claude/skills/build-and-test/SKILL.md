---
name: build-and-test
description: Build FitBuddy and run the XCTest suite on the iOS simulator. Use before committing, when verifying a code change, or whenever asked to build or run tests.
---

# Build & test FitBuddy

Run the full test suite (builds first, so no separate build step is needed):

```bash
xcodebuild test \
  -project FitBuddy.xcodeproj \
  -scheme FitBuddy \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  2>&1 | tail -60
```

- Scheme is `FitBuddy` (the only one); tests live in the `FitBuddyTests` target.
- Any available iPhone simulator works; `iPhone 17` is the default on team machines. If it is missing, pick one from `xcrun simctl list devices available`.
- A full run takes a few minutes — use a generous timeout, don't abort early.
- Build-only check (faster, no simulator boot): replace `test` with `build`.

## If xcodebuild complains about CommandLineTools

On machines where `xcode-select -p` points to `/Library/Developer/CommandLineTools`, prefix commands with:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

(Or fix it once via `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` — needs sudo, so ask the user to run it.)

## Reporting rules

- On failure: name each failing test with its assertion message (grep the log for `error:` and `failed`), don't just say "tests failed".
- Never commit while the suite is red.
- New `ViewModel`s and `Service`s require matching unit tests in `FitBuddyTests/` (see CLAUDE.md) — flag it if the change under test lacks them.
