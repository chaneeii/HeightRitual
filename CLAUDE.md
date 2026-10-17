# Height Ritual

iOS app plus ESP32 controller firmware for a KTH interaction design course prototype (DM2601, Group 6).
A family member is filmed at the wall for a few seconds; the app suggests their height, the parent
corrects it, and every past record is projected life-size on the wall. A Bluetooth controller drives it.

- What to build (screens, controls, protocol, data, requirements): `docs/SPEC.md` (v3)
- How to build it (architecture, file map, milestones, risks): `docs/IMPLEMENTATION.md`
- Old draft, for reuse only: `reference/v1/` (never compiled, still photo, different flow)
- New teammates (new to Xcode, git and Claude): `docs/ONBOARDING.md`

## Current state

All milestones are written. Checked in the simulator: 1 to 3, the Make flow up to Save, the
welcome pages. Written but NOT yet run on a device: M4 projector scene (with an AppDelegate
fallback for risk 1), M5 camera, M6 `Capture/VideoCutout.swift` (Vision segmentation, alpha HEVC,
head-top estimate), M7 `Playback/WallPlayer.swift` (clip on the wall and in the wall copy), the
controller light. P1 live foot check and the camera position auto-detect are not built.

- The phone UI follows Apple's HIG: system TabView (Make / Memory, hidden on pushed screens),
  NavigationStacks drawn from `AppState.route` (`State/Navigation.swift`; the system back button
  sends Cancel), Settings and A1 as sheets with Forms.
- iPhone and iPad, portrait, full screen. Light / dark / system appearance.
- English, Korean, Simplified Chinese, Swedish (`Resources/*.xcstrings`), chosen in Settings.
  Strings built in code go through `L(_:)` so they follow that choice.
- The controller connects on a device; buttons-only firmware in `Firmware/controller_buttons/`.
- 53 unit tests in `HeightRitualTests/` pass in the simulator (scheme runs them in English).

## Commands

```
xcodegen                       # regenerate HeightRitual.xcodeproj from project.yml
xcodebuild -project HeightRitual.xcodeproj -scheme HeightRitual \
  -destination 'generic/platform=iOS Simulator' build
xcodebuild test -project HeightRitual.xcodeproj -scheme HeightRitual \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Run `xcodegen` after adding, removing or moving source files. The `.xcodeproj` is generated; edit `project.yml` instead.

## Rules

- iOS 17+, SwiftUI, `@Observable`, Swift 5 language mode. No third-party packages. No networking.
- The spec wins over `reference/v1/`. Copy ideas from v1, not its flow.
- All input goes through `AppState.handle(_ event: ControlEvent)`. Views send events; they hold no flow logic.
- Change the route only through `AppState.go(to:)`.
- Wall positions are computed in centimetres with `WallGeometry`. Heights are stored in millimetres;
  format them only through `HeightFormatter` so the unit setting applies everywhere.
- One decision per screen, one obvious next action. Follow Apple's HIG: system controls, targets at least 44 pt. No hidden gestures.
- Keep `Firmware/controller/controller.ino`, `ControllerManager` and the protocol table in SPEC section 6 in sync.
- Clips of family members never leave the device.
- UI text: English source strings, sentence case, no emoji. Add every new string to
  `Resources/Localizable.xcstrings` with ko, zh-Hans and sv translations.
- Camera, Bluetooth, video writing and the external display cannot be tested in the simulator.
  Say so when a change touches them and has not been run on a device. Never claim they work untested.
- Finish one milestone, build, and report before starting the next.
- When an open question in SPEC section 15 gets settled, update the spec in the same change.

## Working with a new teammate

Some teammates are new to iOS, Xcode, git and Claude. When the person you are working with seems new:

- Explain each git step in one plain sentence before running it. Reply in their language.
- Never commit or push to `main`. Work on a branch and open a PR for review.
- Ask before force-pushing, deleting branches or discarding changes.
- After a change, tell them exactly what to tap in the simulator to check it.
