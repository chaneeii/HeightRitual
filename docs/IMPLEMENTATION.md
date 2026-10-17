# Height Ritual: Implementation Guide

Read `docs/SPEC.md` (v3) first. This file says how to build it and in which order.

## 1. Starting point

- `HeightRitual/` contains only `Info.plist`. Write the app from the spec.
- `reference/v1/` is an earlier draft: still photo, View/Record flow, never compiled. Reuse ideas and
  small pieces (see section 4), not its structure.
- `Firmware/controller/controller.ino` matches SPEC section 6 and has never been flashed.
- Nothing in this repository has run on a device.

## 2. Stack

- iOS 17.0+, iPhone, portrait. Swift 5 language mode, SwiftUI, Observation.
- Apple frameworks only: SwiftUI, UIKit, CoreBluetooth, AVFoundation, Vision, CoreImage.
- XcodeGen (`project.yml`). Add a unit test target `HeightRitualTests` in milestone 1.

```
brew install xcodegen
xcodegen
xcodebuild -project HeightRitual.xcodeproj -scheme HeightRitual \
  -destination 'generic/platform=iOS Simulator' build
```

## 3. Architecture

```
ESP32 controller --BLE--> ControllerManager --+
                                              +--> AppState.handle(ControlEvent)
Phone buttons ---------------------------------+            |
                                                           |  mode + route state machine
   Store <--> AppState <--> CameraController, VideoCutout, HeightEstimator, WallPlayer
                 |
      +----------+-----------+
      v                      v
 RootView (phone)      WallView (external display scene)
```

1. `AppState` is the single source of truth: `@MainActor @Observable`, shared by both scenes.
2. Every input is a `ControlEvent` and goes through `AppState.handle(_:)`. A phone button calls
   `handle` with the same event the controller would send.
3. `mode` (make, memory) and `route` change only through `go(to:)`, which also starts and stops
   the camera, the player and the light.
4. The wall is drawn from a value snapshot (`WallModel`) in real centimetres through `WallGeometry`.
5. Hardware sits behind protocols (`CameraProviding`, `StoreProviding`, `ControllerLink`) so the
   state machine can be unit tested without devices.

```
enum Mode  { make, memory }
enum Route { home
             makeWho, makeFilm(FilmState), makeHeight(HeightState)
             memoryWho, memoryWall, record(UUID)
             settings(SettingsPage), wizard(step) }
enum FilmState   { ready, countdown(Int), filming(secondsLeft) }
enum HeightState { cuttingOut(progress), editing, noPerson }
enum ControlEvent { knob(Int), left, right, confirm, cancel, record, autoPlayToggle, mode(Mode) }
```

## 4. File map

| File | Responsibility | From v1 |
|---|---|---|
| `App/HeightRitualApp.swift` | `@main`, injects `AppState.shared` | reuse |
| `App/ExternalSceneDelegate.swift` | Scene for the projector, hosts `WallView` | reuse |
| `State/AppState.swift` | Mode, route, `handle(_:)`, sessions, auto play, light | rewrite |
| `Input/ControlEvent.swift` | Events, light patterns | rewrite |
| `Input/ControllerManager.swift` | CoreBluetooth central, reconnect, packet parsing, light writes | adapt IDs |
| `Model/Models.swift` | `Member`, `GrowthRecord`, palette | adapt |
| `Model/Store.swift` | JSON and media files, sample family, delete all | adapt |
| `Model/SettingsStore.swift` | Unit, sound, projector, wall calibration, camera position | new |
| `Model/HeightFormatter.swift` | mm to "121.0 cm" or "3 ft 11 3/4 in", step sizes | new |
| `Capture/CameraController.swift` | Session, movie output, preview layer | rewrite |
| `Capture/VideoCutout.swift` | Reader, per-frame segmentation, crop, alpha HEVC writer, poster | new (v1 `PersonCutout` shows the mask blend) |
| `Capture/HeightEstimator.swift` | Reference box, estimate from camera position | new |
| `Capture/FootGuide.swift` | Overlay geometry, optional live check | new |
| `Playback/WallPlayer.swift` | One `AVPlayer`, play once and hold, auto play sequencing | new |
| `Wall/WallModel.swift`, `Wall/WallView.swift` | Snapshot per route, `WallGeometry`, drawing, video layer | adapt |
| `Phone/RootView.swift` | Tabs, status chips, route switch | rewrite |
| `Phone/MemberGridView.swift` | M1, R1, add tile | new |
| `Phone/FilmView.swift` | M2 | new |
| `Phone/HeightView.swift` | M3 | new |
| `Phone/MemoryWallView.swift` | R2 with auto play / manual | new |
| `Phone/RecordDetailView.swift`, `Phone/MemberEditView.swift` | R3, A1 | new |
| `Phone/Settings/*.swift` | S, S1 to S6, wizard | S2 from v1 `CalibrationView` |

