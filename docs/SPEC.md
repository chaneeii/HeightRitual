# Height Ritual: iOS App Spec (v3)

KTH DM2601 (Media Technology and Interaction Design), Group 6. Hi-fi prototype and workbook due
22 Oct 2026; exhibition in week 43.

Version 3, 5 Oct 2026. This version follows the team's wireframes and controller sketch.
Changes from v2: two modes (Make, Memory) as the app's top level; "family member" instead of
"child"; recording order is member, film, height; the height is pre-filled by an estimate from
the video; auto play / manual in Memory; new controller layout (separate Cancel, auto play toggle,
no Playback or Push button); setup pages for wall fit, camera position,
units and permissions; a foot guide while filming.

The Swift sources in this repository are a v1 draft (still photo, different flow) that was never
compiled. This spec wins wherever they disagree. See `docs/IMPLEMENTATION.md`.

## 1. What it is

Families mark a child's height on a wall or doorframe. The mark is bound to a place the child
eventually leaves, and it is lost when the family moves or repaints.

Height Ritual keeps the ritual and makes the record portable. A family member stands at the wall
and is filmed for a few seconds; the app suggests their height and a parent corrects it. Later
the app projects every past record back onto the wall: the person cut out of the video,
life-size, at their real height, with pencil-like marks for each record.

Design rule for every screen: **one decision per screen, one obvious next action, large targets.**
The hardware setup is already hard; the app must not add to it.

## 2. System

| Part | Role |
|---|---|
| iPhone (iOS 17+) | Brain: app logic, camera, storage, projector output. Stands upright on a fixed stand next to the projector, rear camera facing the wall |
| Projector | Shows the wall image through a USB-C to HDMI (or Lightning Digital AV) adapter |
| Controller | Box with a knob, buttons, two switches and a light. ESP32, Bluetooth LE |

Decisions made:

- iPhone or iPad (iPad mini on the stand works too), portrait, full screen, iOS 17+, SwiftUI.
  No third-party packages. No networking.
- No wall tape unit and no keyboard input.
- A record is a video clip of about 5 seconds, cut out per frame and played life-size.
- The height is estimated from the video and pre-filled; the user can correct it before saving.
- Sound is optional: a setting, off by default.
- Any number of records per member, ordered by date, labelled with month and year.
- Heights are stored in millimetres; the display unit (cm or ft/in) is a setting.
- The projected image covers the wall from the floor to at least 170 cm.

## 3. Features

### Core

| # | Feature | Why |
|---|---|---|
| C1 | Life-size projection at the real height | The body is the recording medium |
| C2 | Height record: video, height and date each time the family measures | The act of measuring is the ritual |
| C3 | Travel through records with the knob, or let them play by themselves | Replaces following the pencil marks with a finger |
| C4 | Tangible wireless controller | The family looks at the wall, not at a phone |
| C5 | Portable record stored on the phone | The record survives moving and repainting |

### Supporting

| Feature | Supports | Priority |
|---|---|---|
| Setup: fit to wall, camera position | C1 | P0 |
| Background removal for every video frame | C1, C2 | P0 |
| Foot guide while filming | C2 | P0 |
| Height estimate from the video, editable | C2 | P0 |
| Family members: add, rename, remove | C5 | P0 |
| Auto play and manual in Memory | C3 | P0 |
| Bluetooth connects and reconnects without user action | C4 | P0 |
| Every controller action also available on the phone screen | C4 | P0 |
| Edit or delete one record; delete everything | C5 | P0 |
| Units (cm, ft/in) and permissions pages | | P0 |
| Sample family on first launch | C3 | P0 |
| Light shows the recording state | C4 | P1 |
| Live check that the person stands on the foot guide | C2 | P1 |
| Sound recorded and played with the clip | C2 | P2, optional |
| Members side by side, export, LiDAR height | | P2 |

P0 = needed for the user test. P1 = needed for the exhibition. P2 = if time allows.

## 4. App structure

