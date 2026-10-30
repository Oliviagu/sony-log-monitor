import MonitorCore
import SwiftUI

struct ContentView: View {
    @StateObject private var model = MonitorModel()

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                OverlayBar(model: model)
                MonitorView(model: model)
                    .background(Color.black)
                RecordBar(camera: model.camera)
            }
            Divider()
            Sidebar(model: model, camera: model.camera)
                .frame(width: 300)
        }
        .frame(minWidth: 1000, minHeight: 620)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Overlay buttons (top of the picture)

private struct OverlayBar: View {
    @ObservedObject var model: MonitorModel

    var body: some View {
        HStack(spacing: 8) {
            ToggleChip(title: "Rec.709", key: "l", isOn: $model.viewRec709)
            ToggleChip(title: "Zebra", key: "z", isOn: $model.zebraOn)
            ToggleChip(title: "False Color", key: "f", isOn: $model.falseColorOn)
            ToggleChip(title: "Skin", key: "s", isOn: $model.skinOn, tint: Color(red: 0.98, green: 0.50, blue: 0.45))
            Spacer()
            Text(model.viewRec709 ? "Viewing Rec.709 (\(model.profile.rawValue))" : "Viewing raw log")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black)
    }
}

private struct ToggleChip: View {
    let title: String
    let key: KeyEquivalent
    @Binding var isOn: Bool
    var tint: Color = .accentColor

    var body: some View {
        Button { isOn.toggle() } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(isOn ? tint : Color.white.opacity(0.08), in: Capsule())
                .foregroundStyle(isOn ? Color.black : Color.white)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: [])
        .help("\(title) (\(String(key.character).uppercased()))")
    }
}

// MARK: - Record bar

private struct RecordBar: View {
    @ObservedObject var camera: CameraController

    var body: some View {
        HStack(spacing: 14) {
            Button { camera.toggleRecording() } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: camera.isRecording ? 3 : 8)
                        .fill(Color.red)
                        .frame(width: 16, height: 16)
                    Text(camera.isRecording ? "Stop" : "Record")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: [])
            .disabled(!camera.connected)

            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                Text(elapsed(at: ctx.date))
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(camera.isRecording ? Color.red : Color.secondary)
            }
            Spacer()
            Circle().fill(camera.connected ? Color.green : Color.orange).frame(width: 8, height: 8)
            Text(camera.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black)
    }

    private func elapsed(at now: Date) -> String {
        guard let start = camera.recordingStarted else { return "00:00:00" }
        let s = Int(now.timeIntervalSince(start))
        return String(format: "%02d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @ObservedObject var model: MonitorModel
    @ObservedObject var camera: CameraController

    var body: some View {
        Form {
            Section("Camera") {
                Picker("Source", selection: $model.source) {
                    ForEach(SourceKind.allCases) { Text($0.rawValue).tag($0) }
                }
                if model.source == .demo {
                    HStack {
                        Button("Open log clip…") { model.openDemoClip() }
                        Button("Test chart") { (camera as? DemoCamera)?.useTestChart() }
                    }
                } else if !camera.connected {
                    Button("Reconnect") { model.reconnect() }
                }
            }

            Section("Phone view") {
                if let url = model.phoneURL {
                    HStack(alignment: .top, spacing: 12) {
                        if let qr = QRCode.image(for: url) {
                            Image(nsImage: qr).interpolation(.none).resizable().frame(width: 96, height: 96)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Scan with your phone's camera, or open in Safari:")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(url).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                            Text("Phone must be on the same Wi-Fi.").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Not on a network, so phone view is off.").foregroundStyle(.secondary)
                }
            }

            Section("Exposure") {
                if camera.settings.isEmpty {
                    Text("Connect the camera to adjust exposure").foregroundStyle(.secondary)
                }
                ForEach(camera.settings) { s in
                    Picker(s.id.rawValue, selection: Binding(
                        get: { s.value },
                        set: { camera.set(s.id, to: $0) }
                    )) {
                        ForEach(s.options, id: \.self) { Text($0).tag($0) }
                    }
                    .disabled(!s.writable)
                }
                if model.source == .demo {
                    Text("Demo: exposure changes are simulated on the picture.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Log profile") {
                Picker("Convert from", selection: $model.profile) {
                    ForEach(LogProfile.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Follow camera picture profile", isOn: $model.followCameraProfile)
                    .help("PP7/PP8/PP9 switch the Rec.709 view on with the matching curve; other profiles switch it off.")
            }

            Section("Zebra") {
                Picker("Mode", selection: $model.zebraMode) {
                    ForEach(ZebraMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledSlider(label: "Level", value: $model.zebraLevel, range: 0...109, unit: "%")
                if model.zebraMode == .range {
                    LabeledSlider(label: "±", value: $model.zebraTolerance, range: 1...20, unit: "%")
                }
                Toggle("Measure on log signal", isOn: $model.zebraOnLog)
                    .help("Off: zebras read the Rec.709 view. On: they read the raw log signal, like the camera's own zebras.")
            }

            Section("Skin / false color") {
                LabeledSlider(label: "Skin from", value: $model.skinLo, range: 30...90, unit: "%")
                LabeledSlider(label: "Skin to", value: $model.skinHi, range: 30...95, unit: "%")
                FalseColorLegend(skinLo: model.skinLo, skinHi: model.skinHi)
            }
        }
        .formStyle(.grouped)
    }
}

private struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String

    var body: some View {
        HStack {
            Text(label).frame(width: 70, alignment: .leading)
            Slider(value: $value, in: range, step: 1)
            Text("\(Int(value))\(unit)").monospacedDigit().frame(width: 40, alignment: .trailing)
        }
    }
}

private struct FalseColorLegend: View {
    let skinLo: Double
    let skinHi: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(rows, id: \.0) { row in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(row.2).frame(width: 14, height: 10)
                    Text(row.0).font(.caption)
                    Spacer()
                    Text(row.1).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            Text("Measured on the Rec.709 image. 18% grey = 41%.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var rows: [(String, String, Color)] {
        let s = Exposure.salmon
        var r = Exposure.fixedBands.map { b in
            (b.name, range(b.lo, b.hi), Color(red: b.rgb.0, green: b.rgb.1, blue: b.rgb.2))
        }
        r.insert(("Skin", "\(Int(skinLo))–\(Int(skinHi))%", Color(red: s.0, green: s.1, blue: s.2)), at: 3)
        return r
    }

    private func range(_ lo: Double, _ hi: Double) -> String {
        if lo < 0 { return "< \(Int(hi * 100))%" }
        if hi > 1 { return "≥ \(Int(lo * 100))%" }
        return "\(Int(lo * 100))–\(Int(hi * 100))%"
    }
}
