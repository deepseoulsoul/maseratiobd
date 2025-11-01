//
//  DTCDatabase.swift
//  mycar
//
//  Created by Jin Shin on 10/30/25.
//  DTC 및 Fault Code 데이터베이스 서비스
//

import Foundation

// MARK: - Models

/// DTC (Diagnostic Trouble Code) 정보
struct DTCInfo: Codable {
    let code: String
    let fullCode: String
    let deviceId: Int
    let description: String
    let system: String
    let type: String

    enum CodingKeys: String, CodingKey {
        case code
        case fullCode = "full_code"
        case deviceId = "device_id"
        case description
        case system
        case type
    }
}

/// Fault Code 다국어 설명
struct FaultDescription: Codable {
    let en: String
    let de: String?
    let it: String?
    let es: String?
    let fr: String?
    let ko: String?  // 한국어 (추후 번역 추가 시)
}

/// Fault Code 정보
struct FaultInfo: Codable {
    let hexcode: String
    let deviceIds: [Int]
    let description: FaultDescription

    enum CodingKeys: String, CodingKey {
        case hexcode
        case deviceIds = "device_ids"
        case description
    }
}

/// 통합 DTC 정보 (DTC + Fault 정보 결합)
struct CombinedDTCInfo {
    let dtcCode: String
    let dtcInfo: DTCInfo?
    let faultInfo: FaultInfo?

    /// 한국어 설명 (영어 fallback)
    var displayDescription: String {
        if let fault = faultInfo {
            return fault.description.ko ?? fault.description.en
        }
        return dtcInfo?.description ?? "알 수 없는 코드"
    }

    /// 영어 설명
    var englishDescription: String {
        faultInfo?.description.en ?? dtcInfo?.description ?? "Unknown code"
    }

    /// 시스템 분류
    var system: String {
        dtcInfo?.system ?? getSystemFromCode(dtcCode)
    }

    /// DTC 타입 (SAE Standard / Manufacturer Specific)
    var type: String {
        dtcInfo?.type ?? "Unknown"
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
}

// MARK: - DTCDatabase

class DTCDatabase {
    static let shared = DTCDatabase()

    private var standardDTCs: [String: DTCInfo] = [:]
    private var manufacturerDTCs: [String: DTCInfo] = [:]
    private var faults: [String: FaultInfo] = [:]

    private var isLoaded = false

    private init() {
        loadDatabases()
    }

    // MARK: - Database Loading

    private func loadDatabases() {
        guard !isLoaded else { return }

        print("📚 [DTCDatabase] Loading databases...")

        // Load standard DTCs
        if let standardData: [String: DTCInfo] = loadJSONFile(named: "dtc_database_complete") {
            standardDTCs = standardData
            print("✅ [DTCDatabase] Loaded \(standardDTCs.count) standard DTCs")
        }

        // Load manufacturer-specific DTCs
        if let manufacturerData: [String: DTCInfo] = loadJSONFile(named: "dtc_manufacturer_specific") {
            manufacturerDTCs = manufacturerData
            print("✅ [DTCDatabase] Loaded \(manufacturerDTCs.count) manufacturer DTCs")
        }

        // Load faults database
        if let faultsData: [String: FaultInfo] = loadJSONFile(named: "faults_database_complete") {
            faults = faultsData
            print("✅ [DTCDatabase] Loaded \(faults.count) fault codes")
        }

        isLoaded = true
        print("✅ [DTCDatabase] All databases loaded successfully")
    }

    private func loadJSONFile<T: Codable>(named fileName: String) -> [String: T]? {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "json") else {
            print("❌ [DTCDatabase] File not found: \(fileName).json")
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([String: T].self, from: data)
            return decoded
        } catch {
            print("❌ [DTCDatabase] Failed to load \(fileName).json: \(error)")
            return nil
        }
    }

    // MARK: - Public Methods

    /// DTC 코드로 정보 조회
    func lookup(dtcCode: String) -> CombinedDTCInfo {
        let normalizedCode = dtcCode.uppercased().trimmingCharacters(in: .whitespaces)

        // DTC 정보 조회 (standard 우선, 없으면 manufacturer)
        let dtcInfo = standardDTCs[normalizedCode] ?? manufacturerDTCs[normalizedCode]

        // Fault 정보 조회 (hexcode 추출)
        var faultInfo: FaultInfo?
        if let hexcode = extractHexcode(from: dtcInfo?.fullCode ?? "") {
            faultInfo = faults[hexcode]
        }

        return CombinedDTCInfo(
            dtcCode: normalizedCode,
            dtcInfo: dtcInfo,
            faultInfo: faultInfo
        )
    }

    /// 여러 DTC 코드 일괄 조회
    func lookup(dtcCodes: [String]) -> [CombinedDTCInfo] {
        dtcCodes.map { lookup(dtcCode: $0) }
    }

    /// Hexcode로 Fault 정보 조회
    func lookupFault(hexcode: String) -> FaultInfo? {
        faults[hexcode.uppercased()]
    }

    /// 키워드로 DTC 검색 (description에서 검색)
    func search(keyword: String) -> [CombinedDTCInfo] {
        let lowercasedKeyword = keyword.lowercased()
        var results: [CombinedDTCInfo] = []

        // Standard DTCs 검색
        for (code, dtc) in standardDTCs {
            if dtc.description.lowercased().contains(lowercasedKeyword) ||
               code.lowercased().contains(lowercasedKeyword) {
                results.append(lookup(dtcCode: code))
            }
        }

        // Manufacturer DTCs 검색
        for (code, dtc) in manufacturerDTCs {
            if dtc.description.lowercased().contains(lowercasedKeyword) ||
               code.lowercased().contains(lowercasedKeyword) {
                results.append(lookup(dtcCode: code))
            }
        }

        return results
    }

    /// 시스템별 DTC 필터링
    func filterBySystem(_ system: String) -> [CombinedDTCInfo] {
        var results: [CombinedDTCInfo] = []

        for (code, dtc) in standardDTCs where dtc.system == system {
            results.append(lookup(dtcCode: code))
        }

        for (code, dtc) in manufacturerDTCs where dtc.system == system {
            results.append(lookup(dtcCode: code))
        }

        return results
    }

    /// 데이터베이스 통계
    func getStatistics() -> DatabaseStatistics {
        DatabaseStatistics(
            standardDTCCount: standardDTCs.count,
            manufacturerDTCCount: manufacturerDTCs.count,
            faultCodeCount: faults.count,
            totalCount: standardDTCs.count + manufacturerDTCs.count
        )
    }

    // MARK: - Private Helpers

    /// full_code에서 hexcode 추출 (뒤 4자리)
    private func extractHexcode(from fullCode: String) -> String? {
        guard fullCode.count >= 4 else { return nil }
        let hexcode = String(fullCode.suffix(4))
        return hexcode
    }
}

// MARK: - Statistics

struct DatabaseStatistics {
    let standardDTCCount: Int
    let manufacturerDTCCount: Int
    let faultCodeCount: Int
    let totalCount: Int

    var summary: String {
        """
        📊 DTC Database Statistics
        • Standard DTCs: \(standardDTCCount)
        • Manufacturer DTCs: \(manufacturerDTCCount)
        • Fault Codes: \(faultCodeCount)
        • Total: \(totalCount)
        """
    }
}