Two modes at the top level, shown as two large tabs at the bottom of the home screen, and a
Settings button at the top right. The controller's mode switch selects the same two modes.

```
                         Settings (top right)
                               |
       +-----------------------+------------------------+
       |                                                |
   MAKE mode                                      MEMORY mode
   M1 Choose a family member                      R1 Choose a family member
   M2 Film  (ready, countdown, filming)           R2 Wall  (manual | auto play)
   M3 Height (cutting out, estimate, Save)             |
       |                                          R3 One record (edit, delete)
       +--> saved: opens R2 for that member with the new record selected
```

First start runs a setup wizard: permissions, fit to wall, camera position.
Each step can be reopened from Settings.

## 5. Screens

| # | Screen | Phone shows | Wall shows |
|---|---|---|---|
| H | Home | The tab bar (Make, Memory) is Home; the app opens on R1. Settings button in the navigation bar. Status chips for projector and controller | As R1 |
| M1 | Make: choose a family member | Grid of members (name, colour, last height), a + tile | Highlighted member's name, faint marks |
| M2 | Make: film | Camera preview with the foot guide (section 8), one red button. States: ready, countdown 3-2-1, filming with seconds left | Ready: foot marks and an outline where to stand. Countdown and filming: dark, only the number |
| M3 | Make: height | While cutting out: progress. Then the looping cut-out, the height in a large field (pre-filled), + and -, the note about the estimate, Save, Retake | The cut-out life-size at the shown height, with a dashed line that follows the number |
| R1 | Memory: choose a family member | Same grid as M1, without + | Highlighted member's name, faint marks |
| R2 | Memory: wall | Segmented control "Auto play / Manual" at the top. Copy of the wall. Manual: Previous, Next, Replay. Auto play: Stop. No Record: filming is only in Make | Marks for all records; the selected record's clip life-size; caption "Nora, Aug 2025, 121.0 cm". Auto play: each record in order |
| R3 | One record | Clip, date, height, growth since the record before. Change height, Delete | Unchanged |
| A1 | Add or edit member | Name, colour, Delete member | Unchanged |
| S | Settings | List: Family, Setup guide, Fit to wall, Camera position, Units, Point colour, Sound, Controller, Permissions, Sample family, Delete everything | Back icon top left, the same items as rounded tiles in two columns with their current values, Setup guide as a pill beside the title; the controller's choice outlined in orange |
| S2 | Fit to wall | Two sliders (floor line, size), fine-step toggle | Centimetre ruler: 0, 100, 150 highlighted, dashed line at 170 |
| S3 | Camera position | Camera preview with two draggable lines: floor and 100 cm. Text: put them on the projected lines | Two bright lines at 0 and 100 cm |
| S4 | Units | cm or feet and inches; choosing one saves it and goes back to the list | Back icon, "Units", the two units with the saved one ticked and the controller's choice outlined in orange |
| S5 | Permissions | Camera, Bluetooth, Microphone (only if sound is on): state of each, button to open iOS Settings | Back icon, "Permissions", each permission with Allowed / Not asked yet / Not allowed (display only) |
| S6 | Controller | Connected or searching, last control used (for testing), Forget this controller | Unchanged |
| W | First-start wizard | S5, S2, S3 in order with Next and Skip | As in each step |

States, not separate screens:

| State | Where | What the phone shows |
|---|---|---|
| No members yet | M1, R1 | "Add the first family member" and the + tile |
| No records yet | R2 | "No records yet. Switch to Make to film one." |
| No projector | Everywhere | Chip "No projector"; the wall copy on the phone is the only picture |
| Controller not found | Everywhere | Chip "Searching for controller"; all on-screen buttons still work |
| Setup not done | M2, R2 | Banner "Finish setup for true size" linking to the wizard |
| No person found | M3 | "Nobody found in the video", Retake |
| Permission denied | M2 | Explanation and a button to S5 |

## 6. Controller

The box, seen from above (19 Oct; replaces the 5 Oct sketch). Powered by a USB power bank.

