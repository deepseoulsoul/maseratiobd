//
//  DiagnosticsView.swift
//  mycar
//
//  Created by Jin Shin on 10/30/25.
//  OBD-II 차량 진단 화면
//

import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var obdService = OBDService.shared
    @ObservedObject var historyManager = DTCHistoryManager.shared
    @State private var isScanning = false
    @State private var dtcCodes: [DTCDisplayCode] = [
        // 🧪 테스트용 샘플 DTC 코드 (차량 연결 없이 UI 테스트용)
        DTCDisplayCode(
            code: "P0300",
            description: "엔진 실화 (다중 실린더)",
            englishDescription: "Random/Multiple Cylinder Misfire Detected",
            system: "Powertrain",
            severity: .critical  // 🔴 심각: 즉시 수리
        ),
        DTCDisplayCode(
            code: "C0040",
            description: "ABS 모듈 통신 오류",
            englishDescription: "ABS Module Communication Error",
            system: "Chassis",
            severity: .critical  // 🔴 심각: 안전 직결
        ),
        DTCDisplayCode(
            code: "P0420",
            description: "촉매 시스템 효율 저하",
            englishDescription: "Catalyst System Efficiency Below Threshold",
            system: "Powertrain",
            severity: .high  // 🟠 높음: 빠른 수리 권장
        ),
        DTCDisplayCode(
            code: "P0133",
            description: "산소 센서 응답 속도 저하",
            englishDescription: "O2 Sensor Circuit Slow Response (Bank 1, Sensor 1)",
            system: "Powertrain",
            severity: .high  // 🟠 높음
        ),
        DTCDisplayCode(
            code: "P0442",
            description: "증발가스 시스템 소형 누출",
            englishDescription: "EVAP System Small Leak Detected",
            system: "Powertrain",
            severity: .medium  // 🟡 보통: 천천히 수리
        ),
        DTCDisplayCode(
            code: "B1657",
            description: "공압 제어 시스템 고장",
            englishDescription: "Pneumatic Pressure Control Siemens",
            system: "Body",
            severity: .low  // 🔵 낮음: 모니터링
        )
    ]
    @State private var showConnectionView = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var selectedTab = 0  // 0: 현재, 1: 히스토리
    @State private var historyFilter: HistoryFilter = .all
    @State private var showTrendAnalysis = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Tab Selector
                    Picker("View", selection: $selectedTab) {
                        Text("현재").tag(0)
                        Text("히스토리").tag(1)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)

                    if selectedTab == 0 {
                        // 현재 코드 탭
                        currentCodesView
                    } else {
                        // 히스토리 탭
                        historyView
                    }
                }
            }
            .navigationTitle("차량 진단")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // 목업 데이터 생성 버튼 (개발용)
                    if selectedTab == 1 {
                        Button(action: {
                            historyManager.generateMockData()
                        }) {
                            Image(systemName: "wand.and.stars")
                                .foregroundColor(.accentGreen)
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showConnectionView = true
                    }) {
                        Image(systemName: obdService.connectionState.isConnected ? "checkmark.circle.fill" : "link")
                            .foregroundColor(obdService.connectionState.isConnected ? .accentGreen : .secondaryText)
                    }
                }
            }
            .sheet(isPresented: $showConnectionView) {
                OBDConnectionView()
            }
            .alert("스캔 오류", isPresented: $showError) {
                Button("확인", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
        }
    }

    // MARK: - Current Codes View

    var currentCodesView: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                // Connection Status Card
                ConnectionStatusCard(
                    isConnected: .constant(obdService.connectionState.isConnected),
                    connectionState: obdService.connectionState,
                    onTap: {
                        showConnectionView = true
                    }
                )

                        // Quick Actions
                        HStack(spacing: AppSpacing.md) {
                            QuickActionButton(
                                icon: "antenna.radiowaves.left.and.right",
                                title: "스캔",
                                subtitle: isScanning ? "스캔 중..." : "DTC 읽기",
                                color: .accentGreen,
                                action: scanDTCs,
                                isLoading: isScanning
                            )
                            .disabled(!obdService.connectionState.isConnected || isScanning)

                            QuickActionButton(
                                icon: "trash.fill",
                                title: "삭제",
                                subtitle: "DTC 제거",
                                color: .red,
                                action: clearDTCs,
                                isLoading: false
                            )
                            .disabled(!obdService.connectionState.isConnected || dtcCodes.isEmpty || isScanning)
                        }
                        .padding(.horizontal, AppSpacing.md)

                // DTC List
                if dtcCodes.isEmpty {
                    EmptyDTCView()
                } else {
                    DTCListSection(dtcCodes: $dtcCodes)
                }
            }
            .padding(.vertical, AppSpacing.md)
        }
    }

    // MARK: - History View

    var historyView: some View {
        ScrollView {
            VStack(spacing: AppSpacing.md) {
                if historyManager.history.isEmpty {
                    EmptyHistoryView()
                } else {
                    // 히스토리 헤더 & 필터
                    VStack(spacing: AppSpacing.md) {
                        HStack {
                            Text("\(filteredHistory.count)개의 스캔 기록")
                                .font(AppTypography.headline)
                                .foregroundColor(.primaryText)

                            Spacer()

                            Button(action: {
                                showTrendAnalysis.toggle()
                            }) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.system(size: 18))
                                    .foregroundColor(.accentGreen)
                            }

                            Button(action: {
                                historyManager.clearAllHistory()
                            }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 18))
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.horizontal, AppSpacing.md)

                        // 필터 버튼들
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppSpacing.sm) {
                                ForEach(HistoryFilter.allCases, id: \.self) { filter in
                                    FilterChip(
                                        title: filter.displayText,
                                        isSelected: historyFilter == filter,
                                        action: { historyFilter = filter }
                                    )
                                }
                            }
                            .padding(.horizontal, AppSpacing.md)
                        }
                    }
                    .padding(.top, AppSpacing.md)

                    // 트렌드 분석 (접을 수 있음)
                    if showTrendAnalysis {
                        TrendAnalysisCard(analysis: historyManager.getTrendAnalysis())
                            .padding(.horizontal, AppSpacing.md)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // 날짜별로 그룹화된 히스토리
                    ForEach(getGroupedFilteredHistory(), id: \.0) { dateString, entries in
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            // 날짜 헤더
                            Text(dateString)
                                .font(AppTypography.body)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondaryText)
                                .padding(.horizontal, AppSpacing.md)
                                .padding(.top, AppSpacing.sm)

                            // 해당 날짜의 스캔 기록들
                            ForEach(entries) { entry in
                                EnhancedHistoryEntryCard(
                                    entry: entry,
                                    previousEntry: getPreviousEntry(for: entry),
                                    onDelete: {
                                        withAnimation {
                                            historyManager.deleteEntry(entry)
                                        }
                                    }
                                )
                                .padding(.horizontal, AppSpacing.md)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, AppSpacing.md)
        }
    }

    // 필터링된 히스토리
    var filteredHistory: [DTCHistoryEntry] {
        switch historyFilter {
        case .all:
            return historyManager.history
        case .critical:
            return historyManager.history.filter { $0.highestSeverity == .critical }
        case .withIssues:
            return historyManager.history.filter { !$0.dtcCodes.isEmpty }
        case .clean:
            return historyManager.history.filter { $0.dtcCodes.isEmpty }
        }
    }

    // 필터링된 히스토리를 날짜별로 그룹화
    func getGroupedFilteredHistory() -> [(String, [DTCHistoryEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredHistory) { entry in
            calendar.startOfDay(for: entry.timestamp)
        }

        return grouped
            .sorted { $0.key > $1.key }
            .map { (dateString(from: $0.key), $0.value.sorted { $0.timestamp > $1.timestamp }) }
    }

    // 이전 스캔 찾기 (비교용)
    func getPreviousEntry(for entry: DTCHistoryEntry) -> DTCHistoryEntry? {
        guard let index = historyManager.history.firstIndex(where: { $0.id == entry.id }) else {
            return nil
        }
        let nextIndex = index + 1
        guard nextIndex < historyManager.history.count else {
            return nil
        }
        return historyManager.history[nextIndex]
    }

    // 날짜 문자열 변환
    func dateString(from date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "오늘"
        } else if calendar.isDateInYesterday(date) {
            return "어제"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "M월 d일 (E)"
            formatter.locale = Locale(identifier: "ko_KR")
            return formatter.string(from: date)
        }
    }

    // MARK: - Actions

    private func scanDTCs() {
        print("🔍 [Diagnostics] Scan button pressed")

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        guard obdService.connectionState.isConnected else {
            print("⚠️ [Diagnostics] Not connected, showing connection view")
            showConnectionView = true
            return
        }

        print("✅ [Diagnostics] Connected, starting scan...")

        withAnimation {
            isScanning = true
        }

        // 실제 OBD 스캔
        Task {
            do {
                print("📡 [Diagnostics] Calling readDTCs()...")
                let codes = try await obdService.readDTCs()
                print("📋 [Diagnostics] Read \(codes.count) DTCs: \(codes)")

                await MainActor.run {
                    withAnimation {
                        // DTC 데이터베이스에서 상세 정보 조회
                        dtcCodes = codes.map { code in
                            let dtcInfo = DTCDatabase.shared.lookup(dtcCode: code)
                            return DTCDisplayCode(
                                code: code,
                                description: dtcInfo.displayDescription,
                                englishDescription: dtcInfo.englishDescription,
                                system: dtcInfo.system,
                                severity: getSeverityFromCode(code)
                            )
                        }
                        isScanning = false
                    }

                    // 히스토리에 저장 (상세 정보 포함)
                    if !codes.isEmpty {
                        historyManager.saveScan(dtcCodes: codes, dtcDetails: dtcCodes)
                        print("💾 [Diagnostics] Saved \(codes.count) DTCs to history with details")
                    }

                    let successGenerator = UINotificationFeedbackGenerator()
                    successGenerator.notificationOccurred(.success)

                    print("✅ [Diagnostics] Scan completed successfully")
                }
            } catch {
                print("❌ [Diagnostics] Failed to read DTCs: \(error)")
                print("❌ [Diagnostics] Error type: \(type(of: error))")
                print("❌ [Diagnostics] Error details: \(error.localizedDescription)")

                await MainActor.run {
                    withAnimation {
                        isScanning = false
                        errorMessage = "DTC 스캔 실패: \(error.localizedDescription)"
                        showError = true
                    }

                    let errorGenerator = UINotificationFeedbackGenerator()
                    errorGenerator.notificationOccurred(.error)
                }
            }
        }
    }

    private func clearDTCs() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)

        guard obdService.connectionState.isConnected else {
            showConnectionView = true
            return
        }

        Task {
            do {
                try await obdService.clearDTCs()
                print("✅ [Diagnostics] DTCs cleared")

                await MainActor.run {
                    withAnimation {
                        dtcCodes.removeAll()
                    }

                    let successGenerator = UINotificationFeedbackGenerator()
                    successGenerator.notificationOccurred(.success)
                }
            } catch {
                print("❌ [Diagnostics] Failed to clear DTCs: \(error)")

                await MainActor.run {
                    let errorGenerator = UINotificationFeedbackGenerator()
                    errorGenerator.notificationOccurred(.error)
                }
            }
        }
    }

    private func getSystemFromCode(_ code: String) -> String {
        guard let firstChar = code.first else { return "Unknown" }
        switch firstChar {
        case "P": return "Powertrain"
        case "C": return "Chassis"
        case "B": return "Body"
        case "U": return "Network"
        default: return "Unknown"
        }
    }

    private func getSeverityFromCode(_ code: String) -> DTCSeverity {
        // 🔴 Critical (심각): 즉시 수리 필요 - 안전/주행 직결
        let criticalCodes: Set<String> = [
            // 엔진 실화 (Misfire)
            "P0300", "P0301", "P0302", "P0303", "P0304", "P0305", "P0306",

            // 연료 시스템 심각한 문제
            "P0087", "P0088",  // 연료 압력 이상
            "P0171", "P0172",  // 연료 트림 심각한 이상

            // 엔진 과열 / 냉각수
            "P0217", "P0218",  // 엔진 과열

            // 브레이크 시스템 (ABS/ESP)
            "C0035", "C0040", "C0045", "C0050",  // ABS 센서/모듈
            "C1095", "C1096",  // 펌프 모터

            // 에어백 시스템
            "B0001", "B0002", "B0003", "B0004",  // 에어백 배치 불량

            // 조향 시스템
            "C0041", "C0042"  // 파워 스티어링
        ]

        // 🟠 High (높음): 빠른 시일 내 수리 권장
        let highCodes: Set<String> = [
            // 촉매 변환기
            "P0420", "P0430",  // 촉매 효율 저하

            // 산소 센서
            "P0131", "P0132", "P0133", "P0134",  // O2 센서 Bank 1
            "P0151", "P0152", "P0153", "P0154",  // O2 센서 Bank 2

            // 점화 시스템
            "P0351", "P0352", "P0353", "P0354",  // 점화 코일

            // 캠/크랭크 센서
            "P0011", "P0021",  // 캠샤프트 포지션
            "P0335", "P0336",  // 크랭크샤프트 포지션

            // 변속기 심각한 문제
            "P0700", "P0715", "P0720",  // 변속기 제어

            // 브레이크 경고등
            "C0031", "C0032"  // 브레이크 스위치
        ]

        // 🟡 Medium (보통): 천천히 수리 가능
        let mediumCodes: Set<String> = [
            // EVAP 시스템
            "P0440", "P0441", "P0442", "P0443",  // 증발가스 누출

            // 냉각 팬
            "P0480", "P0481",  // 냉각 팬 제어

            // 에어컨
            "B1479", "B1480",  // A/C 압력

            // 실내 전장
            "B1650", "B1651", "B1652",  // 도어락, 창문

            // 타이어 공기압
            "C0750", "C0755"  // TPMS
        ]

        // 개별 코드 체크
        if criticalCodes.contains(code) {
            return .critical
        } else if highCodes.contains(code) {
            return .high
        } else if mediumCodes.contains(code) {
            return .medium
        }

        // 기본 분류 (시스템 기반)
        guard let firstChar = code.first else { return .low }
        switch firstChar {
        case "P": return .high      // Powertrain (엔진/변속기) - 기본 높음
        case "C": return .medium    // Chassis (섀시) - 기본 보통
        case "B": return .low       // Body (차체) - 기본 낮음
        case "U": return .low       // Network (통신) - 기본 낮음
        default: return .low
        }
    }
}

