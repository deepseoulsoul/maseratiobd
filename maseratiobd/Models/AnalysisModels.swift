import Foundation

// MARK: - Request

struct AnalyzeRequest: Encodable {
    let dtcCode: String
    let dtcDescription: String?  // Optional - server will fetch if not provided
    let stage: Int
    let language: String = "ko"
}

struct BatchAnalyzeRequest: Encodable {
    let dtcList: [DTCItem]
    let stage: Int
    let language: String = "ko"

    struct DTCItem: Encodable {
        let code: String
        let description: String?
    }
}

// MARK: - Response

struct AnalysisResponse: Decodable {
    let dtcCode: String
    let stage: Int
    let analysis: String
    let cached: Bool
    let tokensUsed: Int
    let cost: Double
    let usage: UsageInfo?
}

struct BatchAnalysisResponse: Decodable {
    let results: [AnalysisResult]
    let totalTokensUsed: Int
    let totalCost: Double
    let usage: UsageInfo

    struct AnalysisResult: Decodable {
        let code: String
        let analysis: String
        let cached: Bool
    }
}

struct UsageInfo: Decodable {
    let scansRemaining: Int?
    let tier: String
}

// MARK: - Usage Statistics

struct UsageStatsResponse: Decodable {
    let period: String
    let scansCount: Int
    let apiCalls: Int
    let tokensUsed: Int
    let costUsd: Double
    let cachedRate: Double
    let scansLimit: Int
}
