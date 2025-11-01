//
//  DTCDatabase.swift
//  maseratiobd
//
//  Created by Jin Shin on 10/30/25.
//  DTC 데이터베이스 서비스 - Server API 통합
//

import Foundation

// MARK: - Models (Backward Compatibility)

/// DTC (Diagnostic Trouble Code) 정보 - 레거시 호환용
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
    let ko: String?
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

/// 통합 DTC 정보 (Server API Response 기반)
struct CombinedDTCInfo {
    let dtcCode: String
    let dtcInfo: DTCInfo?
    let faultInfo: FaultInfo?
    let serverResponse: DTCCodeResponse?

    /// 한국어 설명 (우선순위: 서버 > fault > dtc > fallback)
    var displayDescription: String {
        // 1. 서버에서 받은 설명 (최우선)
        if let serverDesc = serverResponse?.description {
            print("📝 [DTCDatabase] Using server description: \(serverDesc)")
            return serverDesc
        }

        // 2. Fault 정보의 한국어/영어
        if let fault = faultInfo {
            let desc = fault.description.ko ?? fault.description.en
            print("📝 [DTCDatabase] Using fault description: \(desc)")
            return desc
        }

        // 3. DTC 정보
        if let dtc = dtcInfo {
            print("📝 [DTCDatabase] Using DTC description: \(dtc.description)")
            return dtc.description
        }

        // 4. Fallback
        print("⚠️ [DTCDatabase] No description found for \(dtcCode), using fallback")
        return "알 수 없는 코드"
    }

    /// 영어 설명
    var englishDescription: String {
        serverResponse?.description ??
        faultInfo?.description.en ??
        dtcInfo?.description ??
        "Unknown code"
    }

    /// 시스템 분류
    var system: String {
        serverResponse?.system ??
        dtcInfo?.system ??
        getSystemFromCode(dtcCode)
    }

    /// DTC 타입
    var type: String {
        serverResponse?.type ??
        dtcInfo?.type ??
        "Unknown"
    }