// MARK: - Connection Status Card

struct ConnectionStatusCard: View {
    @Binding var isConnected: Bool
    let connectionState: OBDConnectionState
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppSpacing.md) {
                // Status Icon
                ZStack {
                    Circle()
                        .fill(isConnected ? Color.accentGreen.opacity(0.2) : Color.secondaryText.opacity(0.2))
                        .frame(width: 50, height: 50)

                    Image(systemName: isConnected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(isConnected ? .accentGreen : .secondaryText)
                }

                // Status Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(connectionState.displayText)
                        .font(AppTypography.headline)
                        .foregroundColor(.primaryText)

                    Text(isConnected ? "Vgate iCar Pro" : "OBD 어댑터를 연결하세요")
                        .font(AppTypography.caption)
                        .foregroundColor(.secondaryText)
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.secondaryText)
            }
            .padding(AppSpacing.md)
            .background(Color.inputBackground)
            .cornerRadius(AppRadius.medium)
            .padding(.horizontal, AppSpacing.md)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void
    var isLoading: Bool = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 50, height: 50)

                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: color))
                            .scaleEffect(1.2)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 24))
                            .foregroundColor(color)
                    }
                }

                VStack(spacing: 2) {
                    Text(title)
                        .font(AppTypography.headline)
                        .foregroundColor(.primaryText)

                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundColor(.secondaryText)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.md)
            .background(Color.inputBackground)
            .cornerRadius(AppRadius.medium)
            .opacity(isLoading ? 0.6 : 1.0)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Empty DTC View