```
 [ Back ]                    ( Knob )

 < Left       ( Confirm )      Right >
```

| Control | Part | Sends |
|---|---|---|
| Back | Momentary push button | Press |
| Knob | Rotary encoder (EC11 / KY-040), endless, with clicks | Relative clicks, + clockwise |
| Left, Right | Momentary push buttons | Press |
| Confirm | Round momentary push button; also starts and stops filming | Press |

No mode switch, Record button, auto play switch or recording light any more. The app shows the
mode, starts filming on Confirm and auto play is a setting. The light characteristic stays in the
protocol and drives the LED on the ESP32 board, which is not visible in the closed box.

The controller only reports what was used. The app decides what it means.

### What each control does on each screen

| Screen | Knob | Left / Right | Confirm | Back |
|---|---|---|---|---|
| Home wheel | Turn the wheel | Previous / next member | Open the member menu | |
| Member menu | Record or Lookback | Record / Lookback | Choose | Close the menu |
| Add member (letter wheel) | Move through the keys | Previous / next key | Press the key (a letter, delete or done) | Back to home |
| Film: ready | | | Start filming (3-2-1, then 5 s) | Back to the member menu |
| Film: filming | | | Stop early | Discard, back to ready |
| Height check | +/- 0.1 cm per click | -1 / +1 cm | Save | Retake |
| Saved | | | See the growth (Lookback) | Return to home |
| Lookback | Previous / next record | Previous / next record | Replay the clip | Back to the member menu |
| Lookback, auto play on | Stop, then move | Stop, then move | Stop | Stop |
| Settings on the wall (grid) | Move through Setup guide and the tiles | Previous / next | Open (Setup guide, Fit to wall, Units, Permissions so far) | Close Settings |
| Settings: Units | Choose a unit | Centimetres / feet and inches | Save, back to the grid | Back to the grid |
| Settings: Permissions, Setup guide | | | | Back to the grid |
| Settings: Fit to wall | Change selected value | Floor line / Size | Done | Done |
| Onboarding with the controller | As each step says | | Next | Previous step |

In ft/in the knob and Left / Right step by 1/4 inch and 1 inch.

### Bluetooth LE protocol

Device name `MemoryMeter` (was `HeightController`). No pairing; the app finds it by service UUID.

| Item | UUID | Properties |
|---|---|---|
| Service | `6F1D0001-8A3C-4B6E-9A51-2C7E0B1D4A01` | |
| Input | `6F1D0002-8A3C-4B6E-9A51-2C7E0B1D4A01` | notify, 2 bytes `[controlId, value]` |
| Light | `6F1D0003-8A3C-4B6E-9A51-2C7E0B1D4A01` | write, 1 or 2 bytes `[recording, mode]` |

| controlId | Event | value (signed 8-bit) |
|---|---|---|
| 1 | Knob turn | Clicks since the last packet, + clockwise |
| 13 | Confirm | 1 |
| 14 | Left | 1 |
| 15 | Right | 1 |
| 23 | Back | 1 |

| Light byte | Value | Meaning |
|---|---|---|
| recording | 0 | Off |
| | 1 | Slow blink: countdown |
| | 2 | Steady: filming or cutting out |
| | 3 | Three quick flashes, then off: saved |

Debounce (25 ms) is done in the firmware; knob clicks are summed and sent at most every 20 ms.
The app ignores an identical non-knob event within 100 ms. The app still understands 11 (Record),
31 (Mode) and 32 (Auto play) from the older boxes; the v4 box does not send them.

Settings > Controller shows the box drawn as above and a checklist (Back, knob both ways, Left,
Confirm, Right) that fills in as each packet arrives, plus the raw packets.

## 7. Setup

### Setup guide

Two pictures with the steps written below them: the projector lens 2.5 m from the wall and 0.97 m
above the floor; the phone right next to it at the same distance and height, rear camera facing the
wall, the parent behind them with the controller. Tapping a picture shows it full size with Done. The projector shows the same two pictures, with
the back icon and the title.
Sources: `docs/setup-guide/`.