## 5. Milestones

Do them in order. Each ends with a build and the stated check. Report after each one.

| # | Milestone | Check |
|---|---|---|
| 1 | **Skeleton.** Project builds; models, store with sample family, settings store, `HeightFormatter`, `AppState` with all routes and `handle(_:)`; unit tests for the control table in SPEC section 6 | Tests pass; app launches to Home |
| 2 | **Memory without video.** Home tabs, member grid, memory wall with marks and outlines, manual and auto play (timer of 1.5 s for records without a clip), phone wall copy | In the simulator: SPEC acceptance step 4 with on-screen buttons |
| 3 | **Settings.** Family, units, permissions page, projector placement maths, fit to wall, delete everything, wizard shell | Unit switch changes every height; placement shows 2.56 m for 0.8 upright |
| 4 | **Projector (device).** External display scene, rotation, fit to wall on a real wall | SPEC acceptance step 2 |
| 5 | **Film (device).** Camera preview, foot guide, countdown, 5 s movie file, camera position page | A .mov is written; the guide sits on the projected floor line |
| 6 | **Cut out and estimate (device).** `VideoCutout`, `HeightEstimator`, height screen, save | SPEC acceptance steps 5 and 6 |
| 7 | **Clip playback (device).** `WallPlayer`, video layer on wall and phone, play once and hold, auto play by clip length, record detail | SPEC acceptance steps 7 and 8 |
| 8 | **Controller (device).** Flash firmware, connect, light | SPEC acceptance step 10 |
| 9 | **Polish.** Empty states, banners, live foot check, haptics on save | Full acceptance test |
| 10 | P2 items only after the user test | |

Milestones 1 to 3 need only the simulator. From 4 on, a real iPhone is required; do not mark them
done without a device run by the user.

## 6. Risks to check early

| # | Where | Risk | If it fails |
|---|---|---|---|
| 1 | External scene | With the SwiftUI lifecycle the plist entry alone may not be picked up; the projector would mirror the phone | Add `UIApplicationDelegateAdaptor` and return the configuration in `application(_:configurationForConnecting:options:)`. Done; on an iPhone 12 with a Lightning HDMI adapter it still mirrored, because iOS 27 apps built with the iOS 27 SDK need a SwiftUI scene accessory (`ExternalNonInteractiveAccessory`, as in TimeCapsule). Added in `HeightRitualApp`, with `UIApplicationSupportsMultipleScenes` true (not yet retested) |
| 2 | Alpha video | `AVPlayerLayer` may not composite transparent HEVC over the wall drawing | Render frames through `AVPlayerItemVideoOutput` into a Core Image backed view |
| 3 | Two layers, one player | The phone copy and the wall may not both play | Phone shows the poster and a progress bar only |
| 4 | Cut-out time | 150 frames of `.accurate` segmentation may take too long | `.balanced`, 15 fps, or shorter clips |
| 5 | Crop orientation | Core Image origin is bottom-left, mask boxes are top-left | Fix the y conversion; test with a raised arm |
| 6 | Estimate accuracy | Person stands in front of the wall plane; phone tilt | Show the note, keep the field editable; measure the error and report it |
| 7 | Camera position drift | The phone is moved after setup | Banner when the estimate is implausible; page to redo S3 |
| 8 | Latching auto play switch | Its position can disagree with the app | Treated as a toggle on every change (already in firmware) |
| 9 | Firmware | NimBLE 2.x callback signatures | Adjust to the installed library version |

## 7. Conventions

- UI text in English, sentence case, no emoji. Member-facing words: "Make", "Memory", "Choose a family member",
  "Film", "Height", "Save", "Retake".
- Heights: `heightMM: Int` in storage; formatted only by `HeightFormatter`.
- Wall drawing in centimetres through `WallGeometry`; never hard-code points for wall positions.
- New inputs produce `ControlEvent` values; new screens add a `Route` case, a branch in
  `handle(_:)` and in `AppState.wallModel`, and a unit test row.