struct EmptyDTCView: View {
    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()

            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 60))
                .foregroundColor(.accentGreen)

            VStack(spacing: AppSpacing.xs) {
                Text("고장 코드 없음")
                    .font(AppTypography.headline)
                    .foregroundColor(.primaryText)

                Text("차량에 활성화된 DTC 코드가 없습니다.")
                    .font(AppTypography.body)
                    .foregroundColor(.secondaryText)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(AppSpacing.xl)
    }
}

// MARK: - DTC List Section

struct DTCListSection: View {
    @Binding var dtcCodes: [DTCDisplayCode]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Header
            HStack {
                Text("\(dtcCodes.count)개의 고장 코드")
                    .font(AppTypography.headline)
                    .foregroundColor(.primaryText)

                Spacer()
            }
            .padding(.horizontal, AppSpacing.md)

            // DTC Cards
            ForEach(dtcCodes) { dtc in
                DTCCard(dtc: dtc)
                    .padding(.horizontal, AppSpacing.md)
            }
        }
    }
}

// MARK: - DTC Card

struct DTCCard: View {
    let dtc: DTCDisplayCode
    @State private var showDetail = false

    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            showDetail = true
        }) {
            HStack(spacing: AppSpacing.md) {
                // Severity Indicator
                VStack {
                    Circle()
                        .fill(dtc.severity.color)
                        .frame(width: 12, height: 12)

                    Spacer()
                }

                // DTC Info
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    // Code
                    Text(dtc.code)
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.primaryText)

                    // Korean Description
                    Text(dtc.description)
                        .font(AppTypography.body)
                        .foregroundColor(.primaryText)
                        .lineLimit(2)

                    // English Description
                    Text(dtc.englishDescription)
                        .font(AppTypography.caption)
                        .foregroundColor(.secondaryText)
                        .lineLimit(2)

                    // System Badge
                    HStack(spacing: AppSpacing.xs) {
                        Text(dtc.system)
                            .font(AppTypography.caption)
                            .foregroundColor(.secondaryText)

                        Text("•")
                            .foregroundColor(.secondaryText)

                        Text(dtc.severity.displayText)
                            .font(AppTypography.caption)
                            .foregroundColor(dtc.severity.color)
                    }
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.secondaryText)
            }
            .padding(AppSpacing.md)
            .background(Color.inputBackground)
            .cornerRadius(AppRadius.medium)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showDetail) {
            DTCDetailView(
                dtcCode: dtc.code,
                dtcDescription: dtc.description,
                englishDescription: dtc.englishDescription,
                system: dtc.system,
                severity: dtc.severity
            )
        }
    }
}

