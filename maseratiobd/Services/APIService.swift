import Foundation

class APIService {
    static let shared = APIService()

    private let baseURL = "https://maserati.io.kr/obd"
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    private init() {}

    // MARK: - Generic Request Handler

    private func request<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: Encodable? = nil,
        requiresAuth: Bool = false
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add authentication if required
        if requiresAuth {
            guard let token = KeychainHelper.shared.getAccessToken() else {
                throw APIError.unauthorized
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Add body if present
        if let body = body {
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }

        do {
            let result = try decoder.decode(APIResponse<T>.self, from: data)
            if result.success {
                return result.data
            } else {
                throw APIError.serverError(message: result.error?.message ?? "Unknown error")
            }
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Authentication

    func register() async throws -> AuthResponse {
        let deviceId = getDeviceId()
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

        let request = RegisterRequest(
            deviceId: deviceId,
            appVersion: appVersion
        )

        let response: AuthResponse = try await self.request(
            endpoint: "/v1/auth/register",
            method: "POST",
            body: request
        )

        // Save tokens
        KeychainHelper.shared.saveAccessToken(response.accessToken)
        KeychainHelper.shared.saveRefreshToken(response.refreshToken)
        KeychainHelper.shared.saveUserId(response.userId)

        return response
    }

    func login() async throws -> AuthResponse {
        let deviceId = getDeviceId()
        let request = LoginRequest(deviceId: deviceId)

        let response: AuthResponse = try await self.request(
            endpoint: "/v1/auth/login",
            method: "POST",
            body: request
        )

        // Save tokens
        KeychainHelper.shared.saveAccessToken(response.accessToken)
        KeychainHelper.shared.saveRefreshToken(response.refreshToken)
        KeychainHelper.shared.saveUserId(response.userId)

        return response
    }

    func refreshToken() async throws -> AuthResponse {
        guard let refreshToken = KeychainHelper.shared.getRefreshToken() else {
            throw APIError.unauthorized
        }

        let request = RefreshTokenRequest(refreshToken: refreshToken)

        let response: AuthResponse = try await self.request(
            endpoint: "/v1/auth/refresh",
            method: "POST",
            body: request
        )

        // Update tokens
        KeychainHelper.shared.saveAccessToken(response.accessToken)

        return response
    }

    func logout() async throws {
        guard let refreshToken = KeychainHelper.shared.getRefreshToken() else {
            return
        }

        let request = RefreshTokenRequest(refreshToken: refreshToken)

        let _: EmptyResponse = try await self.request(
            endpoint: "/v1/auth/logout",
            method: "POST",
            body: request
        )

        // Clear all tokens
        KeychainHelper.shared.deleteAll()
    }

    // MARK: - DTC Codes

    func getDTCCodesCount() async throws -> Int {
        struct CountResponse: Decodable {
            let count: Int
        }
        let response: CountResponse = try await request(endpoint: "/v1/dtc-codes/count")
        return response.count
    }

    func getDTCCode(_ code: String) async throws -> DTCCodeResponse {
        return try await request(endpoint: "/v1/dtc-codes/\(code)")
    }

    func searchDTCCodes(
        query: String? = nil,
        system: String? = nil,
        category: String? = nil,
        severity: String? = nil,
        limit: Int = 10,
        offset: Int = 0
    ) async throws -> DTCSearchResponse {
        var components = URLComponents(string: "\(baseURL)/v1/dtc-codes/search")!
        var queryItems: [URLQueryItem] = []

        if let query = query {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }
        if let system = system {
            queryItems.append(URLQueryItem(name: "system", value: system))
        }
        if let category = category {
            queryItems.append(URLQueryItem(name: "category", value: category))
        }
        if let severity = severity {
            queryItems.append(URLQueryItem(name: "severity", value: severity))
        }
        queryItems.append(URLQueryItem(name: "limit", value: "\(limit)"))
        queryItems.append(URLQueryItem(name: "offset", value: "\(offset)"))

        components.queryItems = queryItems

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        let (data, _) = try await URLSession.shared.data(for: request)

        let result = try decoder.decode(APIResponse<DTCSearchResponse>.self, from: data)
        return result.data
    }

    func getDTCStats() async throws -> DTCStatsResponse {
        return try await request(endpoint: "/v1/dtc-codes/stats")
    }

    // MARK: - AI Analysis

    func analyzeDTC(
        code: String,
        description: String? = nil,
        stage: Int
    ) async throws -> AnalysisResponse {
        let request = AnalyzeRequest(
            dtcCode: code,
            dtcDescription: description,
            stage: stage
        )

        return try await self.request(
            endpoint: "/v1/dtc/analyze",
            method: "POST",
            body: request,
            requiresAuth: true
        )
    }

    func batchAnalyzeDTC(
        codes: [(code: String, description: String?)],
        stage: Int
    ) async throws -> BatchAnalysisResponse {
        let dtcList = codes.map { item in
            BatchAnalyzeRequest.DTCItem(
                code: item.code,
                description: item.description
            )
        }

        let request = BatchAnalyzeRequest(
            dtcList: dtcList,
            stage: stage
        )

        return try await self.request(
            endpoint: "/v1/dtc/batch-analyze",
            method: "POST",
            body: request,
            requiresAuth: true
        )
    }

    // MARK: - Usage

    func getUsageStats(period: String = "month") async throws -> UsageStatsResponse {
        return try await request(
            endpoint: "/v1/usage/stats?period=\(period)",
            requiresAuth: true
        )
    }

    func getSubscription() async throws -> Subscription {
        return try await request(
            endpoint: "/v1/usage/subscription",
            requiresAuth: true
        )
    }

    // MARK: - Helper

    private func getDeviceId() -> String {
        let key = "deviceId"

        if let existingId = UserDefaults.standard.string(forKey: key) {
            return existingId
        }

        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }
}

// MARK: - API Models

struct APIResponse<T: Decodable>: Decodable {
    let success: Bool
    let data: T
    let error: APIErrorResponse?
}

struct APIErrorResponse: Decodable {
    let code: String
    let message: String
}

struct EmptyResponse: Decodable {}

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case httpError(statusCode: Int)
    case serverError(message: String)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "잘못된 URL입니다."
        case .invalidResponse:
            return "서버 응답이 올바르지 않습니다."
        case .unauthorized:
            return "인증이 필요합니다. 다시 로그인해주세요."
        case .httpError(let statusCode):
            return "서버 오류 (코드: \(statusCode))"
        case .serverError(let message):
            return message
        case .decodingError(let error):
            return "데이터 처리 오류: \(error.localizedDescription)"
        }
    }
}
