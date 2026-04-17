// Mouse/Views/FunctionKeysView.swift
import SwiftUI

struct FunctionKeysView: View {
    let onKeyPress: (Int) -> Void

    private struct FKey: Identifiable {
        let id: String
        let icon: String
        let keyCode: Int
    }

    private let keys: [FKey] = [
        FKey(id: "F7",  icon: "backward.fill",       keyCode: 0x62),  // Previous Track
        FKey(id: "F8",  icon: "playpause.fill",      keyCode: 0x64),  // Play / Pause
        FKey(id: "F9",  icon: "forward.fill",        keyCode: 0x65),  // Next Track
        FKey(id: "F10", icon: "speaker.slash.fill",  keyCode: 0x6D),  // Mute
        FKey(id: "F11", icon: "speaker.fill",        keyCode: 0x67),  // Volume Down
        FKey(id: "F12", icon: "speaker.wave.2.fill", keyCode: 0x6F),  // Volume Up
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(keys) { key in
                Button {
                    onKeyPress(key.keyCode)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: key.icon)
                            .font(.system(size: 13))
                        Text(key.id)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.black.opacity(0.35))
    }
}