// MARK: - Models

struct DTCDisplayCode: Identifiable, Codable {
    let id: UUID
    let code: String
    let description: String  // 한국어 설명
    let englishDescription: String  // 영문 설명
    let system: String
    let severity: DTCSeverity

    init(id: UUID = UUID(), code: String, description: String, englishDescription: String, system: String, severity: DTCSeverity) {
        self.id = id
        self.code = code
        self.description = description
        self.englishDescription = englishDescription
        self.system = system
        self.severity = severity
    }
}

enum DTCSeverity: String, Codable {
    case critical, high, medium, low

    var color: Color {
        switch self {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .blue
        }
    }

    var displayText: String {
        switch self {
        case .critical: return "심각"
        case .high: return "높음"
        case .medium: return "보통"
        case .low: return "낮음"
        }
    }
}

// MARK: - Empty History View

struct EmptyHistoryView: View {
    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()

            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 60))
                .foregroundColor(.secondaryText)

            VStack(spacing: AppSpacing.xs) {
                Text("스캔 기록 없음")
                    .font(AppTypography.headline)
                    .foregroundColor(.primaryText)

                Text("DTC 스캔을 수행하면 히스토리에 저장됩니다.")
                    .font(AppTypography.body)
                    .foregroundColor(.secondaryText)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(AppSpacing.xl)
    }
}

