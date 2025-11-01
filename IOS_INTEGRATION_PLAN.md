# iOS 앱 서버 통합 실행 계획

> Maserati OBD iOS 앱을 서버 API와 통합하기 위한 단계별 가이드

**서버 정보**
- Base URL: `https://maserati.io.kr/obd/`
- 상태: ✅ 배포 완료 및 테스트 완료
- 데이터베이스: 11,430 DTC codes

---

## 📋 통합 체크리스트

### Phase 1: 기본 인프라 (1-2일)
- [ ] `APIService.swift` 생성
- [ ] 인증 모델 (`AuthResponse`, `User`) 생성
- [ ] 토큰 관리 (`KeychainHelper`) 구현
- [ ] 네트워크 에러 핸들링

### Phase 2: 인증 시스템 (1-2일)
- [ ] 디바이스 ID 생성 및 저장
- [ ] 자동 회원가입/로그인
- [ ] 토큰 갱신 로직
- [ ] 로그아웃 처리

### Phase 3: DTC 데이터베이스 통합 (1-2일)
- [ ] 로컬 JSON 제거 (선택 사항)
- [ ] 서버에서 DTC 조회
- [ ] 검색 기능 구현
- [ ] 오프라인 캐싱

### Phase 4: AI 분석 서버 연동 (2-3일)
- [ ] OpenAI 직접 호출 → 서버 API 호출로 변경
- [ ] Stage 1-3 모두 서버 API 사용
- [ ] 사용량 추적 UI
- [ ] 할당량 초과 처리

### Phase 5: 구독 시스템 (3-4일)
- [ ] 구독 상태 표시
- [ ] 티어 업그레이드 UI
- [ ] In-App Purchase 연동 (선택)
- [ ] 사용량 통계 화면

### Phase 6: 테스트 및 최적화 (2-3일)
- [ ] 단위 테스트
- [ ] 통합 테스트
- [ ] 오프라인 시나리오 테스트
- [ ] 성능 최적화

**예상 총 기간: 10-17일**

---

## 🔧 Phase 1: 기본 인프라 구축

### 1.1 APIService.swift 생성

`maseratiobd/Services/APIService.swift` 파일 생성:

```swift
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
```

### 1.2 인증 모델 생성

`maseratiobd/Models/AuthModels.swift` 파일 생성:

```swift
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
```

### 1.3 토큰 관리 (Keychain)

`maseratiobd/Helpers/KeychainHelper.swift` 파일 생성:

```swift
import Foundation
import Security

class KeychainHelper {
    static let shared = KeychainHelper()

    private let service = "com.maseratiobd.app"
    private let accessTokenKey = "accessToken"
    private let refreshTokenKey = "refreshToken"
    private let userIdKey = "userId"

    private init() {}

    // MARK: - Save

    func saveAccessToken(_ token: String) {
        save(key: accessTokenKey, value: token)
    }

    func saveRefreshToken(_ token: String) {
        save(key: refreshTokenKey, value: token)
    }

    func saveUserId(_ userId: String) {
        save(key: userIdKey, value: userId)
    }

    // MARK: - Get

    func getAccessToken() -> String? {
        get(key: accessTokenKey)
    }

    func getRefreshToken() -> String? {
        get(key: refreshTokenKey)
    }

    func getUserId() -> String? {
        get(key: userIdKey)
    }

    // MARK: - Delete

    func deleteAll() {
        delete(key: accessTokenKey)
        delete(key: refreshTokenKey)
        delete(key: userIdKey)
    }

    // MARK: - Private Methods

    private func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func get(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)

        guard let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}
```

---

## 🔐 Phase 2: 인증 시스템

### 2.1 APIService에 인증 메서드 추가

`APIService.swift`에 추가:

```swift
extension APIService {
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

struct EmptyResponse: Decodable {}
```

### 2.2 AuthenticationManager 생성

`maseratiobd/Services/AuthenticationManager.swift`:

```swift
import Foundation

@MainActor
class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()

    @Published var isAuthenticated = false
    @Published var currentUser: AuthResponse?
    @Published var subscription: Subscription?

    private init() {
        checkAuthentication()
    }

    func checkAuthentication() {
        isAuthenticated = KeychainHelper.shared.getAccessToken() != nil
    }

    func signIn() async throws {
        do {
            // Try login first
            let response = try await APIService.shared.login()
            currentUser = response
            subscription = response.subscription
            isAuthenticated = true
        } catch {
            // If login fails, register
            let response = try await APIService.shared.register()
            currentUser = response
            subscription = response.subscription
            isAuthenticated = true
        }
    }

    func signOut() async {
        do {
            try await APIService.shared.logout()
        } catch {
            print("Logout error: \(error)")
        }

        currentUser = nil
        subscription = nil
        isAuthenticated = false
    }

    func refreshSubscription() async throws {
        let subscription: Subscription = try await APIService.shared.request(
            endpoint: "/v1/usage/subscription",
            requiresAuth: true
        )
        self.subscription = subscription
    }
}
```

---

## 🗄️ Phase 3: DTC 데이터베이스 통합

