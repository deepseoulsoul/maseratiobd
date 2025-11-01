//
//  OBDConnectionView.swift
//  mycar
//
//  Created by Jin Shin on 10/30/25.
//  Vgate iCar Pro (BLE 4.0) 연결 화면 - 심플 버전 (자동 연결)
//

import SwiftUI

struct OBDConnectionView: View {
    @ObservedObject var obdService = OBDService.shared
    @Environment(\.dismiss) var dismiss
    @State private var hasAttemptedAutoConnect = false

    // Vgate 기기만 필터링 (OBD 가능성 높은 기기)
    var vgateAdapters: [OBDAdapter] {
        obdService.discoveredAdapters
            .filter { $0.isLikelyOBD }
            .sorted { $0.rssi > $1.rssi }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppSpacing.xl) {
                        // Header
                        VStack(spacing: AppSpacing.md) {
                            Image(systemName: "sensor.tag.radiowaves.forward.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.accentGreen)

                            VStack(spacing: AppSpacing.xs) {
                                Text("OBD 어댑터 연결")
                                    .font(AppTypography.title)
                                    .foregroundColor(.primaryText)

                                Text("Vgate iCar Pro")
                                    .font(AppTypography.body)
                                    .foregroundColor(.secondaryText)
                            }
                        }
                        .padding(.top, AppSpacing.xl)

                        // Connection Status
                        OBDConnectionStatusCard(state: obdService.connectionState)

                        // Auto-Scan Status
                        if case .scanning = obdService.connectionState {
                            ScanningCard()
                        }

                        // Vgate Adapters (자동으로 하이라이트)
                        if !vgateAdapters.isEmpty {
                            VStack(alignment: .leading, spacing: AppSpacing.md) {
                                HStack {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.accentGreen)
                                    Text("Vgate 어댑터")
                                        .font(AppTypography.headline)
                                        .foregroundColor(.primaryText)
                                }
                                .padding(.horizontal, AppSpacing.md)

                                ForEach(vgateAdapters) { adapter in
                                    SimpleAdapterCard(adapter: adapter)
                                }
                            }
                        }

                        // Connected Adapter
                        if let adapter = obdService.connectedAdapter {
                            ConnectedCard(adapter: adapter)
                        }

                        // Simple Help
                        SimpleHelpCard()
                    }
                    .padding(.vertical, AppSpacing.md)
                }
            }
            .navigationTitle("OBD 연결")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("닫기") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if case .connected = obdService.connectionState {
                        Button("완료") {
                            dismiss()
                        }
                        .fontWeight(.semibold)
                        .foregroundColor(.accentGreen)
                    }
                }
            }
            .onAppear {
                // 자동으로 스캔 시작
                if case .disconnected = obdService.connectionState {
                    print("📱 [ConnectionView] Auto-starting scan...")
                    obdService.startScanning()
                }
            }
            .onChange(of: vgateAdapters) { oldValue, newValue in
                // 첫 번째 Vgate 어댑터 발견 시 자동 연결
                if !hasAttemptedAutoConnect, let firstAdapter = newValue.first {
                    hasAttemptedAutoConnect = true
                    print("🔌 [ConnectionView] Auto-connecting to \(firstAdapter.name)...")
                    obdService.connect(to: firstAdapter)
                }
            }
            .onChange(of: obdService.connectionState) { oldValue, newValue in
                // 연결 성공 시 자동으로 화면 닫기
                if case .connected = newValue {
                    print("✅ [ConnectionView] Connected! Auto-dismissing...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - OBD Connection Status Card

struct OBDConnectionStatusCard: View {
    let state: OBDConnectionState

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            // Status Icon
            Group {
                switch state {
                case .disconnected:
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .foregroundColor(.secondaryText)
                case .scanning:
                    ProgressView()
                        .tint(.accentGreen)
                case .connecting:
                    ProgressView()
                        .tint(.accentGreen)
                case .connected:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentGreen)
                case .error:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
            }
            .font(.system(size: 24))

            VStack(alignment: .leading, spacing: 4) {
                Text(state.displayText)
                    .font(AppTypography.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.primaryText)

                Text(statusDescription)
                    .font(AppTypography.caption)
                    .foregroundColor(.secondaryText)
            }

            Spacer()
        }
        .padding(AppSpacing.md)
        .background(statusColor)
        .cornerRadius(AppRadius.medium)
        .padding(.horizontal, AppSpacing.md)
    }

    private var statusDescription: String {
        switch state {
        case .disconnected:
            return "Vgate 어댑터를 찾는 중..."
        case .scanning:
            return "주변 기기 검색 중"
        case .connecting:
            return "어댑터 연결 중"
        case .connected:
            return "정상 연결됨"
        case .error:
            return "연결 실패. 다시 시도해주세요"
        }
    }

    private var statusColor: Color {
        switch state {
        case .connected:
            return Color.accentGreen.opacity(0.15)
        case .error:
            return Color.red.opacity(0.15)
        default:
            return Color.inputBackground
        }
    }
}

// MARK: - Scanning Card

struct ScanningCard: View {
    @State private var animationAmount = 1.0

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            ZStack {
                Circle()
                    .stroke(Color.accentGreen.opacity(0.2), lineWidth: 3)
                    .frame(width: 70, height: 70)

                Circle()
                    .stroke(Color.accentGreen, lineWidth: 3)
                    .frame(width: 70, height: 70)
                    .scaleEffect(animationAmount)
                    .opacity(2 - animationAmount)
                    .animation(
                        Animation.easeOut(duration: 1.5)
                            .repeatForever(autoreverses: false),
                        value: animationAmount
                    )

                Image(systemName: "sensor.tag.radiowaves.forward.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.accentGreen)
            }

            Text("Vgate 어댑터 검색 중...")
                .font(AppTypography.body)
                .foregroundColor(.primaryText)

            Text("자동으로 연결됩니다")
                .font(AppTypography.caption)
                .foregroundColor(.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xl)
        .background(Color.inputBackground)
        .cornerRadius(AppRadius.medium)
        .padding(.horizontal, AppSpacing.md)
        .onAppear {
            animationAmount = 1.5
        }
    }
}

// MARK: - Simple Adapter Card

struct SimpleAdapterCard: View {
    let adapter: OBDAdapter
    @ObservedObject var obdService = OBDService.shared

    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            obdService.connect(to: adapter)
        }) {
            HStack(spacing: AppSpacing.md) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.accentGreen.opacity(0.2))
                        .frame(width: 56, height: 56)

                    Image(systemName: "star.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.accentGreen)
                }

                // Info
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(adapter.name)
                            .font(AppTypography.body)
                            .fontWeight(.semibold)
                            .foregroundColor(.primaryText)

                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.accentGreen)
                    }

                    HStack(spacing: 8) {
                        // Signal Strength
                        HStack(spacing: 4) {
                            Image(systemName: adapter.signalStrength.icon)
                                .font(.system(size: 12))
                            Text(adapter.signalStrength.rawValue)
                                .font(AppTypography.caption)
                        }

                        Text("•")
                            .font(AppTypography.caption)

                        Text("추천")
                            .font(AppTypography.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.accentGreen)
                    }
                    .foregroundColor(.secondaryText)
                }

                Spacer()

                // Connect Button
                if case .connecting = obdService.connectionState {
                    ProgressView()
                        .tint(.accentGreen)
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.accentGreen)

                        Text("연결")
                            .font(.system(size: 11))
                            .fontWeight(.medium)
                            .foregroundColor(.accentGreen)
                    }
                }
            }
            .padding(AppSpacing.md)
            .background(Color.accentGreen.opacity(0.05))
            .cornerRadius(AppRadius.medium)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.medium)
                    .stroke(Color.accentGreen, lineWidth: 2)
            )
        }
        .padding(.horizontal, AppSpacing.md)
        .disabled({
            if case .connecting = obdService.connectionState {
                return true
            }
            return false
        }())
    }
}

