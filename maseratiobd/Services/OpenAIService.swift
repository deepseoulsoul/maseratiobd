//
//  OpenAIService.swift
//  maseratiobd
//
//  Created by Jin Shin on 10/30/25.
//  AI 분석 서비스 - Server API 통합
//

import Foundation

class OpenAIService {
    static let shared = OpenAIService()

    private init() {
        print("🤖 [OpenAI] Initializing with Server API")
    }

    // MARK: - Server API Methods

    /// Stage 1: 15자 이내 즉시 요약
    func getShortSummary(
        for code: String,
        description: String? = nil,
        onChunk: ((String) -> Void)? = nil
    ) async throws -> String {
        print("🔍 [OpenAI] Stage 1: Requesting short summary for \(code)")
        print("   Description provided: \(description != nil)")

        do {
            let response = try await APIService.shared.analyzeDTC(
                code: code,
                description: description,
                stage: 1
            )

            print("✅ [OpenAI] Stage 1 Success")
            print("   Analysis: \(response.analysis)")
            print("   Cached: \(response.cached)")
            print("   Tokens: \(response.tokensUsed)")
            print("   Cost: $\(String(format: "%.5f", response.cost))")
            print("   Scans remaining: \(response.usage?.scansRemaining ?? 0)")

            // Simulate streaming effect if callback provided
            if let onChunk = onChunk {
                await simulateStreaming(text: response.analysis, onChunk: onChunk)
            }

            return response.analysis
        } catch {
            print("❌ [OpenAI] Stage 1 Failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Stage 2: 150자 이내 빠른 요약 (원인, 증상, 해결)
    func getQuickSummary(
        for code: String,
        description: String? = nil,
        onChunk: ((String) -> Void)? = nil
    ) async throws -> String {
        print("🔍 [OpenAI] Stage 2: Requesting quick summary for \(code)")
        print("   Description provided: \(description != nil)")

        do {
            let response = try await APIService.shared.analyzeDTC(
                code: code,
                description: description,
                stage: 2
            )

            print("✅ [OpenAI] Stage 2 Success")
            print("   Analysis length: \(response.analysis.count) chars")
            print("   Cached: \(response.cached)")
            print("   Tokens: \(response.tokensUsed)")
            print("   Cost: $\(String(format: "%.5f", response.cost))")
            print("   Scans remaining: \(response.usage?.scansRemaining ?? 0)")

            // Simulate streaming effect if callback provided
            if let onChunk = onChunk {
                await simulateStreaming(text: response.analysis, onChunk: onChunk)
            }

            return response.analysis
        } catch {
            print("❌ [OpenAI] Stage 2 Failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Stage 3: 500자 이내 상세 분석 (마크다운)
    func getDetailedAnalysis(
        for code: String,
        description: String? = nil,
        onChunk: ((String) -> Void)? = nil
    ) async throws -> String {
        print("🔍 [OpenAI] Stage 3: Requesting detailed analysis for \(code)")
        print("   Description provided: \(description != nil)")

        do {
            let response = try await APIService.shared.analyzeDTC(
                code: code,
                description: description,
                stage: 3
            )

            print("✅ [OpenAI] Stage 3 Success")
            print("   Analysis length: \(response.analysis.count) chars")
            print("   Cached: \(response.cached)")
            print("   Tokens: \(response.tokensUsed)")
            print("   Cost: $\(String(format: "%.5f", response.cost))")
            print("   Scans remaining: \(response.usage?.scansRemaining ?? 0)")

            // Simulate streaming effect if callback provided
            if let onChunk = onChunk {
                await simulateStreaming(text: response.analysis, onChunk: onChunk)
            }

            return response.analysis
        } catch let error as APIError {
            print("❌ [OpenAI] Stage 3 Failed: \(error.localizedDescription)")

            // Check for quota exceeded
            if case .serverError(let message) = error {
                if message.contains("QUOTA_EXCEEDED") {
                    print("⚠️ [OpenAI] Quota exceeded - Stage 3 requires Pro tier")
                }
            }

            throw error
        } catch {
            print("❌ [OpenAI] Stage 3 Failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// 여러 DTC 배치 분석
    func analyzeBatch(
        codes: [(code: String, description: String?)],
        stage: Int
    ) async throws -> [String: String] {
        print("🔍 [OpenAI] Batch analysis: \(codes.count) codes, stage \(stage)")

        do {
            let response = try await APIService.shared.batchAnalyzeDTC(
                codes: codes,
                stage: stage
            )

            print("✅ [OpenAI] Batch analysis success")
            print("   Results: \(response.results.count)")
            print("   Total tokens: \(response.totalTokensUsed)")
            print("   Total cost: $\(String(format: "%.5f", response.totalCost))")
            print("   Tier: \(response.usage.tier)")

            var results: [String: String] = [:]
            for result in response.results {
                results[result.code] = result.analysis
                print("   • \(result.code): \(result.cached ? "Cached" : "Fresh")")
            }

            return results
        } catch {
            print("❌ [OpenAI] Batch analysis failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Helper Methods

    /// 스트리밍 효과 시뮬레이션 (서버는 스트리밍을 지원하지 않으므로)
    private func simulateStreaming(text: String, onChunk: @escaping (String) -> Void) async {
        print("⚡ [OpenAI] Simulating streaming effect...")

        let words = text.split(separator: " ")
        var accumulated = ""

        for word in words {
            accumulated += String(word) + " "

            await MainActor.run {
                onChunk(accumulated.trimmingCharacters(in: .whitespaces))
            }

            // Small delay for streaming effect (faster than actual API)
            try? await Task.sleep(nanoseconds: 30_000_000)  // 30ms
        }

        print("✅ [OpenAI] Streaming simulation complete")
    }

    // MARK: - Legacy Streaming Methods (Compatibility)

    /// 레거시 스트리밍 인터페이스 (서버 API로 변환)
    @available(*, deprecated, message: "Use async/await version instead")
    func streamCompletion(
        prompt: String,
        maxTokens: Int = 100,
        temperature: Double = 0.3,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        print("⚠️ [OpenAI] Using deprecated streaming method")

        Task {
            do {
                // Parse DTC code from prompt (simple heuristic)
                let dtcCode = extractDTCCode(from: prompt) ?? "UNKNOWN"
                let stage = determineStage(from: maxTokens)

                print("   Detected DTC: \(dtcCode), Stage: \(stage)")

                let response = try await APIService.shared.analyzeDTC(
                    code: dtcCode,
                    stage: stage
                )

                // Simulate streaming
                await simulateStreaming(text: response.analysis, onChunk: onChunk)

                await MainActor.run {
                    onComplete()
                }
            } catch {
                await MainActor.run {
                    onError(error)
                }
            }
        }
    }

    /// 레거시 비스트리밍 인터페이스
    @available(*, deprecated, message: "Use async/await version instead")
    func completion(
        prompt: String,
        maxTokens: Int = 100,
        temperature: Double = 0.3,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        print("⚠️ [OpenAI] Using deprecated completion method")

        Task {
            do {
                let dtcCode = extractDTCCode(from: prompt) ?? "UNKNOWN"
                let stage = determineStage(from: maxTokens)

                print("   Detected DTC: \(dtcCode), Stage: \(stage)")

                let response = try await APIService.shared.analyzeDTC(
                    code: dtcCode,
                    stage: stage
                )

                await MainActor.run {
                    completion(.success(response.analysis))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Private Helpers

    /// 프롬프트에서 DTC 코드 추출 (간단한 휴리스틱)
    private func extractDTCCode(from prompt: String) -> String? {
        // P0300, C0040 같은 패턴 찾기
        let pattern = "[PCBU]\\d{4}"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(
               in: prompt,
               range: NSRange(prompt.startIndex..., in: prompt)
           ) {
            if let range = Range(match.range, in: prompt) {
                return String(prompt[range])
            }
        }
        return nil
    }

    /// maxTokens로 stage 결정
    private func determineStage(from maxTokens: Int) -> Int {
        switch maxTokens {
        case 0..<100:
            return 1  // 15자 이내
        case 100..<400:
            return 2  // 150자 이내
        default:
            return 3  // 500자 이내
        }
    }

    // MARK: - Usage Statistics

    /// 사용량 통계 조회
    func getUsageStats() async throws -> UsageStatsResponse {
        print("📊 [OpenAI] Fetching usage statistics...")

        let stats = try await APIService.shared.getUsageStats()

        print("✅ [OpenAI] Usage stats:")
        print("   Scans: \(stats.scansCount) / \(stats.scansLimit)")
        print("   API calls: \(stats.apiCalls)")
        print("   Tokens used: \(stats.tokensUsed)")
        print("   Cost: $\(String(format: "%.4f", stats.costUsd))")
        print("   Cache rate: \(String(format: "%.1f%%", stats.cachedRate * 100))")

        return stats
    }

    /// 구독 정보 조회
    func getSubscription() async throws -> Subscription {
        print("📋 [OpenAI] Fetching subscription info...")

        let subscription = try await APIService.shared.getSubscription()

        print("✅ [OpenAI] Subscription:")
        print("   Tier: \(subscription.tier)")
        print("   Scans: \(subscription.scansUsed) / \(subscription.scansLimit)")
        print("   Reset at: \(subscription.resetAt)")

        return subscription
    }
}

// MARK: - Errors (Legacy Compatibility)

enum OpenAIError: Error, LocalizedError {
    case invalidURL
    case noData
    case parseError
    case invalidAPIKey
    case quotaExceeded

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "잘못된 API URL입니다"
        case .noData:
            return "응답 데이터가 없습니다"
        case .parseError:
            return "응답 파싱 실패"
        case .invalidAPIKey:
            return "유효하지 않은 API 키입니다"
        case .quotaExceeded:
            return "월간 사용량을 초과했습니다. Pro로 업그레이드하세요."
        }
    }
}
