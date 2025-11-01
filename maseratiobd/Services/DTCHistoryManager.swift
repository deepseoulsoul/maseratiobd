//
//  DTCHistoryManager.swift
//  mycar
//
//  Created by Jin Shin on 10/31/25.
//  DTC 스캔 기록 관리
//

import Foundation

// MARK: - Models

/// DTC 히스토리 항목 (확장된 버전)
struct DTCHistoryEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let dtcCodes: [String]
    let dtcDetails: [DTCDisplayCode]  // 심각도 포함 상세 정보
    let dtcCount: Int
    var note: String?  // 사용자 메모

    init(id: UUID = UUID(), timestamp: Date = Date(), dtcCodes: [String], dtcDetails: [DTCDisplayCode] = [], note: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.dtcCodes = dtcCodes
        self.dtcDetails = dtcDetails
        self.dtcCount = dtcCodes.count
        self.note = note
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy년 M월 d일"
        return formatter.string(from: timestamp)
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: timestamp)
    }

    var formattedTimeWithPeriod: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "a h:mm"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter.string(from: timestamp)
    }

    var formattedDateTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: timestamp)
    }

    // 상대 시간 표시 (방금 전, 5분 전, 1시간 전 등)
    var relativeTimeString: String {
        let now = Date()
        let interval = now.timeIntervalSince(timestamp)

        if interval < 60 {
            return "방금 전"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)분 전"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)시간 전"
        } else if interval < 172800 {
            return "어제 \(formattedTime)"
        } else {
            return formattedDate
        }
    }

    // 심각도별 개수
    var severityCounts: [DTCSeverity: Int] {
        var counts: [DTCSeverity: Int] = [:]
        for detail in dtcDetails {
            counts[detail.severity, default: 0] += 1
        }
        return counts
    }

    // 가장 높은 심각도
    var highestSeverity: DTCSeverity {
        if severityCounts[.critical, default: 0] > 0 { return .critical }
        if severityCounts[.high, default: 0] > 0 { return .high }
        if severityCounts[.medium, default: 0] > 0 { return .medium }
        return .low
    }
}

// MARK: - DTCHistoryManager

class DTCHistoryManager: ObservableObject {
    static let shared = DTCHistoryManager()

    @Published var history: [DTCHistoryEntry] = []

    private let userDefaultsKey = "dtc_scan_history"
    private let maxHistoryCount = 50  // 최대 50개 기록 저장

    private init() {
        loadHistory()
    }

    // MARK: - Public Methods

    /// 새로운 스캔 결과 저장 (상세 정보 포함)
    func saveScan(dtcCodes: [String], dtcDetails: [DTCDisplayCode]) {
        guard !dtcCodes.isEmpty else {
            print("⚠️ [History] No DTCs to save")
            return
        }

        let entry = DTCHistoryEntry(dtcCodes: dtcCodes, dtcDetails: dtcDetails)

        // 새 항목을 맨 앞에 추가
        history.insert(entry, at: 0)

        // 최대 개수 제한
        if history.count > maxHistoryCount {
            history = Array(history.prefix(maxHistoryCount))
        }

        persistHistory()

        print("✅ [History] Saved scan with \(dtcCodes.count) DTCs")
        print("📊 [History] Total history entries: \(history.count)")
    }

    /// 하위 호환성을 위한 레거시 메서드
    func saveScan(dtcCodes: [String]) {
        saveScan(dtcCodes: dtcCodes, dtcDetails: [])
    }

    /// 특정 히스토리 항목 삭제
    func deleteEntry(_ entry: DTCHistoryEntry) {
        history.removeAll { $0.id == entry.id }
        persistHistory()

        print("🗑️ [History] Deleted entry: \(entry.formattedDateTime)")
    }

    /// 모든 히스토리 삭제
    func clearAllHistory() {
        history.removeAll()
        persistHistory()

        print("🗑️ [History] Cleared all history")
    }

    /// 최근 스캔 결과 가져오기
    func getLatestScan() -> DTCHistoryEntry? {
        return history.first
    }