### 3.1 DTC 모델 생성

`maseratiobd/Models/DTCModels.swift`:

```swift
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
```

### 3.2 APIService에 DTC 메서드 추가

```swift
extension APIService {
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
}
```

### 3.3 DTCDatabase.swift 수정

기존 `DTCDatabase.swift`를 서버 API를 사용하도록 수정:

```swift
import Foundation

class DTCDatabase {
    static let shared = DTCDatabase()

    // Cache for offline support
    private var codeCache: [String: DTCCodeResponse] = [:]

    private init() {}

    // Main method - Try server first, fallback to cache
    func getDescription(for code: String) async -> String {
        // Try server
        do {
            let response = try await APIService.shared.getDTCCode(code)
            // Cache the result
            codeCache[code] = response
            return response.description
        } catch {
            // Fallback to cache
            if let cached = codeCache[code] {
                return cached.description
            }

            // Last resort: generic description
            return "고장 코드 \(code)"
        }
    }

    func getSeverity(for code: String) async -> String {
        do {
            let response = try await APIService.shared.getDTCCode(code)
            codeCache[code] = response
            return response.severity
        } catch {
            if let cached = codeCache[code] {
                return cached.severity
            }
            return "Medium"
        }
    }

    func searchCodes(query: String, limit: Int = 10) async throws -> [DTCCodeResponse] {
        let response = try await APIService.shared.searchDTCCodes(
            query: query,
            limit: limit
        )
        return response.results
    }
}
```

---

## 🤖 Phase 4: AI 분석 서버 연동

### 4.1 AI 분석 모델

`maseratiobd/Models/AnalysisModels.swift`:

```swift
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
```

### 4.2 APIService에 AI 분석 메서드 추가

```swift
extension APIService {
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
}
```

### 4.3 OpenAIService.swift 수정

기존 `OpenAIService.swift`를 서버 API를 사용하도록 수정:

```swift
import Foundation

class OpenAIService {
    static let shared = OpenAIService()

    private init() {}

    // Stage 1: 15자 요약
    func getShortSummary(for code: String, description: String) async throws -> String {
        let response = try await APIService.shared.analyzeDTC(
            code: code,
            description: description,
            stage: 1
        )
        return response.analysis
    }

    // Stage 2: 150자 빠른 요약
    func getQuickSummary(for code: String, description: String) async throws -> String {
        let response = try await APIService.shared.analyzeDTC(
            code: code,
            description: description,
            stage: 2
        )
        return response.analysis
    }

    // Stage 3: 500자 상세 분석
    func getDetailedAnalysis(for code: String, description: String) async throws -> String {
        let response = try await APIService.shared.analyzeDTC(
            code: code,
            description: description,
            stage: 3
        )
        return response.analysis
    }

    // Batch analysis for multiple codes
    func analyzeBatch(
        codes: [(code: String, description: String)],
        stage: Int
    ) async throws -> [String: String] {
        let response = try await APIService.shared.batchAnalyzeDTC(
            codes: codes,
            stage: stage
        )

        var results: [String: String] = [:]
        for result in response.results {
            results[result.code] = result.analysis
        }
        return results
    }
}
```

---

## 📊 Phase 5: 구독 시스템 UI

### 5.1 사용량 표시 뷰

`maseratiobd/Views/UsageView.swift`:

