# Doseify

A warm, travel-aware iPhone + Apple Watch medication tracker.

## Prerequisites

- macOS Sonoma (14) or later
- **Xcode 15+** — install from the Mac App Store
- **Homebrew** — https://brew.sh
- **xcodegen** — `brew install xcodegen`
- An **Apple Developer account** ($99/year) — required for TestFlight and device installs
- Claude Code installed and authenticated

## First-time setup

```bash
# 1. Create an empty repo
mkdir Doseify && cd Doseify
git init

# 2. Drop these three files in the root:
#    - CLAUDE.md
#    - SPEC.md
#    - README.md  (this file)

# 3. Start Claude Code from the repo root
claude

# 4. Once Claude Code is running, give it this prompt:
#    "Read CLAUDE.md and SPEC.md, then bootstrap the project per the
#     'Bootstrapping the project' section in CLAUDE.md. Stop after the
#     project opens cleanly in Xcode and tell me what you did."
```

Claude Code should produce a `project.yml`, run `xcodegen generate`, and leave you with a working `Doseify.xcodeproj`. Open it in Xcode (`open Doseify.xcodeproj`) and confirm it builds for the simulator.

After bootstrap, you can hand subsequent work to Claude Code one feature at a time. The spec deliberately doesn't prescribe phasing — let Claude Code propose a plan and approve or adjust.

## Suggested first prompts after bootstrap

In rough order:

1. *"Implement the SwiftData models per SPEC §3. Add unit tests for any computed properties."*
2. *"Implement the `DoseScorer` per SPEC §2.5. It's a pure function; full test coverage."*
3. *"Implement the `TimezoneShiftEngine` per SPEC §2.4. Pure functions; cover the edge cases listed in the spec with tests."*
4. *"Build the medication CRUD UI per SPEC §2.1. Use the tone described in §5."*
5. *"Wire up notifications per SPEC §2.2. Stub out HealthKit for now."*

## Running the app on her phone

You'll need:
- Her phone connected to your Mac via USB the first time
- Her Apple ID added to Xcode → Settings → Accounts
- A development team selected on the Doseify target → Signing & Capabilities
- TestFlight invite once you've uploaded a build to App Store Connect

## Things to confirm before relying on the app

These are flagged in SPEC §10 and §11. Don't skip them:

- The 30-min/day timezone shift rate is acceptable for her specific drugs (confirm with oncologist)
- The 5-minute on-time / 120-minute cutoff defaults are acceptable for her drugs
- HealthKit medication-event writing actually works on your target iOS — verify with a real device, not just the simulator
- Critical Alerts: either pursue the Apple entitlement, or accept that DND will sometimes suppress reminders
- Set up a monthly calendar reminder to export the adherence PDF — there is no cloud backup, so an export is the only off-device record

## Name verification (do this before paying for anything)

Before buying a domain or paying for the developer account specifically for "Doseify":

1. Search the App Store directly for "Doseify"
2. Check USPTO TESS at https://tmsearch.uspto.gov/ — classes 9 and 44
3. Check `doseify.com`, `doseify.app`, `doseify.io` availability

A web search did not surface a conflicting medication app, but that's not a substitute for the checks above.
