//
//  DTCDetailView.swift
//  maseratiobd
//
//  Created by Jin Shin on 11/1/25.
//  DTC 상세 화면 - 3단계 AI 설명 (짧은 요약 → 기본 상세 → 매우 상세)
//

import SwiftUI

struct DTCDetailView: View {
    let dtcCode: String
    let dtcDescription: String
    let englishDescription: String
    let system: String
    let severity: DTCSeverity

    @Environment(\.dismiss) var dismiss

    // Stage 1: 짧은 요약 (자동 로딩)
    @State private var briefSummary = ""
    @State private var isLoadingBrief = false
    @State private var hasBriefError = false

    // Stage 2: 기본 상세 설명 (자동 로딩)
    @State private var basicExplanation = ""
    @State private var isLoadingBasic = false
    @State private var hasBasicError = false

    // Stage 3: 매우 상세한 설명 (버튼 클릭 시)
    @State private var verboseExplanation = ""
    @State private var isLoadingVerbose = false
    @State private var hasVerboseError = false
    @State private var showVerbose = false

    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppSpacing.xl) {
                        // DTC Header
                        DTCHeaderSection(
                            code: dtcCode,
                            description: dtcDescription,
                            englishDescription: englishDescription,
                            system: system,
                            severity: severity
                        )

                        // Stage 1: 짧은 요약
                        BriefSummarySection(
                            summary: briefSummary,
                            isLoading: isLoadingBrief,
                            hasError: hasBriefError,
                            errorMessage: errorMessage,
                            onRetry: loadBriefSummary
                        )

                        // Stage 2: 기본 상세 설명 (자동 로딩)
                        BasicExplanationSection(
                            explanation: basicExplanation,
                            isLoading: isLoadingBasic,
                            hasError: hasBasicError,
                            errorMessage: errorMessage,
                            onRetry: loadBasicExplanation
                        )

                        // "더 상세히 보기" 버튼
                        if !basicExplanation.isEmpty && !showVerbose {
                            Button(action: {
                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                generator.impactOccurred()
                                showVerbose = true
                                loadVerboseExplanation()
                            }) {
                                HStack {
                                    Image(systemName: "doc.text.magnifyingglass")
                                    Text("더 상세히 보기")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentGreen)
                                .foregroundColor(.white)
                                .cornerRadius(AppRadius.medium)
                            }
                            .padding(.horizontal, AppSpacing.md)
                        }

                        // Stage 3: 매우 상세한 설명 (스켈레톤 로딩)
                        if showVerbose {
                            VerboseExplanationSection(
                                explanation: verboseExplanation,
                                isLoading: isLoadingVerbose,
                                hasError: hasVerboseError,
                                errorMessage: errorMessage,
                                onRetry: loadVerboseExplanation
                            )
                        }

                        // Additional Info (데이터베이스 정보)
                        AdditionalInfoSection(dtcCode: dtcCode)
                    }
                    .padding(.vertical, AppSpacing.md)
                }
            }
            .navigationTitle("고장 코드 상세")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadBriefSummary()
            loadBasicExplanation()  // 자동 로딩
        }
    }

    // MARK: - Stage 1: 짧은 요약

    private func loadBriefSummary() {
        isLoadingBrief = true
        hasBriefError = false
        briefSummary = ""

        // 15자 이내 한 줄 요약
        let prompt = "\(dtcCode) (\(dtcDescription)) 고장 코드를 한국어로 15자 이내 한 줄 요약"

        print("🤖 [DTCDetail] Stage 1: Requesting brief summary for \(dtcCode)")

        OpenAIService.shared.streamCompletion(
            prompt: prompt,
            maxTokens: APIConfig.openAIMaxTokensBrief,
            temperature: APIConfig.openAITemperature,
            onChunk: { chunk in
                briefSummary += chunk
            },
            onComplete: {
                print("✅ [DTCDetail] Stage 1: Brief summary complete")
                isLoadingBrief = false
            },
            onError: { error in
                print("❌ [DTCDetail] Stage 1: Brief error: \(error.localizedDescription)")
                hasBriefError = true
                errorMessage = error.localizedDescription
                isLoadingBrief = false
            }
        )
    }

    // MARK: - Stage 2: 기본 상세 설명 (자동 로딩)

    private func loadBasicExplanation() {
        isLoadingBasic = true
        hasBasicError = false
        basicExplanation = ""

        // 150자 이내 기본 상세 (원인, 증상, 해결)
        let prompt = """
        \(dtcCode) (\(dtcDescription)) 고장 코드를 한국어로 150자 이내 간결하게 설명:
        1. 원인: 주요 원인 1-2가지
        2. 증상: 운전자가 느낄 수 있는 증상
        3. 해결: 간단한 해결 방법
        """

        print("🤖 [DTCDetail] Stage 2: Requesting basic explanation for \(dtcCode)")

        OpenAIService.shared.streamCompletion(
            prompt: prompt,
            maxTokens: APIConfig.openAIMaxTokensBasic,
            temperature: APIConfig.openAITemperature,
            onChunk: { chunk in
                basicExplanation += chunk
            },
            onComplete: {
                print("✅ [DTCDetail] Stage 2: Basic explanation complete")
                isLoadingBasic = false
            },
            onError: { error in
                print("❌ [DTCDetail] Stage 2: Basic error: \(error.localizedDescription)")
                hasBasicError = true
                errorMessage = error.localizedDescription
                isLoadingBasic = false
            }
        )
    }

    // MARK: - Stage 3: 매우 상세한 설명 (버튼 클릭 시)

    private func loadVerboseExplanation() {
        isLoadingVerbose = true
        hasVerboseError = false
        verboseExplanation = ""

        // 500자 내외 매우 상세한 설명 (마크다운 형식)
        let prompt = """
        \(dtcCode) (\(dtcDescription)) 고장 코드에 대한 전문적인 상세 설명을 한국어로 500자 이내로 작성해주세요.

        중요: 각 항목 사이에 반드시 빈 줄을 하나 넣어주세요. 마크다운 형식(**굵게**)을 사용하세요:

        **1. 고장 진단 절차**
        어떻게 진단하는지 단계별로 설명

        **2. 관련 부품 정보**
        교체가 필요한 부품과 부품 번호

        **3. 예상 수리 비용**
        대략적인 수리 비용 (부품비 + 공임)

        **4. 예방 방법**
        이 고장을 예방하는 정비 팁

        **5. 관련 코드**
        함께 나타날 수 있는 다른 DTC 코드

        **6. 정비소 방문 시 주의사항**
        정비소에서 확인해야 할 사항

        **7. 긴급도 판단**
        즉시 수리가 필요한지, 천천히 해도 되는지

        ⚠️ 참고: AI가 생성한 정보로 정확하지 않을 수 있습니다. 정확한 진단은 전문 정비소에서 받으세요.
        """

        print("🤖 [DTCDetail] Stage 3: Requesting verbose explanation for \(dtcCode)")

        OpenAIService.shared.streamCompletion(
            prompt: prompt,
            maxTokens: APIConfig.openAIMaxTokensVerbose,
            temperature: APIConfig.openAITemperature,
            onChunk: { chunk in
                verboseExplanation += chunk
            },
            onComplete: {
                print("✅ [DTCDetail] Stage 3: Verbose explanation complete")
                isLoadingVerbose = false
            },
            onError: { error in
                print("❌ [DTCDetail] Stage 3: Verbose error: \(error.localizedDescription)")
                hasVerboseError = true
                errorMessage = error.localizedDescription
                isLoadingVerbose = false
            }
        )
    }
}

