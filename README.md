# 🚗 Maserati OBD - AI 기반 차량 진단 앱

> Bluetooth OBD-II 어댑터를 통한 실시간 차량 진단 및 AI 분석 iOS 앱

![iOS](https://img.shields.io/badge/iOS-18.1+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![SwiftUI](https://img.shields.io/badge/SwiftUI-18.1-green)
![License](https://img.shields.io/badge/License-MIT-yellow)

## 📱 주요 기능

### 🔍 OBD-II 진단
- **Bluetooth 자동 연결**: Vgate iCar Pro 어댑터 자동 검색 및 연결
- **실시간 DTC 스캔**: ELM327 프로토콜을 통한 고장 코드 읽기
- **심각도 분류**: Critical, High, Medium, Low 4단계 자동 분류

### 🤖 AI 분석 (3단계)
- **Stage 1 - 설명**: 15자 이내 즉시 요약
- **Stage 2 - AI 빠른요약**: 원인, 증상, 해결 방법 (자동 로딩)
- **Stage 3 - 상세분석**: 진단 절차, 예상 비용, 예방 방법 (마크다운)

### 📊 히스토리 & 분석
- **스캔 히스토리**: 무제한 스캔 기록 보관
- **스캔 간 비교**: 이전 스캔과 자동 비교 (해결됨/새로 발생/여전히 존재)
- **트렌드 분석**: 최근 7일 통계 및 트렌드 (개선 중/안정/악화 중)
- **필터링**: 심각도별, 문제 코드만, 정상 스캔만
- **상대 시간 표시**: "방금 전", "5분 전", "1시간 전"

### 🎨 디자인
- **다크 모드 지원**: 시스템 설정 자동 적용
- **심각도 색상 코드**: 🔴 심각, 🟠 높음, 🟡 보통, 🔵 낮음
- **실시간 스트리밍**: AI 응답 실시간 표시 (타이핑 효과)

## 🛠 기술 스택

### Frontend
```
Platform: iOS 18.1+
Language: Swift 5.9
Framework: SwiftUI
Architecture: MVVM
```

### Services
- **CoreBluetooth**: OBD 어댑터 BLE 통신
- **Maserati OBD Server**: AI 분석 및 DTC 데이터베이스 API
- **UserDefaults**: 로컬 데이터 저장

### Backend (Server)
- **Base URL**: https://maserati.io.kr/obd/
- **Database**: PostgreSQL (11,430 DTC codes)
- **Cache**: Redis (30-day TTL, 80% cost reduction)
- **API**: RESTful (인증, DTC 조회, AI 분석, 사용량 통계)

## 📦 프로젝트 구조

```
maseratiobd/
├── Components/           # 재사용 가능한 UI 컴포넌트
│   └── TypingIndicator.swift
├── Config/              # 설정 파일
│   └── APIConfig.swift
├── Design/              # 디자인 시스템
│   └── DesignSystem.swift
├── Services/            # 비즈니스 로직
│   ├── OBDService.swift          # OBD 통신
│   ├── DTCDatabase.swift         # DTC 데이터베이스
│   ├── DTCHistoryManager.swift   # 히스토리 관리
│   └── OpenAIService.swift       # AI 분석
├── Views/               # 화면
│   ├── DiagnosticsView.swift    # 메인 진단 화면
│   ├── DTCDetailView.swift      # DTC 상세 화면
│   └── OBDConnectionView.swift  # OBD 연결 화면
└── Resources/           # 데이터베이스 파일
    ├── dtc_database_complete.json
    ├── dtc_manufacturer_specific.json
    └── faults_database_complete.json
```

## 🚀 시작하기

### 1. 요구사항
- **Xcode**: 16.0+
- **iOS Deployment Target**: 18.1+
- **OpenAI API Key**: [발급받기](https://platform.openai.com/api-keys)

### 2. 설치

```bash
# 레포지토리 클론
git clone https://github.com/[YOUR_USERNAME]/maseratiobd.git
cd maseratiobd

# Xcode로 열기
open maseratiobd.xcodeproj
```

### 3. API 키 설정

**Option 1: 환경 변수 (권장)**
```bash
# Xcode Scheme에서 Environment Variables 추가
OPENAI_API_KEY=sk-proj-your-api-key-here
```

**Option 2: APIConfig.local.swift (개발용)**
```swift
// maseratiobd/Config/APIConfig.local.swift 생성
import Foundation

extension APIConfig {
    static let openAIKeyLocal = "sk-proj-your-api-key-here"
}
```

**Option 3: APIConfig.swift 직접 수정 (비추천)**
```swift
// APIConfig.swift
static let openAIKey = "sk-proj-your-api-key-here"
```

⚠️ **주의**: API 키를 Git에 커밋하지 마세요!

### 4. 빌드 및 실행

```bash
# 빌드
xcodebuild -scheme maseratiobd -destination 'platform=iOS Simulator,name=iPhone 16' build

# 또는 Xcode에서 ⌘R
```

## 📖 사용 방법

### 1. OBD 어댑터 연결
1. Vgate iCar Pro 어댑터를 차량 OBD-II 포트에 연결
2. 앱 실행 → 우측 상단 연결 아이콘 클릭
3. 자동으로 어댑터 검색 및 연결

### 2. DTC 스캔
1. **스캔** 버튼 클릭
2. 고장 코드 자동 읽기
3. AI 분석 자동 로딩 (Stage 1, 2)

### 3. 상세 분석 보기
1. DTC 카드 클릭
2. 3단계 AI 분석 확인
3. **상세분석** 버튼 클릭 (Stage 3)

### 4. 히스토리 확인
1. 히스토리 탭 전환
2. 필터 적용 (전체/심각/문제/정상)
3. 트렌드 분석 버튼 클릭

## 🌐 서버 API 연동

### API 서버
- **Base URL**: `https://maserati.io.kr/obd/`
- **문서**: API 엔드포인트 및 사용 예제

### 주요 API 엔드포인트

#### 1. 인증
```swift
// 회원가입
POST /v1/auth/register
{
  "device_id": "unique-device-id",
  "platform": "ios",
  "app_version": "1.0.0"
}

// 로그인
POST /v1/auth/login
{
  "device_id": "unique-device-id"
}
```

#### 2. DTC 코드 조회
```swift
// 코드 총 개수
GET /v1/dtc-codes/count
// Response: { "count": 11430 }

// 특정 코드 조회
GET /v1/dtc-codes/P0300
// Response: { "code": "P0300", "description": "...", "severity": "Critical" }

// 검색
GET /v1/dtc-codes/search?q=misfire&limit=10

// 통계
GET /v1/dtc-codes/stats
```

#### 3. AI 분석 (인증 필요)
```swift
POST /v1/dtc/analyze
Headers: { "Authorization": "Bearer <access_token>" }
{
  "dtc_code": "P0300",
  "stage": 1,  // 1: 15자, 2: 150자, 3: 500자 (마크다운)
  "language": "ko"
}

// Note: dtc_description은 선택 사항 (서버가 자동으로 DB에서 조회)
```

#### 4. 사용량 통계
```swift
// 월간 사용량
GET /v1/usage/stats?period=month
Headers: { "Authorization": "Bearer <access_token>" }

// 구독 정보
GET /v1/usage/subscription
Headers: { "Authorization": "Bearer <access_token>" }
```

### 구독 티어

| 티어 | 월 비용 | 스캔 제한 | Stage 3 | PDF | 다중 차량 |
|------|---------|-----------|---------|-----|-----------|
| Free | $0 | 3회/월 | ❌ | ❌ | ❌ |
| Pro | $4.99 | 무제한 | ✅ | ✅ | ❌ |
| Business | $19.99 | 무제한 | ✅ | ✅ | ✅ (최대 5대) |

### iOS 앱 통합 예제

```swift
// APIService.swift
class APIService {
    let baseURL = "https://maserati.io.kr/obd"

    // 1. 회원가입
    func register(deviceId: String) async throws -> AuthResponse {
        let url = URL(string: "\(baseURL)/v1/auth/register")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = [
            "device_id": deviceId,
            "platform": "ios",
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }

    // 2. AI 분석
    func analyzeDTC(code: String, stage: Int, token: String) async throws -> AnalysisResponse {
        let url = URL(string: "\(baseURL)/v1/dtc/analyze")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body = [
            "dtc_code": code,
            "stage": stage,
            "language": "ko"
        ] as [String : Any]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(AnalysisResponse.self, from: data)
    }

    // 3. DTC 코드 조회
    func getDTCCode(_ code: String) async throws -> DTCCodeResponse {
        let url = URL(string: "\(baseURL)/v1/dtc-codes/\(code)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(DTCCodeResponse.self, from: data)
    }
}

// Response Models
struct AuthResponse: Codable {
    let user_id: String
    let access_token: String
    let refresh_token: String
    let tier: String
}

struct AnalysisResponse: Codable {
    let dtc_code: String
    let stage: Int
    let analysis: String
    let cached: Bool
    let tokens_used: Int
    let cost: Double
}

struct DTCCodeResponse: Codable {
    let code: String
    let description: String
    let severity: String
    let category: String
}
```

### 테스트 결과

✅ **모든 API 테스트 완료** (2025-11-01)

| 항목 | 상태 | 비고 |
|------|------|------|
| Health Check | ✅ | 서버 정상 작동 |
| DTC 코드 조회 | ✅ | 11,430개 코드 |
| 검색 기능 | ✅ | 다국어 지원 |
| 회원가입/로그인 | ✅ | JWT 인증 |
| AI Stage 1 | ✅ | 15자 요약 |
| AI Stage 2 | ✅ | 150자 상세 |
| AI Stage 3 | ✅ | 500자 마크다운 |
| 사용량 통계 | ✅ | 실시간 추적 |

## 🧪 목업 데이터

개발 및 테스트를 위한 샘플 데이터:

### 현재 탭
- 6개 샘플 DTC 코드 (P0300, C0040, P0420, P0133, P0442, B1657)

### 히스토리 탭
- 히스토리 탭 → 좌측 상단 ✨ 버튼 클릭
- 7개 샘플 히스토리 생성 (다양한 시간대)

## 💰 비용 (GPT-4o-mini)

```
모델: gpt-4o-mini
입력: $0.15 / 1M tokens
출력: $0.60 / 1M tokens

DTC당 비용:
- Stage 1 (설명): ~$0.00004 (0.004¢)
- Stage 2 (빠른요약): ~$0.00018 (0.018¢)
- Stage 3 (상세분석): ~$0.00041 (0.041¢)

예상 월간 비용 (1,000 사용자):
- 캐싱 없이: $32.4/월
- 캐싱 적용 (80%): $6.5/월 ✅
```

## 🔐 보안

### API 키 관리
- ✅ 환경 변수 사용
- ✅ .gitignore에 추가
- ✅ APIConfig.local.swift 분리
- ⚠️ 절대 Git에 커밋 금지

### 데이터 보호
- 로컬 저장 (UserDefaults)
- HTTPS 통신 (OpenAI API)
- Bluetooth 암호화 (BLE)

## 📊 심각도 분류

### 수동 매핑 (53개 코드)
```swift
Critical (23개): 안전 직결
- 엔진 실화 (P0300~P0306)
- ABS/브레이크 (C0035, C0040, C0045, C0050)
- 에어백 (B0001~B0004)
- 조향 장치 (C0041, C0042)

High (18개): 성능 문제
- 촉매 변환기 (P0420, P0430)
- 산소 센서 (P0131~P0154)
- 점화 코일 (P0351~P0354)

Medium (12개): 편의 기능
- EVAP 시스템 (P0440~P0443)
- 에어컨 (B1479, B1480)
- 도어락/창문 (B1650~B1652)

Low: 기타
```

## 🗺️ 로드맵

### Phase 1: MVP ✅ (완료)
- [x] OBD 연결
- [x] DTC 스캔
- [x] AI 분석 (3단계)
- [x] 히스토리
- [x] 트렌드 분석

### Phase 2: 서버 연동 ✅ (완료)
- [x] 백엔드 API 구축 (https://maserati.io.kr/obd/)
- [x] DTC 데이터베이스 마이그레이션 (11,430 codes)
- [x] Redis 캐싱 시스템 (80% 비용 절감)
- [x] 사용자 인증 (JWT)
- [x] 구독 모델 (Free/Pro/Business)
- [x] AI 분석 API (Stage 1-3)
- [ ] iOS 앱 통합 (진행 중)

### Phase 3: 고급 기능
- [ ] PDF 리포트
- [ ] 푸시 알림
- [ ] 다중 차량 관리
- [ ] 정비소 연동

## 🤝 기여

기여는 언제나 환영합니다!

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 라이선스

MIT License - 자세한 내용은 [LICENSE](LICENSE) 파일 참조

## 📞 연락처

Project Link: [https://github.com/[YOUR_USERNAME]/maseratiobd](https://github.com/[YOUR_USERNAME]/maseratiobd)

## 🙏 감사의 말

- [OpenAI GPT-4o-mini](https://openai.com/) - AI 분석 엔진
- [AlfaOBD](https://www.alfaobd.com/) - DTC 데이터베이스
- [Vgate iCar Pro](https://www.vgate.com/) - OBD-II 어댑터

---

**Made with ❤️ for car enthusiasts**