### S1 Projector placement (removed)

There is no placement page. The projector is placed by hand; the picture must reach at least 170 cm
(the ruler on the wall shows "Top of picture" while fitting). The wall image is always turned -90 degrees: the group's projector lies on its
side (no rotation setting since 19 Oct).

### S2 Fit to wall

Calibration holds three values: `floorPt` (points from the bottom edge to the floor line),
`ptPerCM`; `rotation` is fixed at -90 degrees. The drawing is always centred left to right.
`y(cm) = imageHeight - floorPt - cm * ptPerCM`.

Procedure: tape marks on the wall at 0 and 100 cm; move the floor line until the projected 0 sits on
the floor; change the size until the projected 100 sits on the tape; check 150. The page states
the highest visible centimetre; it must be 170 or more.

### S3 Camera position

Tells the app where the wall's floor line and 100 cm line are in the camera picture. The wall
shows two bright lines; the user drags two lines in the preview onto them. Stored as
`floorY` and `y100` (fractions of the upright frame height) and `centerX`.

Used for the foot guide (section 8) and the height estimate (section 9). It is valid only while
the phone stays on its stand; the page says so. Moving the phone means doing S3 again.

## 8. Foot guide (M2)

Drawn over the camera preview, from the camera position values:

- a horizontal **floor line** at `floorY` with two foot marks centred on `centerX`;
- a standing **outline** from the floor line up to the member's last height plus 10 cm
  (first record: 120 cm), so the user sees how much room is needed;
- one line of text: "Heels on the line, back against the wall".

On the wall, in the ready state: two foot marks at the floor line and the same outline, so the
person can find the spot without looking at the phone. The wall goes dark at the countdown.

P1: while ready, the app runs person segmentation a few times per second. The guide turns green
when the feet are within 3 cm of the floor line, the head is below the top of the picture and the
whole body is in the frame. It never blocks filming.

Without camera position values the guide falls back to a fixed outline at the centre of the preview.

## 9. Recording pipeline

1. **Capture.** Rear camera, 1080p, 30 fps, 5 s. Audio input only when sound is on.
2. **Reference.** The person stands still for the first half second. The median head-to-feet box of
   those frames gives `bodyHeightPx` and the head top `headY`.
3. **Height estimate.** `cm = (floorY - headY) * 100 / (floorY - y100)`, rounded to 0.5 cm.
   Without camera position values, or if the result is outside 40 to 220 cm, the field starts
   at the member's last height (first record: empty, the user must enter it).
4. **Cut out.** Person segmentation for every frame, mask blended over a clear background.
5. **Crop.** One fixed rectangle for the clip: the union of the person boxes over all frames.
6. **Write.** HEVC with alpha, about 1280 px tall, audio copied if present. A poster PNG is saved for lists.
7. **Layout numbers:** `bodyRatio = bodyHeightPx / clipHeightPx`,
   `floorRatio = distance from the clip's bottom edge to the standing feet / clipHeightPx`.

On the wall the clip is drawn with height `heightCM * ptPerCM / bodyRatio`, the standing feet on the
floor line. The saved (user-corrected) height is always the one used.

Note shown under the height field whenever it was pre-filled from the video:
"Estimated from the video. It can be a few centimetres off. Check with a tape and correct it."
A field the user has changed shows no note.

About the estimate: Apple's Measure app has no public interface for its person-height feature, so
the app computes its own. The method above works on any iPhone because it uses the calibrated
wall as the ruler. Its error comes from the person standing in front of the wall plane, hair,
shoes and a tilted phone; the size of the error has not been measured yet. A LiDAR-based
estimate with ARKit is possible on Pro models and is a P2 alternative.

Playback uses one `AVPlayer` owned by `AppState`, with an `AVPlayerLayer` in the wall scene and one
in the phone's wall copy. In manual a clip plays once and holds its last frame. Auto play shows
every record from first to newest, each for the length of its clip, then starts again until stopped.

