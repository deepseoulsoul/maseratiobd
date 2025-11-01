//
//  TypingIndicator.swift
//  mycar
//
//  Created by Jin Shin on 10/27/25.
//  ChatGPT Style Typing Indicator - Pulsing Circles
//

import SwiftUI

struct TypingIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondaryText.opacity(0.7))
                    .frame(width: 8, height: 8)
                    .scaleEffect(isAnimating ? 1.4 : 0.6)
                    .animation(
                        Animation.easeInOut(duration: 0.8)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Color.appBackground.ignoresSafeArea()

        VStack(spacing: 20) {
            Text("AI가 답변을 생성하고 있습니다...")
                .font(AppTypography.caption)
                .foregroundColor(.secondaryText)

            TypingIndicator()
        }
    }
}
