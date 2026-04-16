// Mouse/Views/ToolbarView.swift
import SwiftUI

struct ToolbarView: View {
    let onRightClick: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            Button(action: onRightClick) {
                Label("Right Click", systemImage: "cursorarrow.click.2")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            }

            Spacer()

            Button(action: onDisconnect) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.black.opacity(0.4))
    }
}