// MARK: - History Filter

enum HistoryFilter: CaseIterable {
    case all
    case critical
    case withIssues
    case clean

    var displayText: String {
        switch self {
        case .all: return "전체"
        case .critical: return "심각"
        case .withIssues: return "문제"
        case .clean: return "정상"
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTypography.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .primaryText)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .background(isSelected ? Color.accentGreen : Color.inputBackground)
                .cornerRadius(20)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Trend Analysis Card

struct TrendAnalysisCard: View {
    let analysis: TrendAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.accentGreen)
                Text("최근 7일 요약")
                    .font(AppTypography.headline)
                    .foregroundColor(.primaryText)
            }

            Divider()

            // 통계 정보
            HStack(spacing: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("총 스캔")
                        .font(AppTypography.caption)
                        .foregroundColor(.secondaryText)
                    Text("\(analysis.totalScans)회")
                        .font(AppTypography.title)
                        .foregroundColor(.primaryText)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("평균 DTC")
                        .font(AppTypography.caption)
                        .foregroundColor(.secondaryText)
                    Text(String(format: "%.1f개", analysis.averageDTCs))
                        .font(AppTypography.title)
                        .foregroundColor(.primaryText)
                }

                Spacer()

                // 트렌드 아이콘
                VStack(spacing: 4) {
                    Image(systemName: analysis.trend.icon)
                        .font(.system(size: 24))
                        .foregroundColor(trendColor(for: analysis.trend))
                    Text(analysis.trend.displayText)
                        .font(AppTypography.caption)
                        .foregroundColor(.secondaryText)
                }
            }

            // 자주 발견되는 코드
            if !analysis.topCodes.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("자주 발견되는 코드")
                        .font(AppTypography.caption)
                        .foregroundColor(.secondaryText)

                    ForEach(analysis.topCodes, id: \.code) { code, count in
                        HStack {
                            Text(code)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.primaryText)
                            Spacer()
                            Text("\(count)회")
                                .font(AppTypography.caption)
                                .foregroundColor(.secondaryText)
                        }
                    }
                }
            }
        }
        .padding(AppSpacing.md)
        .background(Color.inputBackground)
        .cornerRadius(AppRadius.medium)
    }

    func trendColor(for trend: TrendDirection) -> Color {
        switch trend {
        case .improving: return .green
        case .stable: return .blue
        case .worsening: return .red
        }
    }
}

