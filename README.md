# Heat Acclimation (Garmin Connect IQ)

A Forerunner 955 watch app that records passive heat exposure (dry sauna /
steam room) as a **native Garmin activity** and scores it as a heat-acclimation
**dose** using heart rate as a proxy for core-temperature-time.

> Read `CLAUDE.md` first. It is the source of truth for architecture and rules.
> `EVIDENCE_BASE.md` is the source of truth for all physiology and dosing.

## Why heart rate (and not temperature)
The wrist cannot measure core temperature, and the watch's thermometer reads
body heat, not air temp. So the dose model is **HR-time-in-zone + HR drift**,
presented honestly as a proxy. Steam-room scoring is **extrapolated** and labeled
as lower-confidence.

## Project map
```
manifest.xml            target = fr955, permissions = Fit + UserProfile
monkey.jungle           build config
resources/strings/      UI strings (incl. mandatory proxy/steam disclaimers)
resources/drawables/    launcher icon (placeholder PNG to add)
source/
  Config.mc             ALL tunable constants (target band, multipliers, decay…)
  DoseEngine.mc         in-zone seconds, modality-weighted dose, HR drift
  SessionManager.mc     ActivityRecording session + custom FIT fields
  SafetyGate.mc         contraindication state, caps, beta-blocker proxy flag
  TrendStore.mc         cross-session persistence: staging, decay, adaptation
  HeatAccApp.mc         entry point (screening gate -> main view)
  HeatAccView.mc        1 Hz sampling loop, HRmax resolution, rendering
  HeatAccDelegate.mc    buttons: start/stop, lap=round, up/down=modality
  ScreeningView.mc      one-time safety screen (STUB - build the real flow)
```

## Build & run

### VS Code (recommended — extension already installed)
1. Open this folder (`heat-acclimation/`) in VS Code.
2. **Install the SDK:** `Cmd+Shift+P` → *Monkey C: Install SDK* — choose the
   latest stable release and install the **fr955** device definition.
3. **Generate a developer key** (one-time): `Cmd+Shift+P` →
   *Monkey C: Generate Developer Key* — save the `.der` file somewhere permanent
   and set its path in `.vscode/settings.json` → `monkeyC.developerKeyPath`.
4. **Build:** `Cmd+Shift+P` → *Monkey C: Build Current Project* (or press F5 to
   build and launch the simulator directly).
5. **Simulator:** launches automatically on F5; use the simulator's heart-rate
   injection to test the dose loop.
6. **Side-load to watch:** copy `bin/HeatAcc.prg` → `GARMIN/APPS/` over USB.

### CLI (once SDK is on PATH)
```
monkeyc -f monkey.jungle -d fr955 -o bin/HeatAcc.prg -y <path/to/key.der>
connectiq          # start simulator
monkeydo bin/HeatAcc.prg fr955
```

## Known TODOs / verify-before-trusting
- `Config.REC_SPORT` / `REC_SUB_SPORT`: confirm the enum names compile against
  the installed SDK; there is no native sauna sport.
- `FitContributor.createField` data types / option keys: verify against the SDK.
- **Screening flow is a stub** — build the real multi-question questionnaire and
  capture beta-blocker status (it invalidates the HR proxy).
- Session duration-cap dialog: currently only detected, not surfaced to the user.
- Optional: ambient temperature as **manual** entry only (never a sensor read).

## Hard rules (see CLAUDE.md for the full list)
- Never imply the score is a core-temperature measurement.
- Never read/write Garmin's Heat Acclimation metric.
- Always label steam scoring as extrapolated.
- Safety gates block dose; never score past a tripped gate.
- Steam moisture + heat can exceed the watch's rated range — warn the user.
