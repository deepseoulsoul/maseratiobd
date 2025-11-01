//
//  DesignSystem.swift
//  mycar
//
//  Created by Jin Shin on 10/27/25.
//  ChatGPT iOS Style - Pure Black OLED Minimal
//

import SwiftUI

// MARK: - Colors (Pure Black Minimal)
extension Color {
    // Background - Pure Black for OLED
    static let appBackground = Color.black                 // #000000 순수 검정
    static let cardBackground = Color(hex: "#1C1C1E")     // 매우 어두운 회색 (미묘한 카드)
    static let inputBackground = Color(hex: "#1C1C1E")    // 입력창 배경

    // Message Bubbles
    static let userBubble = Color(hex: "#E5E5EA")         // 밝은 회색 (사용자 메시지)
    static let userBubbleText = Color.black               // 사용자 메시지 텍스트

    // Text - White on Black
    static let primaryText = Color.white                   // 주요 텍스트 (순수 흰색)
    static let secondaryText = Color(hex: "#EBEBF5").opacity(0.6)  // 보조 텍스트 (60% 불투명)
    static let tertiaryText = Color(hex: "#EBEBF5").opacity(0.3)   // 3차 텍스트 (30% 불투명)

    // Minimal Accent - 최소한의 색상만
    static let accentGreen = Color(hex: "#30D158")        // iOS 시스템 그린
    static let accentSubtle = Color(hex: "#48484A")       // 미묘한 회색 (버튼 배경)

    // Borders & Dividers - 매우 미묘
    static let borderColor = Color(hex: "#38383A")        // 매우 어두운 회색 테두리
    static let dividerColor = Color(hex: "#38383A").opacity(0.5)  // 구분선

    // Skeleton Loading
    static let skeletonBase = Color(hex: "#2C2C2E")       // 스켈레톤 베이스 색상

    // Helper: Hex to Color
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Typography
struct AppTypography {
    // SF Pro 기반
    static let largeTitle = Font.system(size: 28, weight: .bold, design: .default)
    static let title = Font.system(size: 20, weight: .semibold, design: .default)
    static let headline = Font.system(size: 17, weight: .semibold, design: .default)
    static let body = Font.system(size: 16, weight: .regular, design: .default)
    static let bodyBold = Font.system(size: 16, weight: .semibold, design: .default)
    static let caption = Font.system(size: 13, weight: .regular, design: .default)
    static let captionBold = Font.system(size: 13, weight: .semibold, design: .default)
    static let small = Font.system(size: 11, weight: .regular, design: .default)
}

// MARK: - Spacing
struct AppSpacing {
    static let xxxs: CGFloat = 2
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40
}

// MARK: - Corner Radius
struct AppRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xlarge: CGFloat = 20
}

// MARK: - Shadow
struct AppShadow {
    static let small = Color.black.opacity(0.1)
    static let medium = Color.black.opacity(0.2)
    static let large = Color.black.opacity(0.3)
}

// MARK: - Button Styles
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