// MARK: - DTC Header Section

struct DTCHeaderSection: View {
    let code: String
    let description: String
    let englishDescription: String
    let system: String
    let severity: DTCSeverity

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            // Severity Indicator
            ZStack {
                Circle()
                    .fill(severity.color.opacity(0.2))
                    .frame(width: 80, height: 80)

                Circle()
                    .fill(severity.color)
                    .frame(width: 16, height: 16)
            }

            // DTC Code
            Text(code)
                .font(.system(.largeTitle, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(.primaryText)

            // Korean Description
            Text(description)
                .font(AppTypography.body)
                .foregroundColor(.primaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.lg)

            // English Description
            Text(englishDescription)
                .font(AppTypography.caption)
                .foregroundColor(.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.lg)

            // System & Severity Badges
            HStack(spacing: AppSpacing.sm) {
                Badge(text: system, color: .accentGreen)
                Badge(text: severity.displayText, color: severity.color)
            }
        }
        .padding(AppSpacing.lg)
        .background(Color.inputBackground)
        .cornerRadius(AppRadius.medium)
        .padding(.horizontal, AppSpacing.md)
    }
}

// MARK: - Brief Summary Section

struct BriefSummarySection: View {
    let summary: String
    let isLoading: Bool
    let hasError: Bool
    let errorMessage: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Section Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.accentGreen)
                Text("설명")
                    .font(AppTypography.headline)
                    .foregroundColor(.primaryText)
                Spacer()
            }
            .padding(.horizontal, AppSpacing.md)

            // Content
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                if isLoading {
                    // Loading State
                    HStack(spacing: AppSpacing.sm) {
                        TypingIndicator()
                        Text("요약 생성 중...")
                            .font(AppTypography.body)
                            .foregroundColor(.secondaryText)
                    }
                    .padding(.vertical, AppSpacing.md)
                } else if hasError {
                    // Error State
                    ErrorStateView(
                        message: "요약을 불러올 수 없습니다",
                        errorMessage: errorMessage,
                        onRetry: onRetry
                    )
                } else if !summary.isEmpty {
                    // Success State
                    Text(summary)
                        .font(AppTypography.body)
                        .foregroundColor(.primaryText)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                } else {
                    Text("요약 불러오는 중...")
                        .font(AppTypography.body)
                        .foregroundColor(.secondaryText)
                        .padding(.vertical, AppSpacing.md)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.md)
            .background(Color.inputBackground)
            .cornerRadius(AppRadius.medium)
            .padding(.horizontal, AppSpacing.md)
        }
    }
}