    /// 날짜별로 그룹화된 히스토리
    func getGroupedHistory() -> [(String, [DTCHistoryEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: history) { entry in
            calendar.startOfDay(for: entry.timestamp)
        }

        return grouped
            .sorted { $0.key > $1.key }  // 최신 날짜부터
            .map { (dateString(from: $0.key), $0.value.sorted { $0.timestamp > $1.timestamp }) }
    }

    /// 두 스캔 결과 비교
    func compareScan(_ current: DTCHistoryEntry, with previous: DTCHistoryEntry) -> ScanComparison {
        let currentCodes = Set(current.dtcCodes)
        let previousCodes = Set(previous.dtcCodes)

        let resolved = previousCodes.subtracting(currentCodes)
        let new = currentCodes.subtracting(previousCodes)
        let persistent = currentCodes.intersection(previousCodes)

        return ScanComparison(
            resolved: Array(resolved),
            new: Array(new),
            persistent: Array(persistent)
        )
    }

    /// 최근 7일 트렌드 분석
    func getTrendAnalysis() -> TrendAnalysis {
        let calendar = Calendar.current
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: Date())!

        let recentHistory = history.filter { $0.timestamp >= sevenDaysAgo }

        let totalScans = recentHistory.count
        let averageDTCs = totalScans > 0 ? Double(recentHistory.reduce(0) { $0 + $1.dtcCount }) / Double(totalScans) : 0

        // 가장 자주 발견되는 코드 TOP 3
        var codeCounts: [String: Int] = [:]
        for entry in recentHistory {
            for code in entry.dtcCodes {
                codeCounts[code, default: 0] += 1
            }
        }
        let topCodes = codeCounts.sorted { $0.value > $1.value }.prefix(3).map { ($0.key, $0.value) }

        // 트렌드 계산 (첫 스캔 vs 최근 스캔)
        let trend: TrendDirection
        if recentHistory.count >= 2 {
            let firstScan = recentHistory.last!
            let latestScan = recentHistory.first!
            if latestScan.dtcCount < firstScan.dtcCount {
                trend = .improving
            } else if latestScan.dtcCount > firstScan.dtcCount {
                trend = .worsening
            } else {
                trend = .stable
            }
        } else {
            trend = .stable
        }

        return TrendAnalysis(
            totalScans: totalScans,
            averageDTCs: averageDTCs,
            topCodes: topCodes,
            trend: trend
        )
    }

