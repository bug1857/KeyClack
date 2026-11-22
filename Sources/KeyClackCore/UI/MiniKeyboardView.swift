import SwiftUI

/// Compact, interactive MacBook keyboard strip that lights up live physical keystrokes
/// and allows clicking any key directly to audition stereo panning and stabilizer sounds.
struct MiniKeyboardView: View {
    @ObservedObject var appState: AppState

    private struct KeyCap: Identifiable {
        let id: UInt16
        let label: String
        let widthWeight: CGFloat
    }

    private let rows: [[KeyCap]] = [
        [
            KeyCap(id: 12, label: "Q", widthWeight: 1),
            KeyCap(id: 13, label: "W", widthWeight: 1),
            KeyCap(id: 14, label: "E", widthWeight: 1),
            KeyCap(id: 15, label: "R", widthWeight: 1),
            KeyCap(id: 17, label: "T", widthWeight: 1),
            KeyCap(id: 16, label: "Y", widthWeight: 1),
            KeyCap(id: 32, label: "U", widthWeight: 1),
            KeyCap(id: 34, label: "I", widthWeight: 1),
            KeyCap(id: 31, label: "O", widthWeight: 1),
            KeyCap(id: 35, label: "P", widthWeight: 1),
            KeyCap(id: 51, label: "⌫", widthWeight: 1.45)
        ],
        [
            KeyCap(id: 0, label: "A", widthWeight: 1),
            KeyCap(id: 1, label: "S", widthWeight: 1),
            KeyCap(id: 2, label: "D", widthWeight: 1),
            KeyCap(id: 3, label: "F", widthWeight: 1),
            KeyCap(id: 5, label: "G", widthWeight: 1),
            KeyCap(id: 4, label: "H", widthWeight: 1),
            KeyCap(id: 38, label: "J", widthWeight: 1),
            KeyCap(id: 40, label: "K", widthWeight: 1),
            KeyCap(id: 37, label: "L", widthWeight: 1),
            KeyCap(id: 36, label: "⏎", widthWeight: 1.75)
        ],
        [
            KeyCap(id: 56, label: "⇧", widthWeight: 1.55),
            KeyCap(id: 6, label: "Z", widthWeight: 1),
            KeyCap(id: 7, label: "X", widthWeight: 1),
            KeyCap(id: 8, label: "C", widthWeight: 1),
            KeyCap(id: 9, label: "V", widthWeight: 1),
            KeyCap(id: 11, label: "B", widthWeight: 1),
            KeyCap(id: 45, label: "N", widthWeight: 1),
            KeyCap(id: 46, label: "M", widthWeight: 1),
            KeyCap(id: 49, label: "SPACE", widthWeight: 3.1)
        ]
    ]

    private var accentColor: Color {
        if case .builtIn(let sw) = appState.settings.activeProfile {
            let rgb = sw.accentRGB
            return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
        }
        return Color.accentColor
    }

    var body: some View {
        VStack(spacing: 6) {
            VStack(spacing: 3.5) {
                ForEach(0..<rows.count, id: \.self) { rowIdx in
                    HStack(spacing: 3.5) {
                        ForEach(rows[rowIdx]) { key in
                            let isPressed = appState.pressedKeyCodes.contains(key.id)
                            Button {
                                appState.triggerVirtualKey(keyCode: key.id)
                            } label: {
                                Text(key.label)
                                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                    .foregroundColor(isPressed ? .white : .secondary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 22)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                                            .fill(isPressed ? accentColor : Color.primary.opacity(0.07))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                                            .strokeBorder(
                                                isPressed ? accentColor.opacity(0.9) : Color.primary.opacity(0.10),
                                                lineWidth: 0.75
                                            )
                                    )
                                    .scaleEffect(isPressed ? 0.93 : 1.0)
                                    .animation(.easeOut(duration: 0.06), value: isPressed)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: key.widthWeight * 28)
                        }
                    }
                }
            }

            // Live spatial stereo pan readout bar
            HStack(spacing: 6) {
                Text("L")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                GeometryReader { geo in
                    let normalized = CGFloat((appState.lastActivePan + 1.0) * 0.5)
                    let clamped = max(0.06, min(0.94, normalized))
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 4)
                        Circle()
                            .fill(accentColor)
                            .frame(width: 8, height: 8)
                            .offset(x: geo.size.width * clamped - 4)
                            .animation(.easeOut(duration: 0.09), value: appState.lastActivePan)
                    }
                    .frame(height: 8)
                }
                .frame(height: 8)

                Text("R")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
        )
    }
}
