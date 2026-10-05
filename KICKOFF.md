# Kickoff prompt for Claude Code

Open this folder in Claude Code and paste the text below as the first message.

---

Read `CLAUDE.md`, `docs/SPEC.md` and `docs/IMPLEMENTATION.md` completely before writing anything.

Build the Height Ritual iOS app described there. The sources in `reference/v1/` are an older,
never-compiled draft with a different flow: reuse small pieces where IMPLEMENTATION section 4 says
so, but follow the v3 spec.

Work through the milestones in IMPLEMENTATION section 5, starting with milestone 1:

1. Create the source files under `HeightRitual/`, run `xcodegen`, and build for the iOS Simulator
   until the build is clean.
2. Add the unit test target and one test per row of the control table in SPEC section 6.
3. Stop and report: what was built, test results, and anything in the spec that was unclear or
   contradictory.

Then continue with milestones 2 and 3 the same way, stopping after each. Do not start milestone 4
or later until I confirm I have an iPhone and projector connected, because those cannot be
verified in the simulator.

Constraints: iOS 17, SwiftUI, `@Observable`, Swift 5 mode, no third-party packages, no networking.
Keep every screen to one decision and one obvious next action. If the spec does not say what
something should do, choose the simplest behaviour, note it in your report, and add it to SPEC
section 15.