Not yet verified on a device: transparent HEVC composited by `AVPlayerLayer` over black on the
external display; two layers on one player; segmentation time for 150 frames; estimate accuracy.

## 10. The wall image

- Layers, bottom to top: black background; marks and captions; the transparent video.
- Thin warm off-white lines like pencil marks, italic serif labels. The selected record uses the
  member's colour. The line for a record being made is dashed coral.
- Heights on the wall follow the unit setting.
- A member taller than the top of the picture is shown cut off, with the caption still visible.

## 11. Data

Stored only in the app's Documents folder. Nothing leaves the phone.

```
Member       { id: UUID, name: String, colorIndex: Int }
GrowthRecord { id: UUID, memberID: UUID, date: Date, heightMM: Int,
               heightSource: "estimated" | "edited" | "sample",
               videoFile: String?, posterFile: String?, hasSound: Bool,
               bodyRatio: Double?, floorRatio: Double? }
Settings     { unit: "cm" | "ftin", soundOn: Bool, autoPlay: Bool,
               wall: Calibration, camera: CameraPosition? }
```

- `Documents/records.json`, `Documents/media/<uuid>.mov`, `Documents/media/<uuid>.png`.
- Settings in UserDefaults.
- Sample family: Nora with six records, Leo with four, no clips (shown as soft outlines).
- "Delete everything" removes members, records and media; setup values stay.

## 12. Requirements

| ID | Requirement | P |
|---|---|---|
| W1 | With a projector connected, the projector shows only the wall image; the phone shows controls | P0 |
| W2 | Without a projector the phone's wall copy shows the same image | P0 |
| W3 | Everything on the wall is positioned in real centimetres from the floor | P0 |
| W4 | After S2 a projected 100 cm line is within 1 cm of a real 100 cm mark, 150 within 1.5 cm | P0 |
| W5 | The wall image can be rotated for a projector on its side; the screen stays awake | P0 |
| S2 | Camera position stores floor and 100 cm lines; the foot guide and the estimate use them | P0 |
| S3 | The wizard runs on first start and every step can be skipped and reopened | P0 |
| S4 | Units can be switched at any time without changing stored heights | P0 |
| S5 | The permissions page shows the state of each permission and opens iOS Settings | P0 |
| M1 | Make has three steps: who, film, height. Cancel at any step keeps nothing | P0 |
| M2 | Film: one button starts a 3 s countdown and 5 s of video; pressing again stops early | P0 |
| M3 | The foot guide is shown on the phone and, before the countdown, on the wall | P0 |
| M4 | After filming, the height field is pre-filled with the estimate and the note is shown | P0 |
| M5 | Height is 40 to 220 cm in 0.5 cm steps (or 1/4 in); the wall follows the number live | P0 |
| M6 | Save writes the record and opens Memory for that member with the new record selected | P0 |
| M7 | If nobody is found in the video the app says so and offers Retake | P0 |
| R1 | Memory shows a mark for every record of the member and the selected record's clip life-size | P0 |
| R2 | Manual: knob and Left / Right step through records; Confirm replays | P0 |
| R3 | Auto play runs through all records until any control is used | P0 |
| R4 | A record's height can be corrected and a single record deleted | P0 |
| B1 | The app finds the controller by service UUID, remembers it and reconnects by itself | P0 |
| B2 | Every control event goes through `AppState.handle(_:)`; phone buttons send the same events | P0 |
| B3 | Every screen can be completed on the phone alone | P0 |
| B4 | The app writes the light state | P1 |
| D1 | Members can be added, renamed, recoloured and removed | P0 |
| D2 | Sample family on first launch; "Delete everything" in Settings | P0 |
| X1 | Sound recorded and played with the clip; microphone requested only then | P2 |

## 13. iOS specifics