    /// 심각도 (서버에서 제공)
    var severity: String {
        serverResponse?.severity ?? "Medium"
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

    // Server cache
    private var codeCache: [String: DTCCodeResponse] = [:]

    // Legacy local data (fallback only)
    private var standardDTCs: [String: DTCInfo] = [:]
    private var manufacturerDTCs: [String: DTCInfo] = [:]
    private var faults: [String: FaultInfo] = [:]

    private var isLoaded = false

    private init() {
        print("🚀 [DTCDatabase] Initializing with Server API")
        loadLocalDatabases()  // Fallback용으로만 로드
    }

    // MARK: - Server API Methods

    /// DTC 코드로 정보 조회 (서버 우선, 캐시 fallback)
    func lookup(dtcCode: String) async -> CombinedDTCInfo {
        let normalizedCode = dtcCode.uppercased().trimmingCharacters(in: .whitespaces)
        print("🔍 [DTCDatabase] Looking up: \(normalizedCode)")

        // Try server first
        do {
            let response = try await APIService.shared.getDTCCode(normalizedCode)
            print("✅ [DTCDatabase] Server lookup success: \(response.description)")

            // Cache the result
            codeCache[normalizedCode] = response

            return CombinedDTCInfo(
                dtcCode: normalizedCode,
                dtcInfo: nil,
                faultInfo: nil,
                serverResponse: response
            )
        } catch {
            print("⚠️ [DTCDatabase] Server lookup failed: \(error.localizedDescription)")
            print("📦 [DTCDatabase] Trying cache...")

            // Fallback to cache
            if let cached = codeCache[normalizedCode] {
                print("✅ [DTCDatabase] Cache hit: \(cached.description)")
                return CombinedDTCInfo(
                    dtcCode: normalizedCode,
                    dtcInfo: nil,
                    faultInfo: nil,
                    serverResponse: cached
                )
            }

            print("📚 [DTCDatabase] Cache miss, trying local database...")

            // Last resort: local database
            return lookupLocal(dtcCode: normalizedCode)
        }
    }

    /// 동기 버전 - 캐시만 사용 (UI에서 즉시 필요한 경우)
    func lookupSync(dtcCode: String) -> CombinedDTCInfo {
        let normalizedCode = dtcCode.uppercased().trimmingCharacters(in: .whitespaces)
        print("⚡ [DTCDatabase] Sync lookup: \(normalizedCode)")

        // Check cache first
        if let cached = codeCache[normalizedCode] {
            print("✅ [DTCDatabase] Cache hit (sync): \(cached.description)")
            return CombinedDTCInfo(
                dtcCode: normalizedCode,
                dtcInfo: nil,
                faultInfo: nil,
                serverResponse: cached
            )
        }

        // Fallback to local
        print("📚 [DTCDatabase] Cache miss (sync), using local")
        return lookupLocal(dtcCode: normalizedCode)
    }

    /// 여러 DTC 코드 일괄 조회 (병렬 처리)
    func lookup(dtcCodes: [String]) async -> [CombinedDTCInfo] {
        print("🔍 [DTCDatabase] Batch lookup: \(dtcCodes.count) codes")

        return await withTaskGroup(of: CombinedDTCInfo.self) { group in
            for code in dtcCodes {
                group.addTask {
                    await self.lookup(dtcCode: code)
                }
            }

            var results: [CombinedDTCInfo] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    /// 키워드로 DTC 검색 (서버 API 사용)
    func search(keyword: String, limit: Int = 10) async throws -> [CombinedDTCInfo] {
        print("🔎 [DTCDatabase] Searching: '\(keyword)' (limit: \(limit))")

        let response = try await APIService.shared.searchDTCCodes(
            query: keyword,
            limit: limit
        )

        print("✅ [DTCDatabase] Search found \(response.count) results")

        return response.results.map { serverResponse in
            // Cache the result
            codeCache[serverResponse.code] = serverResponse

            return CombinedDTCInfo(
                dtcCode: serverResponse.code,
                dtcInfo: nil,
                faultInfo: nil,
                serverResponse: serverResponse
            )
        }
    }

    /// 시스템별 DTC 필터링 (서버 API 사용)
    func filterBySystem(_ system: String, limit: Int = 20) async throws -> [CombinedDTCInfo] {
        print("📊 [DTCDatabase] Filtering by system: \(system)")

        let response = try await APIService.shared.searchDTCCodes(
            system: system,
            limit: limit
        )

        print("✅ [DTCDatabase] Found \(response.count) codes for system: \(system)")

        return response.results.map { serverResponse in
            codeCache[serverResponse.code] = serverResponse

            return CombinedDTCInfo(
                dtcCode: serverResponse.code,
                dtcInfo: nil,
                faultInfo: nil,
                serverResponse: serverResponse
            )
        }
    }

    /// 데이터베이스 통계 (서버에서 가져오기)
    func getStatistics() async throws -> DatabaseStatistics {
        print("📊 [DTCDatabase] Fetching statistics from server...")

        let stats = try await APIService.shared.getDTCStats()

        print("✅ [DTCDatabase] Stats: \(stats.total) total codes")

        let categoryCounts = Dictionary(
            uniqueKeysWithValues: stats.byCategory.map { ($0.category, Int($0.count) ?? 0) }
        )

        return DatabaseStatistics(
            standardDTCCount: categoryCounts["SAE"] ?? 0,
            manufacturerDTCCount: categoryCounts["Manufacturer"] ?? 0,
            faultCodeCount: categoryCounts["AlfaOBD"] ?? 0,
            totalCount: stats.total
        )
    }

    /// 캐시 프리로드 (앱 시작 시 자주 사용하는 코드들)
    func preloadCommonCodes() async {
        print("🔄 [DTCDatabase] Preloading common DTC codes...")

        let commonCodes = [
            "P0300", "P0301", "P0302", "P0420", "P0430",
            "P0171", "P0174", "P0442", "P0455", "C0040"
        ]

        for code in commonCodes {
            _ = await lookup(dtcCode: code)
        }

        print("✅ [DTCDatabase] Preloaded \(commonCodes.count) common codes")
    }

    // MARK: - Local Database (Fallback)

    private func loadLocalDatabases() {
        guard !isLoaded else { return }

        print("📚 [DTCDatabase] Loading local databases (fallback only)...")

        // Load standard DTCs
        if let standardData: [String: DTCInfo] = loadJSONFile(named: "dtc_database_complete") {
            standardDTCs = standardData
            print("✅ [DTCDatabase] Loaded \(standardDTCs.count) standard DTCs (local)")
        }

        // Load manufacturer-specific DTCs
        if let manufacturerData: [String: DTCInfo] = loadJSONFile(named: "dtc_manufacturer_specific") {
            manufacturerDTCs = manufacturerData
            print("✅ [DTCDatabase] Loaded \(manufacturerDTCs.count) manufacturer DTCs (local)")
        }

        // Load faults database
        if let faultsData: [String: FaultInfo] = loadJSONFile(named: "faults_database_complete") {
            faults = faultsData
            print("✅ [DTCDatabase] Loaded \(faults.count) fault codes (local)")
        }

        isLoaded = true
        print("✅ [DTCDatabase] Local databases loaded (for fallback)")
    }

    private func loadJSONFile<T: Codable>(named fileName: String) -> [String: T]? {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "json") else {
            print("⚠️ [DTCDatabase] File not found: \(fileName).json")
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

    private func lookupLocal(dtcCode: String) -> CombinedDTCInfo {
        let normalizedCode = dtcCode.uppercased().trimmingCharacters(in: .whitespaces)

        // DTC 정보 조회 (standard 우선, 없으면 manufacturer)
        let dtcInfo = standardDTCs[normalizedCode] ?? manufacturerDTCs[normalizedCode]

        // Fault 정보 조회 (hexcode 추출)
        var faultInfo: FaultInfo?
        if let hexcode = extractHexcode(from: dtcInfo?.fullCode ?? "") {
            faultInfo = faults[hexcode]
        }

        if dtcInfo != nil || faultInfo != nil {
            print("✅ [DTCDatabase] Local lookup success")
        } else {
            print("⚠️ [DTCDatabase] Code not found in local database")
        }

        return CombinedDTCInfo(
            dtcCode: normalizedCode,
            dtcInfo: dtcInfo,
            faultInfo: faultInfo,
            serverResponse: nil
        )
    }

    /// full_code에서 hexcode 추출 (뒤 4자리)
    private func extractHexcode(from fullCode: String) -> String? {
        guard fullCode.count >= 4 else { return nil }
        let hexcode = String(fullCode.suffix(4))
        return hexcode
    }

    // MARK: - Cache Management

    /// 캐시 클리어
    func clearCache() {
        print("🧹 [DTCDatabase] Clearing cache (\(codeCache.count) items)")
        codeCache.removeAll()
    }

    /// 캐시 크기
    var cacheSize: Int {
        codeCache.count
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
        • Standard DTCs (SAE): \(standardDTCCount)
        • Manufacturer DTCs: \(manufacturerDTCCount)
        • Fault Codes (AlfaOBD): \(faultCodeCount)
        • Total: \(totalCount)
        """
    }
}
