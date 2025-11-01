import Foundation

// MARK: - Request Models

struct RegisterRequest: Encodable {
    let deviceId: String
    let platform: String = "ios"
    let appVersion: String
}

struct LoginRequest: Encodable {
    let deviceId: String
}

struct RefreshTokenRequest: Encodable {
    let refreshToken: String
}

// MARK: - Response Models

struct AuthResponse: Decodable {
    let userId: String
    let accessToken: String
    let refreshToken: String
    let tier: String
    let subscription: Subscription?
}

struct Subscription: Decodable {
    let tier: String
    let scansLimit: Int
    let scansUsed: Int
    let resetAt: String
    let expiresAt: String?
    let features: SubscriptionFeatures
}

struct SubscriptionFeatures: Decodable {
    let unlimitedScans: Bool
    let stage3Enabled: Bool
    let pdfExport: Bool
    let multipleVehicles: Bool
}