// MARK: - Basic Explanation Section (Stage 2 - 자동 로딩)

struct BasicExplanationSection: View {
    let explanation: String
    let isLoading: Bool
    let hasError: Bool
    let errorMessage: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Section Header
            HStack {
                Image(systemName: "doc.text")
                    .foregroundColor(.accentGreen)
                Text("AI 빠른요약")
                    .font(AppTypography.headline)
                    .foregroundColor(.primaryText)
                Spacer()
            }
            .padding(.horizontal, AppSpacing.md)

            // Content
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                if isLoading {
                    // Skeleton Loading
                    BasicSkeletonView()
                } else if hasError {
                    // Error State
                    ErrorStateView(
                        message: "AI 빠른요약을 불러올 수 없습니다",
                        errorMessage: errorMessage,
                        onRetry: onRetry
                    )
                } else if !explanation.isEmpty {
                    // Success State
                    Text(explanation)
                        .font(AppTypography.body)
                        .foregroundColor(.primaryText)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                } else {
                    Text("AI 빠른요약 불러오는 중...")
                        .font(AppTypography.body)
                        .foregroundColor(.secondaryText)
                        .padding(.vertical, AppSpacing.md)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.md)
            .background(Color.inputBackground)
            .cornerRadius(AppRadius.medium)
            .padding(.horizontal, AppSpacing.md)
        }
    }
}

// MARK: - Verbose Explanation Section (Stage 3 - 버튼 클릭)

struct VerboseExplanationSection: View {
    let explanation: String
    let isLoading: Bool
    let hasError: Bool
    let errorMessage: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Section Header
            HStack {
                Image(systemName: "book.fill")
                    .foregroundColor(.accentGreen)
                Text("상세분석")
                    .font(AppTypography.headline)
                    .foregroundColor(.primaryText)
                Spacer()
            }
            .padding(.horizontal, AppSpacing.md)

            // Content
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                if isLoading {
                    // Skeleton Loading
                    VerboseSkeletonView()
                } else if hasError {
                    // Error State
                    ErrorStateView(
                        message: "상세분석을 불러올 수 없습니다",
                        errorMessage: errorMessage,
                        onRetry: onRetry
                    )
                } else if !explanation.isEmpty {
                    // Success State (with Markdown support and line breaks)
                    if let attributedString = try? AttributedString(
                        markdown: explanation,
                        options: AttributedString.MarkdownParsingOptions(
                            interpretedSyntax: .inlineOnlyPreservingWhitespace
                        )
                    ) {
                        Text(attributedString)
                            .font(AppTypography.body)
                            .foregroundColor(.primaryText)
                            .lineSpacing(8)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    } else {
                        // Fallback if markdown parsing fails
                        Text(explanation)
                            .font(AppTypography.body)
                            .foregroundColor(.primaryText)
                            .lineSpacing(8)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                } else {
                    Text("상세분석 불러오는 중...")
                        .font(AppTypography.body)
                        .foregroundColor(.secondaryText)
                        .padding(.vertical, AppSpacing.md)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.md)
            .background(Color.inputBackground)
            .cornerRadius(AppRadius.medium)
            .padding(.horizontal, AppSpacing.md)
        }
    }
}

// MARK: - Skeleton Loading Views

struct BasicSkeletonView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // 제목 스켈레톤
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "sparkles")
                    .foregroundColor(.accentGreen)
                Text("AI가 빠른요약을 작성하고 있습니다...")
                    .font(AppTypography.caption)
                    .foregroundColor(.secondaryText)
            }
            .padding(.bottom, AppSpacing.sm)

            // 텍스트 라인 스켈레톤
            ForEach(0..<4, id: \.self) { index in
                SkeletonLine(width: getLineWidth(index: index, total: 4))
            }
        }
        .padding(.vertical, AppSpacing.md)
    }

    private func getLineWidth(index: Int, total: Int) -> CGFloat {
        let widths: [CGFloat] = [0.9, 0.95, 0.85, 0.8]
        return widths[index]
    }
}