// MARK: - Enhanced History Entry Card

struct EnhancedHistoryEntryCard: View {
    let entry: DTCHistoryEntry
    let previousEntry: DTCHistoryEntry?
    let onDelete: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더 (항상 표시)
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: AppSpacing.md) {
                    // 심각도 아이콘
                    ZStack {
                        Circle()
                            .fill(severityColor(entry.highestSeverity).opacity(0.2))
                            .frame(width: 40, height: 40)

                        Image(systemName: severityIcon(entry.highestSeverity))
                            .font(.system(size: 18))
                            .foregroundColor(severityColor(entry.highestSeverity))
                    }

                    // 시간 및 요약 정보
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.relativeTimeString)
                                .font(AppTypography.headline)
                                .foregroundColor(.primaryText)

                            if let note = entry.note, !note.isEmpty {
                                Image(systemName: "note.text")
                                    .font(.system(size: 12))
                                    .foregroundColor(.accentGreen)
                            }
                        }

                        HStack(spacing: 8) {
                            Text("\(entry.dtcCount)개 고장")
                                .font(AppTypography.caption)
                                .foregroundColor(.secondaryText)

                            // 심각도 도트
                            if !entry.dtcDetails.isEmpty {
                                SeverityDots(severityCounts: entry.severityCounts)
                            }
                        }
                    }

                    Spacer()

                    // 비교 표시
                    if let previous = previousEntry {
                        ComparisonBadge(current: entry, previous: previous)
                    }

                    // 확장 아이콘
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14))
                        .foregroundColor(.secondaryText)
                }
                .padding(AppSpacing.md)
            }
            .buttonStyle(PlainButtonStyle())

            // 확장된 내용
            if isExpanded {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Divider()
                        .padding(.horizontal, AppSpacing.md)

                    // 메모 (있는 경우)
                    if let note = entry.note, !note.isEmpty {
                        HStack(alignment: .top, spacing: AppSpacing.sm) {
                            Image(systemName: "note.text")
                                .font(.system(size: 14))
                                .foregroundColor(.accentGreen)
                            Text(note)
                                .font(AppTypography.caption)
                                .foregroundColor(.secondaryText)
                        }
                        .padding(.horizontal, AppSpacing.md)
                    }

                    // DTC 코드 목록 (상세 정보 포함)
                    if !entry.dtcDetails.isEmpty {
                        ForEach(entry.dtcDetails) { dtc in
                            DTCDetailRow(dtc: dtc)
                                .padding(.horizontal, AppSpacing.md)
                        }
                    } else if !entry.dtcCodes.isEmpty {
                        // dtcDetails가 없는 경우 (레거시 데이터)
                        ForEach(entry.dtcCodes, id: \.self) { code in
                            HStack(spacing: AppSpacing.sm) {
                                Text("•")
                                    .foregroundColor(.secondaryText)
                                Text(code)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.primaryText)
                                Spacer()
                            }
                            .padding(.horizontal, AppSpacing.md)
                        }
                    } else {
                        // 정상 (코드 없음)
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("고장 코드 없음")
                                .font(AppTypography.body)
                                .foregroundColor(.primaryText)
                        }
                        .padding(.horizontal, AppSpacing.md)
                    }

                    // 비교 상세 (이전 스캔이 있는 경우)
                    if let previous = previousEntry, !entry.dtcCodes.isEmpty || !previous.dtcCodes.isEmpty {
                        Divider()
                            .padding(.horizontal, AppSpacing.md)

                        ComparisonDetailView(current: entry, previous: previous)
                            .padding(.horizontal, AppSpacing.md)
                    }
                }
                .padding(.bottom, AppSpacing.md)
            }
        }
        .background(Color.inputBackground)
        .cornerRadius(AppRadius.medium)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("삭제", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("삭제", systemImage: "trash")
            }
        }
    }

    func severityIcon(_ severity: DTCSeverity) -> String {
        switch severity {
        case .critical: return "exclamationmark.triangle.fill"
        case .high: return "exclamationmark.circle.fill"
        case .medium: return "info.circle.fill"
        case .low: return "checkmark.circle.fill"
        }
    }

    func severityColor(_ severity: DTCSeverity) -> Color {
        switch severity {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .blue
        }
    }
}

