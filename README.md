# Dominus

A terrain-sculpting god game for macOS, built with Godot. Simulation, rules and
progression are separate from rendering, UI and audio; see
[architecture](docs/ARCHITECTURE.md).

## Install

Open `dist/Dominus-0.1.1-arm64.pkg`. It installs **Dominus.app** in Applications.
The installer contains application code and its runtime dependencies, without
external game artwork, models, animation, maps, music or sound effects.

On first launch, Dominus downloads the separately hosted content archive,
verifies its pinned checksum, extracts it and converts the required resources.
Progress appears in the setup window. Downloads can resume after interruption;
setup can be retried after an error. The original executable is read as data
and is never launched. The source URL and integrity values are in
[`config/asset_source.json`](config/asset_source.json).

Content and generated files live under
`~/Library/Application Support/Dominus/runtime/`. Setup logs are stored there.
Subsequent launches use that local content without downloading it again.
This local development build has an ad-hoc application signature and an
unsigned installer; it is not notarized.
This bundled-tool build requires Apple Silicon and macOS 27.2 or newer.

## Play

- **Start** begins Homeworld; **Campaigns** selects another available map.
- Two-finger trackpad movement pans; Shift + two fingers rotates and tilts.
  Pinch or the mouse wheel zooms. Pan with the middle mouse button and orbit
  with the right mouse button.
- Drag terrace edges to extend or shrink terrain layers.
- Click a home once to collect its belief. Once BeliefLeashing is unlocked,
  hold and drag across other homes to collect from them too.
- Once Leashing is unlocked, hold a follower until the leash appears, then
  drag to land and release. The leash stays pinned there while the follower
  walks or waits for a route.
- The top-left collection shows advances and resource cards. Select an advance
  to see compatible resources, then drag a resource onto its portrait.
  Buried chests and adventure rewards supply resources.
- Select a temple site to inspect its builders, repair time and costs.
  Idle builders prioritize clear, reachable sites they can afford to repair.
  Tap covering trees to clear them; remove covering houses with Finger of God
  after unlocking that power. Sculpt away land above buried sites.
- The top-right menu contains save/load, JSON settings and three editable
  unit tables: `Adobes.csv`, `Followers.csv`, `Update.csv`. Save edits in
  OpenOffice or LibreOffice, then use **Reload all 3 CSV files**.
- **Example world** and **Asset library** inspect recovered models and
  components. Unsupported content has no fabricated replacement.

Supported campaigns still have incomplete later progression and special
unit behavior. Available terrain maps do not imply complete individual stories.
[PLAN.md](PLAN.md) records remaining work.

## Source checkout

Open `game/project.godot` with Godot 4.8. Missing content opens first-launch
setup automatically. Source-checkout conversion requires Python 3, 7-Zip,
ImageMagick and the audio tools described in [asset conversion](docs/ORIGINAL_ASSETS.md).
The installer bundles its own engine, Python, archive extraction and
conversion tools; it does not require Homebrew or a separate Python install.

External source data, converted assets, native comparison captures, local saves,
build outputs and installers are excluded by `.gitignore`. Preserve source
provenance in generated local manifests. Do not include downloaded or converted
external assets in the source repository. The supplied Dominus logo and
explicitly requested Roboto Condensed font are included.

Build an installer on the configured macOS development machine:

```sh
python3 tools/package_macos.py
```

GitHub Actions publishes an Apple Silicon installer and its checksum manifest
for each commit on `main`, starting with 0.1.1. It builds any pending commits
in order and reuses the verified runtime from the 0.1.0 release. Each manifest
records the commit used for that installer.

After local content setup, run checks:

```sh
python3 -m unittest discover -s tests -v
python3 tools/check_game.py
```

Native research captures are optional development inputs and are not included
in the installer. Regenerate them locally before running comparison checks
that depend on them. Runtime simulation never requires an emulator.
