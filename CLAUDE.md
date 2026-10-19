# Height Ritual (app name: Memory Meter)

iOS app plus ESP32 controller firmware for a KTH interaction design course prototype (DM2601, Group 6).
A family member is filmed at the wall for a few seconds; the app suggests their height, the parent
corrects it, and every past record is projected life-size on the wall. A Bluetooth controller drives it.

- What to build (screens, controls, protocol, data, requirements): `docs/SPEC.md` (v3)
- How to build it (architecture, file map, milestones, risks): `docs/IMPLEMENTATION.md`
- Old draft, for reuse only: `reference/v1/` (never compiled, still photo, different flow)

## Current state

All milestones are written. Checked in the simulator: 1 to 3, the Make flow up to Save, the
welcome pages. Written but NOT yet run on a device: M4 projector scene (with an AppDelegate
fallback for risk 1), M5 camera, M6 `Capture/VideoCutout.swift` (Vision segmentation, alpha HEVC,
head-top estimate), M7 `Playback/WallPlayer.swift` (clip on the wall and in the wall copy), the
controller light. P1 live foot check and the camera position auto-detect are not built.

- Redesign in progress (feature/new-design): member-first Home wheel, member menu, letter-wheel
  add, Record (film, dial, saved) and Lookback, each with a phone and a wall version
  (`Phone/Home`, `Phone/Record`, `Phone/Playback`, `Phone/Design`). Colours and fonts only from
  `Theme`; controller buttons only as `ControlIcon`. Debug builds: the projector button on every
  page shows the wall on the phone with the controller's buttons; `-DebugFakeClip` fakes a
  filmed clip in the simulator.
- The phone UI follows Apple's HIG: system TabView (Make / Memory, hidden on pushed screens),
  NavigationStacks drawn from `AppState.route` (`State/Navigation.swift`; the system back button
  sends Cancel), Settings and A1 as sheets with Forms.
- iPhone and iPad, portrait, full screen. Follows the phone's light or dark appearance.
- English only (localization removed 17 Oct). Strings built in code still go through `L(_:)`,
  dates use `Locale.english`.
- The controller connects on a device. The v4 box (Back, knob encoder, Left, Confirm, Right; power bank) runs `Firmware/controller/`; it compiles but has not run on the box yet. `Firmware/controller_buttons/` is the old breadboard build.
- 56 unit tests in `HeightRitualTests/` pass in the simulator (scheme runs them in English).

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
- UI text: English only, sentence case, no emoji. No string catalogs or translations.
- The controller has five controls: Back (Cancel), the knob, Left, Right and the round Confirm.
  Confirm also starts and stops filming. Show them only with `ControlIcon`.
- Camera, Bluetooth, video writing and the external display cannot be tested in the simulator.
  Say so when a change touches them and has not been run on a device. Never claim they work untested.
- Finish one milestone, build, and report before starting the next.
- When an open question in SPEC section 15 gets settled, update the spec in the same change.