// MARK: - Severity Dots

struct SeverityDots: View {
    let severityCounts: [DTCSeverity: Int]

    var body: some View {
        HStack(spacing: 4) {
            ForEach([DTCSeverity.critical, .high, .medium, .low], id: \.self) { severity in
                if let count = severityCounts[severity], count > 0 {
                    ForEach(0..<min(count, 3), id: \.self) { _ in
                        Circle()
                            .fill(colorFor(severity))
                            .frame(width: 6, height: 6)
                    }
                    if count > 3 {
                        Text("+\(count - 3)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondaryText)
                    }
                }
            }
        }
    }

    func colorFor(_ severity: DTCSeverity) -> Color {
        switch severity {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .blue
        }
    }
}

// MARK: - DTC Detail Row

struct DTCDetailRow: View {
    let dtc: DTCDisplayCode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // 심각도 배지
                Text(dtc.severity.displayText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(dtc.severity.color)
                    .cornerRadius(4)

                Text(dtc.code)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.primaryText)

                Spacer()
            }

            Text(dtc.description)
                .font(AppTypography.caption)
                .foregroundColor(.secondaryText)
                .padding(.leading, AppSpacing.sm)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Comparison Badge

struct ComparisonBadge: View {
    let current: DTCHistoryEntry
    let previous: DTCHistoryEntry

