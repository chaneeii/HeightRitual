import SwiftUI

/// Step 1: who is measured. Knob or arrows move, Confirm continues.
struct SelectChildView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 16) {
            List {
                ForEach(Array(state.store.children.enumerated()), id: \.element.id) { index, child in
                    Button {
                        state.selectChild(index)
                    } label: {
                        HStack {
                            Circle().fill(Palette.color(child.colorIndex)).frame(width: 14, height: 14)
                            Text(child.name).font(.title3)
                            Spacer()
                            if let last = state.store.records(for: child.id).last {
                                Text("Last \(last.heightCM.cmText), \(last.date.monthYear)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if index == state.childIndex {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .listStyle(.insetGrouped)

            FlowButtons(back: "Cancel", next: "Next") {
                state.handle(.cancel)
            } onNext: {
                state.handle(.confirm)
            }
        }
    }
}

/// Step 2: height measured with a real tape, set with the knob or typed in.
struct HeightEntryView: View {
    @Environment(AppState.self) private var state
    @FocusState private var typing: Bool

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            Text(state.currentChild?.name ?? "")
                .font(.title3)
                .foregroundStyle(Palette.color(state.currentChild?.colorIndex ?? 0))

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField("Height", value: $state.draftHeightCM, format: .number.precision(.fractionLength(1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 64, weight: .light, design: .serif).monospacedDigit())
                    .frame(maxWidth: 240)
                    .focused($typing)
                Text("cm").font(.title2).foregroundStyle(.secondary)
            }

            if let last = state.lastRecord {
                Text("\((state.draftHeightCM - last.heightCM).signedCM) since \(last.date.monthYear) (\(last.heightCM.cmText))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("First record for \(state.currentChild?.name ?? "this child")")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                ForEach([-1.0, -0.5, 0.5, 1.0], id: \.self) { step in
                    Button(String(format: "%+.1f", step)) { state.adjustHeight(by: step) }
                        .buttonStyle(.bordered)
                        .font(.body.monospacedDigit())
                }
            }

            Text("Measure with a real tape, then turn the knob or type the number.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)

            FlowButtons(back: "Back", next: "Take photo") {
                typing = false
                state.handle(.cancel)
            } onNext: {
                typing = false
                state.adjustHeight(by: 0)
                state.handle(.confirm)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { typing = false; state.adjustHeight(by: 0) }
            }
        }
    }
}

/// Step 3: whole body in frame, countdown, photo.
struct CaptureView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                CameraPreview(session: state.camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.white.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .padding(24)
                    .allowsHitTesting(false)

                VStack {
                    Text("Whole body in the frame, head to feet")
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(.top, 32)
                    Spacer()
                }

                if let n = state.countdown {
                    Text("\(n)")
                        .font(.system(size: 120, weight: .light, design: .serif))
                        .shadow(radius: 8)
                }
                if state.isProcessing {
                    ProgressView("Cutting out the photo")
                        .padding()
                        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                }
            }

            Text("\(state.currentChild?.name ?? "") · \(state.draftHeightCM.cmText)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            FlowButtons(back: "Back", next: state.countdown == nil ? "Start 3 s countdown" : "Counting") {
                state.handle(.cancel)
            } onNext: {
                state.handle(.confirm)
            }
            .disabled(state.isProcessing)
        }
    }
}

/// Step 4: check the cut-out, then save or retake.
struct ReviewView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Checkerboard().clipShape(RoundedRectangle(cornerRadius: 12))
                if let image = state.cutout {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(12)
                }
            }
            Text("\(state.currentChild?.name ?? "") · \(state.draftHeightCM.cmText) · \(Date.now.monthYear)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Text("The head and feet should touch the top and bottom of the cut-out, so the wall shows it life-size.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            FlowButtons(back: "Retake", next: "Save") {
                state.handle(.cancel)
            } onNext: {
                state.handle(.confirm)
            }
        }
    }
}

struct FlowButtons: View {
    let back: String
    let next: String
    let onBack: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) { Text(back).frame(maxWidth: .infinity) }
                .buttonStyle(.bordered)
            Button(action: onNext) { Text(next).frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
    }
}

struct Checkerboard: View {
    var body: some View {
        Canvas { ctx, size in
            let cell: CGFloat = 12
            for row in 0..<Int(size.height / cell) + 1 {
                for col in 0..<Int(size.width / cell) + 1 where (row + col).isMultiple(of: 2) {
                    let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                    ctx.fill(Path(rect), with: .color(.white.opacity(0.06)))
                }
            }
        }
        .background(Color(white: 0.1))
    }
}
