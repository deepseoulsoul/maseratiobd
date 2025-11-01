import Foundation

// MARK: - DTC Code Response

struct DTCCodeResponse: Decodable {
    let id: Int?
    let code: String
    let fullCode: String?
    let deviceId: Int?
    let description: String
    let descriptionTranslations: [String: String]?
    let system: String?
    let category: String
    let severity: String
    let type: String?
    let hexcode: String?
    let deviceIds: [Int]?
    let createdAt: String?
    let updatedAt: String?
}

// MARK: - Search Response

struct DTCSearchResponse: Decodable {
    let results: [DTCCodeResponse]
    let count: Int
    let limit: Int
    let offset: Int
}

// MARK: - Statistics Response

struct DTCStatsResponse: Decodable {
    let total: Int
    let byCategory: [CategoryStat]
    let bySystem: [SystemStat]
    let bySeverity: [SeverityStat]
}

struct CategoryStat: Decodable {
    let category: String
    let count: String
}

struct SystemStat: Decodable {
    let system: String?
    let count: String
}

struct SeverityStat: Decodable {
    let severity: String
    let count: String
}