struct VerboseSkeletonView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // 제목 스켈레톤
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "sparkles")
                    .foregroundColor(.accentGreen)
                Text("AI가 상세분석을 작성하고 있습니다...")
                    .font(AppTypography.caption)
                    .foregroundColor(.secondaryText)
            }
            .padding(.bottom, AppSpacing.sm)

            // 텍스트 라인 스켈레톤 (더 많음)
            ForEach(0..<8, id: \.self) { index in
                SkeletonLine(width: getLineWidth(index: index))
            }
        }
        .padding(.vertical, AppSpacing.md)
    }

    private func getLineWidth(index: Int) -> CGFloat {
        let widths: [CGFloat] = [0.9, 0.95, 0.85, 0.92, 0.88, 0.93, 0.87, 0.75]
        return widths[index]
    }
}

struct SkeletonLine: View {
    let width: CGFloat
    @State private var isAnimating = false

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.secondaryText.opacity(0.15),
                        Color.secondaryText.opacity(0.25),
                        Color.secondaryText.opacity(0.15)
                    ]),
                    startPoint: isAnimating ? .leading : .trailing,
                    endPoint: isAnimating ? .trailing : .leading
                )
            )
            .frame(width: UIScreen.main.bounds.width * width - 60, height: 14)
            .onAppear {
                withAnimation(Animation.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating.toggle()
                }
            }
    }
}

// MARK: - Error State View

struct ErrorStateView: View {
    let message: String
    let errorMessage: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)

            Text(message)
                .font(AppTypography.body)
                .foregroundColor(.primaryText)

            Text(errorMessage)
                .font(AppTypography.caption)
                .foregroundColor(.secondaryText)
                .multilineTextAlignment(.center)

            Button(action: onRetry) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("다시 시도")
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background(Color.accentGreen)
                .foregroundColor(.white)
                .cornerRadius(AppRadius.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xl)
    }
}

// MARK: - Additional Info Section

struct AdditionalInfoSection: View {
    let dtcCode: String

    var dtcInfo: CombinedDTCInfo {
        DTCDatabase.shared.lookup(dtcCode: dtcCode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Section Header
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.accentGreen)
                Text("추가 정보")
                    .font(AppTypography.headline)
                    .foregroundColor(.primaryText)
                Spacer()
            }
            .padding(.horizontal, AppSpacing.md)

            // Info Cards
            VStack(spacing: AppSpacing.sm) {
                InfoRow(
                    icon: "doc.text",
                    title: "코드 타입",
                    value: dtcInfo.type
                )

                if let dtc = dtcInfo.dtcInfo {
                    Divider()
                        .background(Color.dividerColor)

                    InfoRow(
                        icon: "number",
                        title: "Full Code",
                        value: dtc.fullCode
                    )

                    Divider()
                        .background(Color.dividerColor)

                    InfoRow(
                        icon: "cpu",
                        title: "Device ID",
                        value: "\(dtc.deviceId)"
                    )
                }

                if let fault = dtcInfo.faultInfo {
                    Divider()
                        .background(Color.dividerColor)

                    InfoRow(
                        icon: "globe",
                        title: "다국어 지원",
                        value: getSupportedLanguages(fault: fault)
                    )
                }
            }
            .padding(AppSpacing.md)
            .background(Color.inputBackground)
            .cornerRadius(AppRadius.medium)
            .padding(.horizontal, AppSpacing.md)
        }
    }

    private func getSupportedLanguages(fault: FaultInfo) -> String {
        var languages: [String] = []
        languages.append("🇬🇧 영어")  // en is always available
        if fault.description.de != nil { languages.append("🇩🇪 독일어") }
        if fault.description.it != nil { languages.append("🇮🇹 이탈리아어") }
        if fault.description.es != nil { languages.append("🇪🇸 스페인어") }
        if fault.description.fr != nil { languages.append("🇫🇷 프랑스어") }
        return languages.joined(separator: ", ")
    }
}

// MARK: - Supporting Views

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(AppTypography.caption)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, 4)
            .background(color)
            .cornerRadius(AppRadius.small)
    }
}

struct InfoRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.accentGreen)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.caption)
                    .foregroundColor(.secondaryText)

                Text(value)
                    .font(AppTypography.body)
                    .foregroundColor(.primaryText)
            }

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    DTCDetailView(
        dtcCode: "P0011",
        dtcDescription: "캠샤프트 포지션 센서 고장",
        englishDescription: "Camshaft Position Sensor Circuit Range/Performance",
        system: "Powertrain",
        severity: .critical
    )
}