| Area | Framework | Notes |
|---|---|---|
| UI, state | SwiftUI, Observation | One `@MainActor @Observable AppState`, shared by both scenes |
| Projector | UIKit scenes | `UIWindowSceneSessionRoleExternalDisplayNonInteractive` |
| Controller | CoreBluetooth | Central role |
| Capture | AVFoundation | `AVCaptureMovieFileOutput`; audio session only with sound on |
| Cut-out, estimate | Vision, CoreImage | `VNGeneratePersonSegmentationRequest` |
| Write, play | AVFoundation | `AVAssetReader`, `AVAssetWriter` (`.hevcWithAlpha`), `AVPlayer` |

`Info.plist`: `NSCameraUsageDescription`, `NSBluetoothAlwaysUsageDescription`,
`NSMicrophoneUsageDescription`, portrait only, external display scene configuration.
Camera, Bluetooth and the external display cannot be tested in the simulator.

## 14. Acceptance test

On a real iPhone on its stand, projector connected.

1. First start: the wizard asks for camera and Bluetooth, then shows fit to wall and camera position.
2. Fit to wall against tape marks at 0 and 100 cm. Projected 150 is within 1.5 cm of a real 150.
3. Camera position: the two lines are placed on the projected lines.
4. Memory, Nora (sample): six marks; the knob moves through them; auto play runs and any button stops it.
5. Make, Nora: the foot guide is on the phone and the wall. Record: countdown, 5 s clip of a
   person who raises an arm.
6. Height opens with an estimate and the note. The estimate is within 3 cm of a tape measurement
   (target, not yet verified). Correct it; the wall follows. Save.
7. Memory opens with the new record; the standing head is at the saved height; the arm is not cut off.
8. One record: change the height, then delete the record.
9. Units: switch to ft/in; every height on the phone and the wall changes; switch back.
10. Controller off and on: Searching, then Connected, with no user action. Mode switch changes the tab.
11. Settings, Delete everything: no members, no records, media folder empty; setup values kept.

## 15. Open questions

- Which iPhone will be used at the exhibition (needed for the adapter and for the LiDAR option)?
- Are the two mode lights on the controller wanted, or only the recording light?
- Clip length (5 s assumed). Auto play: loop until stopped (assumed) or run once?
- Sound: projector speaker or phone speaker?
- Should adults be recorded too? The picture reaches about 176 cm; taller people are cut off.
- Can the projector run on its side without overheating?

Assumed in milestone 1 (simplest behaviour; confirm or change):

- Home is shown only at launch, before a mode is chosen. Choosing a tab or moving the mode switch
  opens M1 or R1; the tabs stay visible on M1 to R3.
- A mode switch position equal to the current mode is ignored, so the report sent on every
  reconnect does not move the user. On Home after launch the first report does open M1 or R1.
- Cancel on M1 and R1 does nothing (the table leaves it empty).
- Record / Stop during the countdown goes back to ready, like Cancel: nothing has been filmed yet.
- In auto play, Record / Stop also stops auto play without filming ("until any control is used").
- On "Nobody found", Confirm also means Retake.
- Turning the knob on an empty height field (first record, no estimate) starts from 100 cm.
- Save after a record goes to Memory in manual, even when auto play was last chosen, so the new
  record stays selected.
- The controller does nothing on R3, A1, the settings list pages other than fit to wall (Cancel goes
  back) and the wizard steps other than fit to wall.
- "Not saved" is shown when filming, cutting out or the height step is left for a screen outside
  Make (mode switch or Settings). Retake and Cancel back to ready discard without the notice.
- Screens whose wall column says "Unchanged" (A1, S, S4 to S6) show the faint ruler of Home.
  R3 shows the memory wall with that record.
- Until a projector is connected, the phone's wall copy assumes a 1920 x 1080 picture.
- R2 always shows the selected record (date, height, growth) under the wall copy; tapping it opens R3.
- The wall image is always turned -90 degrees (projector on its side); there is no rotation setting.
- The Settings button is hidden during the wizard; the wizard is left only by Next, Skip or Finish.
- Bluetooth permission is asked when "Allow" is pressed on S5, not at launch.
- S2 has, per value, a slider and - / + buttons (one knob step each); tapping a value selects it for the knob.
- S6 is a test page: it lists every packet (raw bytes and meaning) and has light test buttons.
  While S6 is open, controller events are only listed, not acted on (also the mode switch).
