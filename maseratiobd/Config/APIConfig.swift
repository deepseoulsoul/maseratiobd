//
//  APIConfig.swift
//  mycar
//
//  Created by Jin Shin on 10/30/25.
//  API 설정 (OpenAI API Key 등)
//

import Foundation

struct APIConfig {
    // OpenAI API Key
    // 🔑 실제 OpenAI API 키는 환경 변수 또는 APIConfig.local.swift에서 관리
    // https://platform.openai.com/api-keys 에서 발급
    static let openAIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "YOUR_API_KEY_HERE"

    // Maserati Backend API (기존 챗봇용)
    static let maseratiBaseURL = "https://maserati.io.kr"

    // OpenAI 설정
    static let openAIModel = "gpt-4o-mini"  // 빠르고 저렴한 모델
    static let openAIMaxTokensBrief = 30    // 짧은 요약 (Stage 1)
    static let openAIMaxTokensBasic = 250   // 기본 상세 설명 (Stage 2 - 자동 로딩)
    static let openAIMaxTokensVerbose = 600 // 매우 상세한 설명 (Stage 3 - 버튼 클릭)
    static let openAITemperature = 0.3  // 일관된 답변
}