// MARK: - Connected Card

struct ConnectedCard: View {
    let adapter: OBDAdapter
    @ObservedObject var obdService = OBDService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentGreen)
                Text("연결됨")
                    .font(AppTypography.headline)
                    .foregroundColor(.primaryText)
            }
            .padding(.horizontal, AppSpacing.md)

            VStack(spacing: AppSpacing.md) {
                // Adapter Info
                HStack(spacing: AppSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(Color.accentGreen.opacity(0.2))
                            .frame(width: 60, height: 60)

                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 28))
                            .foregroundColor(.accentGreen)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(adapter.name)
                            .font(AppTypography.body)
                            .fontWeight(.semibold)
                            .foregroundColor(.primaryText)

                        HStack(spacing: 8) {
                            Image(systemName: adapter.signalStrength.icon)
                                .font(.system(size: 12))
                            Text(adapter.signalStrength.rawValue)
                                .font(AppTypography.caption)
                        }
                        .foregroundColor(.secondaryText)
                    }

                    Spacer()
                }

                Divider()
                    .background(Color.dividerColor)

                // Disconnect Button
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    obdService.disconnect()
                }) {
                    HStack {
                        Image(systemName: "xmark.circle")
                        Text("연결 해제")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red)
                    .cornerRadius(AppRadius.small)
                }
            }
            .padding(AppSpacing.md)
            .background(Color.inputBackground)
            .cornerRadius(AppRadius.medium)
            .padding(.horizontal, AppSpacing.md)
        }
    }
}

// MARK: - Simple Help Card

struct SimpleHelpCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.accentGreen)
                Text("연결 방법")
                    .font(AppTypography.headline)
                    .foregroundColor(.primaryText)
            }

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HelpRow(number: "1", text: "차량 시동 ON 또는 ACC 모드")
                HelpRow(number: "2", text: "Vgate를 OBD-II 포트에 연결")
                HelpRow(number: "3", text: "어댑터 LED 확인 후 자동 연결")
            }

            Text("💡 검색이 안 되면 어댑터를 빼고 다시 꽂아보세요")
                .font(AppTypography.caption)
                .foregroundColor(.secondaryText)
                .padding(.top, 4)
        }
        .padding(AppSpacing.md)
        .background(Color.inputBackground)
        .cornerRadius(AppRadius.medium)
        .padding(.horizontal, AppSpacing.md)
    }
}

struct HelpRow: View {
    let number: String
    let text: String

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Text(number)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.accentGreen)
                .cornerRadius(12)

            Text(text)
                .font(AppTypography.body)
                .foregroundColor(.primaryText)
        }
    }
}

// MARK: - Preview

#Preview {
    OBDConnectionView()
}