- The controller chip shows the Bluetooth state ("Bluetooth not allowed", "Bluetooth off",
  "Searching for controller", "Connecting to controller") and opens S5 or S6 when tapped.
- Changed 5 Oct (team): Memory has no Record. Filming starts only in Make (mode switch or tab),
  so the mode switch always matches what the app does.
- Changed 6 Oct (team): the phone UI follows Apple's Human Interface Guidelines: a system tab bar
  for Make / Memory (hidden while filming), NavigationStacks with the system back button (it sends
  Cancel / Back), Settings as a sheet with grouped lists, A1 as a sheet from M1. The phone follows
  the phone's light or dark appearance (no setting since 19 Oct); the wall image is always black. The wall copy has a full-screen
  button. The grid title is "Choose a family member".
- Changed 6 Oct (team):
  - First start shows three welcome pages (what it is, Make, Memory) before setup; "Set up later"
    skips setup, which stays reachable from the banner and Settings.
  - Each record keeps the clip as filmed besides the cut-out. Memory has a Show background button:
    off shows only the person (default), on shows the clip as filmed. About twice the storage.
  - M3 shows a still from the reference half second with the found head top (dotted) and the height
    in the field (dashed, needs the camera position). "Nobody found" also offers "Use this clip
    anyway", which keeps the clip as filmed with the height set by hand (testing without a person).
  - The cut-out writes no sound yet; the clip as filmed keeps it.
  - The wall uses only a portrait strip of the projected picture: 9:16, the picture's full height
    (so the reach from the floor does not change), black elsewhere. The strip is centred in a wide
    picture. Every copy of the wall on the phone (R2, M3, S2, full screen) shows
    exactly that strip, upright, so it reads like the phone itself (decided 12 Oct).
  - Redesign (17 Oct, Figma "Ritual", branch feature/new-design). Members come first: Home is a
    wheel of member cards with an Add card last (knob and Left / Right turn it, Confirm opens).
    Choosing a member darkens Home and offers Record or Lookback; Cancel goes back to the wheel.
    A member is added from an endless letter wheel (Delete, Save, A to Z). The mode switch only
    preselects Record (Make) or Lookback (Memory) on that menu. Every screen has a phone version
    (touch) and a wall version (608 x 1080 strip, controller only, cursor and thick border on the
    selection). Confirm turns the wall's check green for a moment before the choice opens.
  - Recording has no countdown: Record films five seconds at once, with a bar and the seconds
    left. The height is checked on a dial (knob 0.5 cm, Left / Right 1 cm, dragged on the phone),
    then a Saved screen offers the member's growth (Confirm) or Return to home (Cancel). Lookback on
    the wall lays the date, height, growth and story segments over the life-size clip; its hint
    goes away at the first move. Black and white for now; colours and fonts come from `Theme`.
  - English only: the language setting and the translations are removed (17 Oct).
  - The controller now has five controls: Back (Cancel), the knob, Left, Right and the round
    Confirm. Record, the mode switch and the auto play switch are gone; Confirm starts filming
    and stops it early. The app still accepts their old codes, so older firmware keeps working.
  - Settings > Onboarding with controller (demo, 17 Oct): ten guided steps on the phone and the
    wall, with the controller drawn underneath and only the controls of that step in colour (the
    drawing can be tapped like the box). The name picked becomes a member, the dial's height its
    first record; the last step opens Home on that member. Back is a step back throughout.
  - On the height check the knob steps 0.1 cm (Left / Right stay 1 cm); the dial has a tick per
    millimetre (17 Oct).
  - Settings > Point colour (19 Oct): black by default, or one of the member colours. Used for
    selection borders, the main button, the dial's needle, the filming bar, the saved check and
    the cursor; text stays black.
