//
//  OpenAIService.swift
//  mycar
//
//  Created by Jin Shin on 10/30/25.
//  OpenAI API 직접 호출 (스트리밍 지원)
//

import Foundation

class OpenAIService {
    static let shared = OpenAIService()

    // API 설정 (APIConfig에서 가져옴)
    private let apiKey = APIConfig.openAIKey
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private let model = APIConfig.openAIModel

    private init() {}

    // MARK: - Streaming Chat Completion

    /// OpenAI API 스트리밍 호출
    /// - Parameters:
    ///   - prompt: 사용자 프롬프트
    ///   - maxTokens: 최대 토큰 수 (짧은 답변용)
    ///   - onChunk: 스트리밍 청크 수신 시 호출
    ///   - onComplete: 완료 시 호출
    ///   - onError: 에러 시 호출
    func streamCompletion(
        prompt: String,
        maxTokens: Int = 100,
        temperature: Double = 0.3,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        guard let url = URL(string: baseURL) else {
            onError(OpenAIError.invalidURL)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        // Request body
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "You are a helpful automotive diagnostics assistant. Provide concise, accurate answers in Korean."],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": maxTokens,
            "temperature": temperature,
            "stream": true  // 스트리밍 활성화
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            onError(error)
            return
        }

        print("🚀 [OpenAI] Streaming request: \(prompt.prefix(50))...")

        // Create streaming delegate
        let delegate = OpenAIStreamDelegate(
            onChunk: onChunk,
            onComplete: onComplete,
            onError: onError
        )

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: request)
        task.resume()
    }

    // MARK: - Non-Streaming (Fallback)

    /// 비스트리밍 완료 (필요시 사용)
    func completion(
        prompt: String,
        maxTokens: Int = 100,
        temperature: Double = 0.3,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let url = URL(string: baseURL) else {
            completion(.failure(OpenAIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "You are a helpful automotive diagnostics assistant. Provide concise, accurate answers in Korean."],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": maxTokens,
            "temperature": temperature
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(OpenAIError.noData))
                }
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    DispatchQueue.main.async {
                        completion(.success(content))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(OpenAIError.parseError))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
}

// MARK: - Streaming Delegate

class OpenAIStreamDelegate: NSObject, URLSessionDataDelegate {
    private var buffer = Data()
    private let onChunk: (String) -> Void
    private let onComplete: () -> Void
    private let onError: (Error) -> Void

    init(
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.onChunk = onChunk
        self.onComplete = onComplete
        self.onError = onError
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)

        // Parse SSE stream
        if let text = String(data: buffer, encoding: .utf8) {
            let lines = text.components(separatedBy: "\n")

            // Process complete lines
            for line in lines.dropLast() {
                if line.hasPrefix("data: ") {
                    let jsonString = line.replacingOccurrences(of: "data: ", with: "")

                    // Skip [DONE] marker
                    if jsonString == "[DONE]" {
                        continue
                    }

                    // Parse JSON
                    if let jsonData = jsonString.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                       let choices = json["choices"] as? [[String: Any]],
                       let firstChoice = choices.first,
                       let delta = firstChoice["delta"] as? [String: Any],
                       let content = delta["content"] as? String {

                        DispatchQueue.main.async {
                            self.onChunk(content)
                        }
                    }
                }
            }

            // Keep incomplete line in buffer
            if let lastLine = lines.last {
                buffer = lastLine.data(using: .utf8) ?? Data()
            } else {
                buffer.removeAll()
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.onError(error)
            }
        } else {
            DispatchQueue.main.async {
                self.onComplete()
            }
        }
    }
}

// MARK: - Errors

enum OpenAIError: Error, LocalizedError {
    case invalidURL
    case noData
    case parseError
    case invalidAPIKey

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
        }
    }
}