    var body: some View {
        let diff = current.dtcCount - previous.dtcCount

        if diff < 0 {
            // 개선됨
            HStack(spacing: 2) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 10))
                Text("\(abs(diff))")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.green)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green.opacity(0.2))
            .cornerRadius(4)
        } else if diff > 0 {
            // 악화됨
            HStack(spacing: 2) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 10))
                Text("+\(diff)")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.red)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.red.opacity(0.2))
            .cornerRadius(4)
        }
    }
}

// MARK: - Comparison Detail View

struct ComparisonDetailView: View {
    let current: DTCHistoryEntry
    let previous: DTCHistoryEntry

    var comparison: ScanComparison {
        let currentCodes = Set(current.dtcCodes)
        let previousCodes = Set(previous.dtcCodes)

        return ScanComparison(
            resolved: Array(previousCodes.subtracting(currentCodes)),
            new: Array(currentCodes.subtracting(previousCodes)),
            persistent: Array(currentCodes.intersection(previousCodes))
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("이전 스캔과 비교")
                .font(AppTypography.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondaryText)

            if !comparison.resolved.isEmpty {
                ComparisonSection(
                    icon: "checkmark.circle.fill",
                    color: .green,
                    title: "해결됨",
                    codes: comparison.resolved
                )
            }

            if !comparison.new.isEmpty {
                ComparisonSection(
                    icon: "exclamationmark.triangle.fill",
                    color: .red,
                    title: "새로 발생",
                    codes: comparison.new
                )
            }

            if !comparison.persistent.isEmpty {
                ComparisonSection(
                    icon: "arrow.clockwise.circle.fill",
                    color: .orange,
                    title: "여전히 존재",
                    codes: comparison.persistent
                )
            }
        }
    }
}

struct ComparisonSection: View {
    let icon: String
    let color: Color
    let title: String
    let codes: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
                Text(title)
                    .font(AppTypography.caption)
                    .foregroundColor(color)
            }

            ForEach(codes, id: \.self) { code in
                Text("• \(code)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondaryText)
                    .padding(.leading, AppSpacing.md)
            }
        }
    }
}

// MARK: - History Entry Card (레거시 - 호환성 유지)

struct HistoryEntryCard: View {
    let entry: DTCHistoryEntry
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Button(action: {
                withAnimation {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: AppSpacing.md) {
                    // Time Icon
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 40, height: 40)

                        Image(systemName: "clock.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                    }

                    // Entry Info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.formattedTime)
                            .font(AppTypography.headline)
                            .foregroundColor(.primaryText)

                        Text("\(entry.dtcCount)개의 고장 코드")
                            .font(AppTypography.caption)
                            .foregroundColor(.secondaryText)
                    }

                    Spacer()

                    // Expand Icon
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14))
                        .foregroundColor(.secondaryText)
                }
                .padding(AppSpacing.md)
            }
            .buttonStyle(PlainButtonStyle())

            // Expanded Content
            if isExpanded {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Divider()
                        .padding(.horizontal, AppSpacing.md)

                    ForEach(entry.dtcCodes, id: \.self) { code in
                        HStack(spacing: AppSpacing.sm) {
                            Text("•")
                                .foregroundColor(.secondaryText)

                            Text(code)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.primaryText)

                            Spacer()
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, 2)
                    }
                }
                .padding(.bottom, AppSpacing.sm)
            }
        }
        .background(Color.inputBackground)
        .cornerRadius(AppRadius.medium)
    }
}

// MARK: - Preview

#Preview {
    DiagnosticsView()
}
