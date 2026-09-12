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
  -destination 'platform=iOS Simulator,name=FitBuddy Tests' \
  2>&1 | tail -60
```

- Scheme is `FitBuddy` (the only one); tests live in the `FitBuddyTests` target.
- **Always test on the dedicated `FitBuddy Tests` simulator, never on the one used for manual testing.** The suite runs against the real simulator Keychain and wipes every FitBuddy key in `setUp`/`tearDown`, and the UI tests launch the app with a forced reset — a test run on the developer's own simulator deletes their Hevy, LLM and Strava credentials. Create the device once if it is missing (an iPhone 17 clone on the current iOS runtime):
  ```bash
  xcrun simctl create "FitBuddy Tests" \
    com.apple.CoreSimulator.SimDeviceType.iPhone-17 \
    "$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; print([r["identifier"] for r in json.load(sys.stdin)["runtimes"] if r["platform"]=="iOS" and r["isAvailable"]][-1])')"
  ```
- A full run takes a few minutes — use a generous timeout, don't abort early.
- Build-only check (faster, no simulator boot): replace `test` with `build`.

## If the UI tests fail with "Application failed preflight checks" / "Busy"

A `-only-testing:` run leaves the simulator in a state where the next full run's XCUITests cannot launch the app. Erase the test device and run again — it is disposable, that is what it is for:

```bash
xcrun simctl shutdown all; xcrun simctl erase "FitBuddy Tests"
```

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
