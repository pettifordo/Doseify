# Doseify

Test harness for the Doseify time-zone shift engine.

## Live demo

Once GitHub Pages is enabled on this repo, the harness will be reachable at:

**https://pettifordo.github.io/Doseify/**

(Update the URL if the repo or username changes.)

## What this is

A single-file, self-contained HTML playground for the medication time-shifting
algorithm that will eventually power the Doseify iOS app. The goal is to get
the algorithm right *before* porting it to Swift.

Everything runs in your browser; nothing is sent anywhere. Saved scenarios
live in your browser's `localStorage`.

Features:

- Configure home + destination timezone, flight times, medication schedule
- Pick a shift strategy (snap on landing, gradual pre-shift, split,
  or "suggest" to let the engine pick)
- Pick a direction (delay = clock later each day; advance = clock earlier)
- Discrete 30-minute step shifts (or whatever step you configure)
- Day-by-day dose table + interactive timeline visualization
- Live warning recompute (interval too short / too long, sleep-window doses,
  in-flight doses)
- **Drag any dose dot** on the timeline to override its time — snaps to
  30-min boundaries, warnings update live
- Compare two strategies side by side
- Save scenarios as named regression-test fixtures; export to JSON

## Running locally

Open `index.html` in any modern browser. No build step, no server, no
dependencies.

## Known limitations

- Fixed UTC offsets — no IANA zone / DST handling. A trip that crosses a DST
  boundary will be off by an hour. The production iOS engine will need real
  zone support.
- The engine is geometric, not clinical. It places dose times; it does not
  know about drug pharmacokinetics, food interactions, or which strategy is
  safe for a given medication.
- Single-leg flights only (no layovers).

## Status

Research preview — not medical advice, not a shipping product.
