# Height Ritual

DM2601 Group 6 prototype: iOS app plus ESP32 controller firmware.

| Path | What |
|---|---|
| `docs/SPEC.md` | What to build (v3, 5 Oct 2026) |
| `docs/IMPLEMENTATION.md` | How and in which order |
| `KICKOFF.md` | The first message to give Claude Code |
| `CLAUDE.md` | Standing rules for Claude Code |
| `HeightRitual/` | App sources (milestones 1 to 3) |
| `HeightRitualTests/` | Unit tests (state machine, formatter, store, protocol) |
| `Firmware/controller/` | Controller firmware (Arduino, ESP32) |
| `reference/v1/` | Earlier Swift draft, for reuse only |
| `project.yml` | XcodeGen project definition |

Status: the app builds and its unit tests pass in the simulator. Nothing has been flashed or run on a device yet.

Needs a Mac with Xcode 15 or later, an iPhone on iOS 17 or later, and `brew install xcodegen`.