    /// 목업 데이터 생성 (테스트용)
    func generateMockData() {
        print("🧪 [History] Generating mock data...")

        let mockEntries: [DTCHistoryEntry] = [
            // 오늘 - 방금 전 (1분 전)
            DTCHistoryEntry(
                timestamp: Date().addingTimeInterval(-60),
                dtcCodes: ["P0300", "P0420", "P0442"],
                dtcDetails: [
                    DTCDisplayCode(code: "P0300", description: "엔진 실화 (다중 실린더)", englishDescription: "Random/Multiple Cylinder Misfire Detected", system: "Powertrain", severity: .critical),
                    DTCDisplayCode(code: "P0420", description: "촉매 시스템 효율 저하", englishDescription: "Catalyst System Efficiency Below Threshold", system: "Powertrain", severity: .high),
                    DTCDisplayCode(code: "P0442", description: "증발가스 시스템 소형 누출", englishDescription: "EVAP System Small Leak Detected", system: "Powertrain", severity: .medium)
                ]
            ),
            // 오늘 - 2시간 전
            DTCHistoryEntry(
                timestamp: Date().addingTimeInterval(-7200),
                dtcCodes: ["P0300", "C0040", "P0420"],
                dtcDetails: [
                    DTCDisplayCode(code: "P0300", description: "엔진 실화 (다중 실린더)", englishDescription: "Random/Multiple Cylinder Misfire Detected", system: "Powertrain", severity: .critical),
                    DTCDisplayCode(code: "C0040", description: "ABS 모듈 통신 오류", englishDescription: "ABS Module Communication Error", system: "Chassis", severity: .critical),
                    DTCDisplayCode(code: "P0420", description: "촉매 시스템 효율 저하", englishDescription: "Catalyst System Efficiency Below Threshold", system: "Powertrain", severity: .high)
                ],
                note: "정비소 방문 전 스캔"
            ),
            // 어제 - 오전
            DTCHistoryEntry(
                timestamp: Date().addingTimeInterval(-86400 - 10800),
                dtcCodes: ["P0300", "C0040", "P0420", "P0133"],
                dtcDetails: [
                    DTCDisplayCode(code: "P0300", description: "엔진 실화 (다중 실린더)", englishDescription: "Random/Multiple Cylinder Misfire Detected", system: "Powertrain", severity: .critical),
                    DTCDisplayCode(code: "C0040", description: "ABS 모듈 통신 오류", englishDescription: "ABS Module Communication Error", system: "Chassis", severity: .critical),
                    DTCDisplayCode(code: "P0420", description: "촉매 시스템 효율 저하", englishDescription: "Catalyst System Efficiency Below Threshold", system: "Powertrain", severity: .high),
                    DTCDisplayCode(code: "P0133", description: "산소 센서 응답 속도 저하", englishDescription: "O2 Sensor Circuit Slow Response", system: "Powertrain", severity: .high)
                ]
            ),
            // 어제 - 오후
            DTCHistoryEntry(
                timestamp: Date().addingTimeInterval(-86400),
                dtcCodes: ["P0420", "P0133"],
                dtcDetails: [
                    DTCDisplayCode(code: "P0420", description: "촉매 시스템 효율 저하", englishDescription: "Catalyst System Efficiency Below Threshold", system: "Powertrain", severity: .high),
                    DTCDisplayCode(code: "P0133", description: "산소 센서 응답 속도 저하", englishDescription: "O2 Sensor Circuit Slow Response", system: "Powertrain", severity: .high)
                ],
                note: "점화 플러그 교체 후"
            ),
            // 3일 전
            DTCHistoryEntry(
                timestamp: Date().addingTimeInterval(-259200),
                dtcCodes: ["P0420"],
                dtcDetails: [
                    DTCDisplayCode(code: "P0420", description: "촉매 시스템 효율 저하", englishDescription: "Catalyst System Efficiency Below Threshold", system: "Powertrain", severity: .high)
                ]
            ),
            // 5일 전
            DTCHistoryEntry(
                timestamp: Date().addingTimeInterval(-432000),
                dtcCodes: ["P0442", "B1657"],
                dtcDetails: [
                    DTCDisplayCode(code: "P0442", description: "증발가스 시스템 소형 누출", englishDescription: "EVAP System Small Leak Detected", system: "Powertrain", severity: .medium),
                    DTCDisplayCode(code: "B1657", description: "공압 제어 시스템 고장", englishDescription: "Pneumatic Pressure Control Siemens", system: "Body", severity: .low)
                ]
            ),
            // 7일 전
            DTCHistoryEntry(
                timestamp: Date().addingTimeInterval(-604800),
                dtcCodes: [],
                dtcDetails: [],
                note: "정상 - 고장 코드 없음"
            )
        ]

        history = mockEntries
        persistHistory()

        print("✅ [History] Generated \(mockEntries.count) mock entries")
    }

    // MARK: - Private Methods

    private func persistHistory() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(history)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)

            print("💾 [History] Persisted \(history.count) entries")
        } catch {
            print("❌ [History] Failed to persist: \(error)")
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            print("ℹ️ [History] No saved history found")
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            history = try decoder.decode([DTCHistoryEntry].self, from: data)

            print("✅ [History] Loaded \(history.count) entries")
        } catch {
            print("❌ [History] Failed to load: \(error)")
            history = []
        }
    }

    private func dateString(from date: Date) -> String {
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
}

// MARK: - Supporting Structures

/// 스캔 비교 결과
struct ScanComparison {
    let resolved: [String]   // 해결된 코드
    let new: [String]         // 새로 발생한 코드
    let persistent: [String]  // 여전히 존재하는 코드
}

/// 트렌드 방향
enum TrendDirection: String, Codable {
    case improving = "improving"   // 개선 중
    case stable = "stable"          // 안정
    case worsening = "worsening"    // 악화 중

    var displayText: String {
        switch self {
        case .improving: return "개선 중"
        case .stable: return "안정"
        case .worsening: return "악화 중"
        }
    }

    var icon: String {
        switch self {
        case .improving: return "arrow.down.circle.fill"
        case .stable: return "equal.circle.fill"
        case .worsening: return "arrow.up.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .improving: return "green"
        case .stable: return "blue"
        case .worsening: return "red"
        }
    }
}

/// 트렌드 분석 결과
struct TrendAnalysis {
    let totalScans: Int
    let averageDTCs: Double
    let topCodes: [(code: String, count: Int)]
    let trend: TrendDirection
}
