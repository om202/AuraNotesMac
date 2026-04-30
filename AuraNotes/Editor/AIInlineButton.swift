//
//  AIInlineButton.swift
//  AuraNotes
//

import SwiftUI

/// Sparkle pill that floats above a non-empty selection in the editor.
/// Tapping it opens system Writing Tools targeting the selected range.
struct AIInlineButton: View {
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "apple.intelligence")
                    .font(.system(size: 13, weight: .semibold))
                Text("AI")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(.white)
            .background(
                Capsule(style: .continuous)
                    .fill(LinearGradient(
                        colors: [
                            Color(red: 1.00, green: 0.46, blue: 0.12),
                            Color(red: 0.90, green: 0.20, blue: 0.55),
                            Color(red: 0.40, green: 0.30, blue: 0.95)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(hover ? 0.35 : 0.20),
                    radius: hover ? 6 : 4,
                    y: 2)
            .scaleEffect(hover ? 1.04 : 1.0)
            .animation(.easeOut(duration: 0.12), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Writing Tools — Proofread, Rewrite, Summarize…")
    }
}