```swift
import SwiftUI

struct UsageView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var usageStats: UsageStatsResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            List {
                // Subscription Tier
                Section("구독 정보") {
                    if let subscription = authManager.subscription {
                        HStack {
                            Text("현재 플랜")
                            Spacer()
                            Text(subscription.tier.uppercased())
                                .bold()
                                .foregroundColor(tierColor(subscription.tier))
                        }

                        // Scans remaining
                        HStack {
                            Text("남은 스캔 횟수")
                            Spacer()
                            if subscription.features.unlimitedScans {
                                Text("무제한")
                                    .foregroundColor(.green)
                            } else {
                                Text("\(subscription.scansLimit - subscription.scansUsed) / \(subscription.scansLimit)")
                                    .foregroundColor(scansColor(subscription))
                            }
                        }

                        // Reset date
                        if let resetAt = subscription.resetAt {
                            HStack {
                                Text("리셋 날짜")
                                Spacer()
                                Text(formatDate(resetAt))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Usage Statistics
                Section("이번 달 사용량") {
                    if let stats = usageStats {
                        LabeledContent("스캔 횟수", value: "\(stats.scansCount)")
                        LabeledContent("API 호출", value: "\(stats.apiCalls)")
                        LabeledContent("토큰 사용", value: "\(stats.tokensUsed)")
                        LabeledContent("비용", value: String(format: "$%.4f", stats.costUsd))
                        LabeledContent("캐시 적중률", value: String(format: "%.1f%%", stats.cachedRate * 100))
                    } else if isLoading {
                        ProgressView()
                    }
                }

                // Features by Tier
                Section("플랜별 기능") {
                    if let subscription = authManager.subscription {
                        FeatureRow(title: "무제한 스캔", enabled: subscription.features.unlimitedScans)
                        FeatureRow(title: "상세 분석 (Stage 3)", enabled: subscription.features.stage3Enabled)
                        FeatureRow(title: "PDF 내보내기", enabled: subscription.features.pdfExport)
                        FeatureRow(title: "다중 차량 관리", enabled: subscription.features.multipleVehicles)
                    }
                }

                // Upgrade Button
                if authManager.subscription?.tier == "free" {
                    Section {
                        Button(action: upgradeToPro) {
                            HStack {
                                Spacer()
                                Text("Pro로 업그레이드")
                                    .bold()
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("사용량 & 구독")
            .task {
                await loadData()
            }
            .refreshable {
                await loadData()
            }
            .alert("오류", isPresented: .constant(errorMessage != nil)) {
                Button("확인") { errorMessage = nil }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
        }
    }

    // MARK: - Methods

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Load subscription
            try await authManager.refreshSubscription()

            // Load usage stats
            usageStats = try await APIService.shared.getUsageStats()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func upgradeToPro() {
        // TODO: Implement In-App Purchase
        print("Upgrade to Pro")
    }

    private func tierColor(_ tier: String) -> Color {
        switch tier {
        case "free": return .gray
        case "pro": return .blue
        case "business": return .purple
        default: return .gray
        }
    }

    private func scansColor(_ subscription: Subscription) -> Color {
        let remaining = subscription.scansLimit - subscription.scansUsed
        if remaining == 0 { return .red }
        if remaining <= 1 { return .orange }
        return .green
    }

    private func formatDate(_ dateString: String) -> String {
        // TODO: Format date properly
        return dateString
    }
}

struct FeatureRow: View {
    let title: String
    let enabled: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: enabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(enabled ? .green : .gray)
        }
    }
}
```

---

## 🧪 Phase 6: 테스트

### 6.1 테스트 시나리오

1. **인증 테스트**
   - [ ] 최초 실행 시 자동 회원가입
   - [ ] 재실행 시 자동 로그인
   - [ ] 토큰 만료 시 자동 갱신
   - [ ] 로그아웃 후 재로그인

2. **DTC 조회 테스트**
   - [ ] 특정 코드 조회 (P0300)
   - [ ] 검색 기능 ("misfire")
   - [ ] 오프라인 캐싱
   - [ ] 존재하지 않는 코드 처리

3. **AI 분석 테스트**
   - [ ] Stage 1 분석 (15자)
   - [ ] Stage 2 분석 (150자)
   - [ ] Stage 3 분석 (500자)
   - [ ] 할당량 초과 시 에러 처리

4. **사용량 테스트**
   - [ ] 스캔 카운트 감소 확인
   - [ ] 사용량 통계 표시
   - [ ] 티어별 제한 확인

---

## 📝 다음 단계

### 즉시 시작 가능한 작업

1. **APIService.swift 생성 및 테스트**
   ```bash
   # 파일 생성
   touch maseratiobd/Services/APIService.swift

   # Xcode에서 프로젝트에 추가
   # File → Add Files to "maseratiobd"
   ```

2. **간단한 테스트 실행**
   ```swift
   // DiagnosticsView.swift에 테스트 버튼 추가
   Button("서버 테스트") {
       Task {
           do {
               let count = try await APIService.shared.getDTCCodesCount()
               print("DTC 코드 수: \(count)")
           } catch {
               print("오류: \(error)")
           }
       }
   }
   ```

3. **인증 플로우 구현**
   - AuthenticationManager 생성
   - 앱 시작 시 자동 인증
   - 토큰 저장 및 관리

---

## 🎯 예상 결과

### 통합 완료 후

1. **앱 크기 감소**
   - 로컬 JSON 제거 (약 5.5MB)
   - 서버에서 필요한 데이터만 다운로드

2. **비용 절감**
   - Redis 캐싱으로 80% 비용 절감
   - 중복 분석 제거

3. **사용자 경험 향상**
   - 최신 DTC 데이터 자동 업데이트
   - 다국어 지원 (EN, DE, IT, ES, FR)
   - 사용량 추적 및 통계

4. **수익화 준비**
   - 구독 티어 시스템
   - In-App Purchase 준비 완료
   - 사용량 기반 과금 가능

---

## ⚠️ 주의사항

1. **API 키 관리**
   - OpenAI API 키는 더 이상 iOS 앱에 포함하지 않음
   - 서버에서만 API 키 사용

2. **에러 핸들링**
   - 네트워크 오류 시 사용자 친화적 메시지
   - 오프라인 모드 지원
   - 자동 재시도 로직

3. **성능**
   - 로컬 캐싱으로 반복 요청 최소화
   - 배치 분석으로 API 호출 감소
   - 백그라운드 데이터 동기화

---

## 📚 참고 자료

- **서버 API 문서**: https://maserati.io.kr/obd/
- **GitHub**: https://github.com/deepseoulsoul/maseratiobd
- **README**: 서버 API 연동 섹션 참조

---

**작성일**: 2025-11-01
**버전**: 1.0
**상태**: 준비 완료 ✅
