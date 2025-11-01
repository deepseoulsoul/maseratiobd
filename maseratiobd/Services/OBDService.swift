//
//  OBDService.swift
//  mycar
//
//  Created by Jin Shin on 10/30/25.
//  CoreBluetooth를 사용한 Vgate iCar Pro (BLE 4.0) 연결 및 OBD-II 통신
//

import Foundation
import CoreBluetooth
import Combine

// MARK: - OBD Adapter Model

struct OBDAdapter: Identifiable, Equatable {
    let id: UUID
    let peripheral: CBPeripheral
    let name: String
    let rssi: Int  // 신호 강도 (dBm)
    let serviceUUIDs: [String]  // 광고된 서비스 UUID
    let manufacturerData: String?  // 제조사 데이터 (16진수)
    let isConnectable: Bool
    let localName: String?  // 광고 데이터의 로컬 이름

    var signalStrength: SignalStrength {
        switch rssi {
        case -50...0: return .excellent
        case -60..<(-50): return .good
        case -70..<(-60): return .fair
        case -80..<(-70): return .weak
        default: return .poor
        }
    }

    // OBD 어댑터일 가능성
    var isLikelyOBD: Bool {
        // FFE0, FFE1 서비스가 있거나 이름에 OBD 관련 키워드가 있으면 높은 가능성
        let hasOBDService = serviceUUIDs.contains(where: {
            $0.uppercased().contains("FFE0") || $0.uppercased().contains("FFE1")
        })

        let nameKeywords = ["vgate", "icar", "obd", "elm327", "v-link", "veepeak", "konnwei"]
        let hasOBDName = nameKeywords.contains(where: {
            name.lowercased().contains($0) || (localName?.lowercased().contains($0) ?? false)
        })

        return hasOBDService || hasOBDName
    }

    enum SignalStrength: String {
        case excellent = "최고"
        case good = "좋음"
        case fair = "보통"
        case weak = "약함"
        case poor = "매우 약함"

        var icon: String {
            switch self {
            case .excellent, .good: return "wifi"
            case .fair: return "wifi.exclamationmark"
            case .weak, .poor: return "wifi.slash"
            }
        }
    }

    static func == (lhs: OBDAdapter, rhs: OBDAdapter) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Connection State

enum OBDConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting
    case connected
    case error(String)

    var displayText: String {
        switch self {
        case .disconnected: return "연결 안됨"
        case .scanning: return "검색 중..."
        case .connecting: return "연결 중..."
        case .connected: return "연결됨"
        case .error(let message): return "에러: \(message)"
        }
    }

    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
}

// MARK: - OBD Service

class OBDService: NSObject, ObservableObject {
    static let shared = OBDService()

    // Published properties
    @Published var connectionState: OBDConnectionState = .disconnected
    @Published var discoveredAdapters: [OBDAdapter] = []
    @Published var connectedAdapter: OBDAdapter?

    // Auto-connect settings
    @Published var autoConnectEnabled: Bool = true  // 자동 연결 활성화
    private var hasAttemptedAutoConnect: Bool = false  // 자동 연결 시도 여부

    // Debug logging
    private let enableDebugLogging: Bool = false  // true로 설정하면 상세 로그 표시
    private let enableVerboseLogging: Bool = false  // 매우 상세한 로그 (CAN 트래픽 등)

    // CoreBluetooth
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?

    // Connection timeout
    private var connectionTimer: Timer?
    private let connectionTimeout: TimeInterval = 15.0  // 15초 타임아웃

    // Response handling
    private var responseBuffer = ""
    private var responseContinuation: CheckedContinuation<String, Error>?

    // Initialization flag
    private var isInitialized: Bool = false

    // UUIDs for Vgate iCar Pro (BLE 4.0)
    // Vgate uses standard BLE UART service
    private let serviceUUID = CBUUID(string: "FFE0")  // BLE UART Service
    private let writeCharacteristicUUID = CBUUID(string: "FFE1")  // TX Characteristic
    private let notifyCharacteristicUUID = CBUUID(string: "FFE1")  // RX Characteristic (same as TX for iCar)

    private override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Public Methods

    /// 어댑터 스캔 시작
    func startScanning() {
        if enableDebugLogging {
            print("🔍 [OBD] Starting BLE scan...")
            print("🔍 [OBD] Auto-connect enabled: \(autoConnectEnabled)")
        } else {
            print("🔍 [OBD] 검색 시작...")
        }
        discoveredAdapters.removeAll()
        hasAttemptedAutoConnect = false  // 새 스캔 시작 시 자동 연결 플래그 리셋
        connectionState = .scanning

        if centralManager.state == .poweredOn {
            // 모든 BLE 기기 스캔 (디버깅용 - 서비스 필터 제거)
            centralManager.scanForPeripherals(
                withServices: nil,  // nil = 모든 서비스
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        } else {
            connectionState = .error("Bluetooth가 꺼져 있습니다")
        }
    }

    /// 스캔 중지
    func stopScanning() {
        print("⏹️ [OBD] Stopping BLE scan...")
        centralManager.stopScan()
        if connectionState == .scanning {
            connectionState = .disconnected
        }
    }

    /// 어댑터 연결
    func connect(to adapter: OBDAdapter) {
        print("🔗 [OBD] Connecting to \(adapter.name)...")
        stopScanning()
        connectionState = .connecting
        connectedPeripheral = adapter.peripheral

        // 연결 타임아웃 타이머 시작
        startConnectionTimer()

        centralManager.connect(adapter.peripheral, options: nil)
    }

    /// 연결 해제
    func disconnect() {
        print("🔌 [OBD] Disconnecting...")
        stopConnectionTimer()

        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        connectedAdapter = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        isInitialized = false  // 초기화 플래그 리셋
        connectionState = .disconnected
    }

    // MARK: - Connection Timer

    private func startConnectionTimer() {
        stopConnectionTimer()
        print("⏱️ [OBD] Starting connection timeout timer (\(connectionTimeout)s)")

        connectionTimer = Timer.scheduledTimer(withTimeInterval: connectionTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            print("⏰ [OBD] Connection timeout!")

            if self.connectionState == .connecting {
                self.disconnect()
                self.connectionState = .error("연결 시간 초과. 서비스/특성을 찾을 수 없습니다.\n로그를 확인하여 지원되는 UUID를 확인하세요.")
            }
        }
    }

    private func stopConnectionTimer() {
        connectionTimer?.invalidate()
        connectionTimer = nil
    }

    /// OBD 명령어 전송
    func sendCommand(_ command: String) async throws -> String {
        guard let characteristic = writeCharacteristic,
              let peripheral = connectedPeripheral,
              connectionState.isConnected else {
            throw OBDError.notConnected
        }

        let commandWithCR = command + "\r"
        guard let data = commandWithCR.data(using: .utf8) else {
            throw OBDError.invalidCommand
        }

        if enableDebugLogging {
            print("📤 [OBD] Sending: \(command)")
        }
        responseBuffer = ""

        return try await withCheckedThrowingContinuation { continuation in
            self.responseContinuation = continuation
            peripheral.writeValue(data, for: characteristic, type: .withResponse)

            // 타임아웃 (5초)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                if self?.responseContinuation != nil {
                    self?.responseContinuation?.resume(throwing: OBDError.timeout)
                    self?.responseContinuation = nil
                }
            }
        }
    }

    /// ELM327 초기화 (Reference app 방식)
    func initializeELM327() async throws {
        print("🔧 [OBD] Initializing ELM327...")

        // Reset
        _ = try await sendCommand("ATZ")
        try await Task.sleep(nanoseconds: 2_500_000_000)  // 2.5초 대기 (Reference app 방식)

        // Echo off
        _ = try await sendCommand("ATE0")

        // Auto protocol (let ELM327 detect the best protocol)
        _ = try await sendCommand("ATSP0")

        // Get adapter info
        let info = try await sendCommand("ATI")
        print("📟 [OBD] Adapter info: \(info)")

        print("✅ [OBD] ELM327 initialized")
    }

    /// DTC 읽기 (Mode 03)
    func readDTCs() async throws -> [String] {
        if enableDebugLogging {
            print("📋 [OBD] Reading DTCs...")
        }

        let response = try await sendCommand("03")
        if enableDebugLogging {
            print("📥 [OBD] DTC Response: '\(response)'")
            print("📏 [OBD] Response length: \(response.count) characters")
        }

        // 빈 응답 또는 NO DATA 체크
        if response.isEmpty {
            if enableDebugLogging {
                print("⚠️ [OBD] Empty response received")
            }
            return []
        }

        if response.uppercased().contains("NO DATA") {
            print("ℹ️ [OBD] DTC 없음")
            return []
        }

        if response.uppercased().contains("ERROR") {
            print("❌ [OBD] 에러 응답: \(response)")
            throw OBDError.invalidCommand
        }

        // 응답 파싱 (예: "43 01 33 00 00 00 00")
        let dtcs = parseDTCResponse(response)
        print("✅ [OBD] \(dtcs.count)개 DTC 발견: \(dtcs)")
        return dtcs
    }

    /// DTC 삭제 (Mode 04)
    func clearDTCs() async throws {
        print("🗑️ [OBD] Clearing DTCs...")
        _ = try await sendCommand("04")
        print("✅ [OBD] DTCs cleared")
    }

    /// PID 읽기 (Mode 01)
    func readPID(_ pid: String) async throws -> String {
        let command = "01" + pid
        return try await sendCommand(command)
    }

    // MARK: - Private Methods

    private func parseDTCResponse(_ response: String) -> [String] {
        // "43 01 33 00 00 00 00" → ["P0133"]
        if enableDebugLogging {
            print("🔍 [OBD] Parsing DTC response: '\(response)'")
        }
        var dtcs: [String] = []

        // Clean response - remove common prefixes and whitespace
        let cleaned = response
            .replacingOccurrences(of: "43", with: "")  // Remove mode response (0x43 = response to 0x03)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if enableDebugLogging {
            print("🧹 [OBD] Cleaned response: '\(cleaned)'")
        }

        let bytes = cleaned
            .split(separator: " ")
            .compactMap { UInt8($0, radix: 16) }

        if enableDebugLogging {
            print("📊 [OBD] Parsed bytes: \(bytes.map { String(format: "0x%02X", $0) })")
        }

        // Skip first byte (number of DTCs)
        guard bytes.count > 1 else {
            if enableDebugLogging {
                print("⚠️ [OBD] Not enough bytes to parse DTCs (count: \(bytes.count))")
            }
            return dtcs
        }

        let numDTCs = bytes[0]
        if enableDebugLogging {
            print("📝 [OBD] Number of DTCs reported: \(numDTCs)")
        }

        var i = 1
        while i < bytes.count - 1 {
            let byte1 = bytes[i]
            let byte2 = bytes[i + 1]

            if enableDebugLogging {
                print("🔢 [OBD] Processing bytes [\(i)]: 0x\(String(format: "%02X", byte1)) 0x\(String(format: "%02X", byte2))")
            }

            // Combine two bytes
            let code = (UInt16(byte1) << 8) | UInt16(byte2)

            // Check if not 0000 (no DTC)
            if code != 0x0000 {
                let dtc = parseDTCCode(code)
                if enableDebugLogging {
                    print("✅ [OBD] Found DTC: \(dtc) (raw: 0x\(String(format: "%04X", code)))")
                }
                dtcs.append(dtc)
            } else if enableDebugLogging {
                print("⏭️  [OBD] Skipping 0x0000 (no DTC)")
            }

            i += 2
        }

        if enableDebugLogging {
            print("📋 [OBD] Total DTCs parsed: \(dtcs.count)")
        }
        return dtcs
    }

    private func parseDTCCode(_ code: UInt16) -> String {
        // Parse SAE J1979 DTC format
        let systemBits = (code >> 14) & 0b11
        let typeBits = (code >> 12) & 0b11
        let codeNum = code & 0xFFF

        let system: String
        switch systemBits {
        case 0: system = "P"
        case 1: system = "C"
        case 2: system = "B"
        case 3: system = "U"
        default: system = "?"
        }

        return String(format: "%@%d%03X", system, typeBits, codeNum)
    }
}

// MARK: - CBCentralManagerDelegate

extension OBDService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let stateNames: [CBManagerState: String] = [
            .unknown: "알 수 없음 (unknown)",
            .resetting: "재설정 중 (resetting)",
            .unsupported: "지원 안됨 (unsupported)",
            .unauthorized: "권한 없음 (unauthorized)",
            .poweredOff: "꺼짐 (poweredOff)",
            .poweredOn: "켜짐 (poweredOn)"
        ]

        let stateName = stateNames[central.state] ?? "알 수 없는 상태"
        if enableDebugLogging {
            print("📡 [OBD] Bluetooth 상태: \(stateName)")
        }

        switch central.state {
        case .poweredOn:
            // 스캔 중이었다면 자동으로 재개
            if connectionState == .scanning {
                startScanning()
            } else if case .error = connectionState {
                connectionState = .disconnected
            }
        case .poweredOff:
            print("⚠️ [OBD] Bluetooth 꺼짐")
            connectionState = .error("Bluetooth가 꺼져 있습니다")
        case .unauthorized:
            print("⚠️ [OBD] Bluetooth 권한 필요")
            connectionState = .error("Bluetooth 권한이 필요합니다. 설정 > 개인정보 보호 > Bluetooth에서 권한을 허용해주세요.")
        case .unsupported:
            print("❌ [OBD] Bluetooth 미지원")
            connectionState = .error("이 기기는 Bluetooth를 지원하지 않습니다")
        case .resetting:
            connectionState = .disconnected
        case .unknown:
            connectionState = .disconnected
        @unknown default:
            connectionState = .disconnected
        }
    }

    func centralManager(_ central: CBCentralManager,
                       didDiscover peripheral: CBPeripheral,
                       advertisementData: [String: Any],
                       rssi RSSI: NSNumber) {
        let rssiValue = RSSI.intValue

        // 광고 데이터에서 이름 추출 (여러 소스 시도)
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let peripheralName = peripheral.name
        let displayName = localName ?? peripheralName ?? "알 수 없는 장치"

        // 서비스 UUID 추출
        let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]
        let serviceUUIDStrings = serviceUUIDs?.map { $0.uuidString }.joined(separator: ", ") ?? "없음"

        // Manufacturer Data 추출 (16진수로 표시)
        let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let manufacturerHex = manufacturerData?.map { String(format: "%02X", $0) }.joined(separator: " ") ?? "없음"

        // TX Power Level
        let txPower = advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber
        let txPowerString = txPower != nil ? "\(txPower!) dBm" : "없음"

        // Connectable 여부
        let isConnectable = advertisementData[CBAdvertisementDataIsConnectable] as? Bool ?? false

        // Service Data 추출
        let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]
        var serviceDataString = "없음"
        if let serviceData = serviceData, !serviceData.isEmpty {
            serviceDataString = serviceData.map { uuid, data in
                let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
                return "\(uuid.uuidString): \(hex)"
            }.joined(separator: ", ")
        }

        // 디버깅 정보 출력 (간소화)
        if enableDebugLogging {
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("🔍 [OBD] BLE 기기 발견")
            print("📱 표시 이름: \(displayName)")
            print("   • Peripheral Name: \(peripheralName ?? "없음")")
            print("   • Local Name: \(localName ?? "없음")")
            print("📡 UUID: \(peripheral.identifier.uuidString)")
            print("📶 RSSI: \(rssiValue) dBm (\(getSignalStrengthDescription(rssiValue)))")
            print("🔌 연결 가능: \(isConnectable ? "예" : "아니오")")
            print("⚙️  서비스 UUID: \(serviceUUIDStrings)")
            print("🏭 제조사 데이터: \(manufacturerHex)")
            print("📊 TX Power: \(txPowerString)")
            print("💾 서비스 데이터: \(serviceDataString)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        } else {
            print("🔍 [OBD] 발견: \(displayName) | RSSI: \(rssiValue)dBm | 연결가능: \(isConnectable ? "예" : "아니오")")
        }

        let adapter = OBDAdapter(
            id: UUID(),
            peripheral: peripheral,
            name: displayName,
            rssi: rssiValue,
            serviceUUIDs: serviceUUIDs?.map { $0.uuidString } ?? [],
            manufacturerData: manufacturerHex != "없음" ? manufacturerHex : nil,
            isConnectable: isConnectable,
            localName: localName
        )

        // 중복 체크
        if !discoveredAdapters.contains(where: { $0.peripheral == peripheral }) {
            discoveredAdapters.append(adapter)

            // OBD 가능성 표시
            let obdIndicator = adapter.isLikelyOBD ? "⭐️ [OBD 가능성 높음]" : ""
            print("✅ [OBD] 목록에 추가: \(displayName) \(obdIndicator)\n")

            // IOS-Vlink 자동 연결 (활성화되어 있고, 아직 시도하지 않았으며, 연결 가능한 경우)
            if autoConnectEnabled && !hasAttemptedAutoConnect && adapter.isConnectable {
                let isIOSVlink = displayName.uppercased().contains("IOS-VLINK") ||
                                displayName.uppercased().contains("V-LINK") ||
                                (localName?.uppercased().contains("IOS-VLINK") ?? false)

                if isIOSVlink {
                    print("🎯 [OBD] IOS-Vlink 기기 발견! 자동 연결 시작...")
                    hasAttemptedAutoConnect = true

                    // 약간의 딜레이 후 연결 (안정성을 위해)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.connect(to: adapter)
                    }
                }
            }
        }
    }

    private func getSignalStrengthDescription(_ rssi: Int) -> String {
        switch rssi {
        case -50...0: return "매우 강함"
        case -60..<(-50): return "강함"
        case -70..<(-60): return "보통"
        case -80..<(-70): return "약함"
        default: return "매우 약함"
        }
    }

    func centralManager(_ central: CBCentralManager,
                       didConnect peripheral: CBPeripheral) {
        print("✅ [OBD] Connected to \(peripheral.name ?? "Unknown")")
        print("📱 [OBD] Peripheral UUID: \(peripheral.identifier.uuidString)")

        peripheral.delegate = self

        // 모든 서비스를 발견하도록 변경 (디버깅용)
        print("🔍 [OBD] Discovering all services...")
        peripheral.discoverServices(nil)  // nil = 모든 서비스 검색
    }

    func centralManager(_ central: CBCentralManager,
                       didFailToConnect peripheral: CBPeripheral,
                       error: Error?) {
        print("❌ [OBD] Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
        connectionState = .error("연결 실패")
    }

    func centralManager(_ central: CBCentralManager,
                       didDisconnectPeripheral peripheral: CBPeripheral,
                       error: Error?) {
        print("🔌 [OBD] Disconnected from \(peripheral.name ?? "Unknown")")
        connectionState = .disconnected
        connectedAdapter = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
    }
}

// MARK: - CBPeripheralDelegate

extension OBDService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("❌ [OBD] Service discovery error: \(error.localizedDescription)")
            connectionState = .error("서비스 검색 실패: \(error.localizedDescription)")
            return
        }

        guard let services = peripheral.services else {
            print("❌ [OBD] No services found")
            connectionState = .error("서비스를 찾을 수 없습니다")
            return
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔍 [OBD] Discovered \(services.count) services:")
        for (index, service) in services.enumerated() {
            print("  [\(index + 1)] Service UUID: \(service.uuid.uuidString)")
            print("      isPrimary: \(service.isPrimary)")
        }
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // 모든 서비스의 모든 특성 발견
        for service in services {
            print("🔍 [OBD] Discovering characteristics for service: \(service.uuid.uuidString)")
            peripheral.discoverCharacteristics(nil, for: service)  // nil = 모든 특성 검색
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                   didDiscoverCharacteristicsFor service: CBService,
                   error: Error?) {
        if let error = error {
            print("❌ [OBD] Characteristic discovery error: \(error.localizedDescription)")
            connectionState = .error("특성 검색 실패: \(error.localizedDescription)")
            return
        }

        guard let characteristics = service.characteristics else {
            print("❌ [OBD] No characteristics found for service: \(service.uuid.uuidString)")
            return
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔍 [OBD] Service: \(service.uuid.uuidString)")
        print("🔍 [OBD] Discovered \(characteristics.count) characteristics:")

        for (index, characteristic) in characteristics.enumerated() {
            let properties = characteristic.properties
            var propStrings: [String] = []
            if properties.contains(.read) { propStrings.append("Read") }
            if properties.contains(.write) { propStrings.append("Write") }
            if properties.contains(.writeWithoutResponse) { propStrings.append("WriteNoResp") }
            if properties.contains(.notify) { propStrings.append("Notify") }
            if properties.contains(.indicate) { propStrings.append("Indicate") }

            print("  [\(index + 1)] UUID: \(characteristic.uuid.uuidString)")
            print("      Properties: \(propStrings.joined(separator: ", "))")
        }
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // 특성 찾기 - 더 유연하게
        for characteristic in characteristics {
            let uuid = characteristic.uuid.uuidString.uppercased()

            // Write 특성 찾기 (FFE1 또는 Write 속성을 가진 특성)
            if uuid.contains("FFE1") ||
               (characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse)) {
                if writeCharacteristic == nil {
                    writeCharacteristic = characteristic
                    print("✅ [OBD] Found write characteristic: \(uuid)")
                }
            }

            // Notify 특성 찾기 (FFE1 또는 Notify 속성을 가진 특성)
            if uuid.contains("FFE1") || characteristic.properties.contains(.notify) {
                if notifyCharacteristic == nil {
                    notifyCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                    print("✅ [OBD] Found notify characteristic: \(uuid)")
                    print("✅ [OBD] Enabled notifications for: \(uuid)")
                }
            }
        }

        // 모든 특성 발견 시 연결 완료
        if writeCharacteristic != nil && notifyCharacteristic != nil {
            stopConnectionTimer()  // 타이머 중지

            print("🎉 [OBD] All required characteristics found!")
            print("   Write: \(writeCharacteristic!.uuid.uuidString)")
            print("   Notify: \(notifyCharacteristic!.uuid.uuidString)")

            connectionState = .connected

            // 발견된 어댑터에서 정보 가져오기
            if let discoveredAdapter = discoveredAdapters.first(where: { $0.peripheral == peripheral }) {
                connectedAdapter = discoveredAdapter
            } else {
                // 발견 목록에 없으면 기본값으로 생성
                let name = peripheral.name ?? "Unknown"
                connectedAdapter = OBDAdapter(
                    id: UUID(),
                    peripheral: peripheral,
                    name: name,
                    rssi: -100,
                    serviceUUIDs: [],
                    manufacturerData: nil,
                    isConnectable: true,
                    localName: nil
                )
            }

            print("✅ [OBD] Connection established")

            // ELM327 초기화 (한 번만)
            if !isInitialized {
                isInitialized = true
                Task {
                    do {
                        try await initializeELM327()
                    } catch {
                        print("❌ [OBD] Failed to initialize ELM327: \(error)")
                        isInitialized = false  // 실패 시 재시도 가능하도록
                    }
                }
            } else {
                print("ℹ️ [OBD] Already initialized, skipping")
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                   didUpdateValueFor characteristic: CBCharacteristic,
                   error: Error?) {
        guard error == nil,
              let data = characteristic.value,
              let string = String(data: data, encoding: .utf8) else {
            return
        }

        responseBuffer += string

        // 상세 로그는 verbose 모드에서만
        if enableVerboseLogging {
            print("📥 [OBD] Received: \(string.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        // ">" 프롬프트가 나타나면 응답 완료
        if responseBuffer.contains(">") {
            let response = responseBuffer
                .replacingOccurrences(of: ">", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let continuation = responseContinuation {
                continuation.resume(returning: response)
                responseContinuation = nil
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                   didWriteValueFor characteristic: CBCharacteristic,
                   error: Error?) {
        if let error = error {
            print("❌ [OBD] Write error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Vehicle Status Model

struct VehicleStatus {
    var remoteStartEnabled: Bool = false  // BCM 원격 시동 기능 활성화 상태
    var windowsStatus: WindowsStatus = WindowsStatus()
    var sunroofStatus: SunroofStatus = .unknown
    var lastUpdated: Date = Date()

    struct WindowsStatus {
        var frontLeft: WindowState = .unknown
        var frontRight: WindowState = .unknown
        var rearLeft: WindowState = .unknown
        var rearRight: WindowState = .unknown

        var allClosed: Bool {
            [frontLeft, frontRight, rearLeft, rearRight].allSatisfy { $0 == .closed }
        }

        var allOpen: Bool {
            [frontLeft, frontRight, rearLeft, rearRight].allSatisfy { $0 == .open }
        }
    }

    enum WindowState: String {
        case open = "열림"
        case closed = "닫힘"
        case partial = "부분 열림"
        case unknown = "알 수 없음"

        var icon: String {
            switch self {
            case .open: return "arrow.up.square"
            case .closed: return "arrow.down.square"
            case .partial: return "arrow.up.and.down.square"
            case .unknown: return "questionmark.square"
            }
        }

        var color: String {
            switch self {
            case .open: return "accentGreen"
            case .closed: return "blue"
            case .partial: return "orange"
            case .unknown: return "secondaryText"
            }
        }
    }

    enum SunroofStatus: String {
        case open = "열림"
        case closed = "닫힘"
        case tilted = "환기"
        case unknown = "알 수 없음"

        var icon: String {
            switch self {
            case .open: return "sun.max"
            case .closed: return "moon"
            case .tilted: return "wind"
            case .unknown: return "questionmark.circle"
            }
        }

        var color: String {
            switch self {
            case .open: return "accentGreen"
            case .closed: return "blue"
            case .tilted: return "orange"
            case .unknown: return "secondaryText"
            }
        }
    }
}

// MARK: - Vehicle Status Reading Extension

extension OBDService {

    // MARK: - Vehicle Information

    /// VIN (차량 식별번호) 읽기 (7E0 DID 0xF190)
    func readVIN() async throws -> String? {
        do {
            _ = try await sendCommand("ATSH7E0")
            let response = try await sendCommand("22F190")

            // Parse multiline response
            let lines = response.components(separatedBy: "\n")
            var dataBytes: [UInt8] = []

            for line in lines {
                if line.contains(":") {
                    let parts = line.components(separatedBy: ":")
                    if parts.count > 1 {
                        let hexStr = parts[1].trimmingCharacters(in: .whitespaces)
                        let bytes = hexStr.split(separator: " ").compactMap { UInt8($0, radix: 16) }
                        dataBytes.append(contentsOf: bytes)
                    }
                }
            }

            // Remove response header (62 F1 90)
            if dataBytes.count > 3 && dataBytes[0] == 0x62 {
                let vinBytes = Array(dataBytes[3...])
                return String(bytes: vinBytes, encoding: .ascii)?.trimmingCharacters(in: .controlCharacters)
            }

            return nil
        } catch {
            print("⚠️ [OBD] Failed to read VIN: \(error)")
            return nil
        }
    }

    /// ECU 시리얼 번호 읽기 (7E0 DID 0xF18C)
    func readECUSerialNumber() async throws -> String? {
        do {
            _ = try await sendCommand("ATSH7E0")
            let response = try await sendCommand("22F18C")

            // Parse multiline response
            let lines = response.components(separatedBy: "\n")
            var dataBytes: [UInt8] = []

            for line in lines {
                if line.contains(":") {
                    let parts = line.components(separatedBy: ":")
                    if parts.count > 1 {
                        let hexStr = parts[1].trimmingCharacters(in: .whitespaces)
                        let bytes = hexStr.split(separator: " ").compactMap { UInt8($0, radix: 16) }
                        dataBytes.append(contentsOf: bytes)
                    }
                }
            }

            // Remove response header (62 F1 8C)
            if dataBytes.count > 3 && dataBytes[0] == 0x62 {
                let serialBytes = Array(dataBytes[3...])
                return String(bytes: serialBytes, encoding: .ascii)?.trimmingCharacters(in: .controlCharacters)
            }

            return nil
        } catch {
            print("⚠️ [OBD] Failed to read ECU S/N: \(error)")
            return nil
        }
    }

    /// TCU 시리얼 번호 읽기 (7E1 DID 0xF18C)
    func readTCUSerialNumber() async throws -> String? {
        do {
            _ = try await sendCommand("ATSH7E1")
            let response = try await sendCommand("22F18C")

            // Parse multiline response
            let lines = response.components(separatedBy: "\n")
            var dataBytes: [UInt8] = []

            for line in lines {
                if line.contains(":") {
                    let parts = line.components(separatedBy: ":")
                    if parts.count > 1 {
                        let hexStr = parts[1].trimmingCharacters(in: .whitespaces)
                        let bytes = hexStr.split(separator: " ").compactMap { UInt8($0, radix: 16) }
                        dataBytes.append(contentsOf: bytes)
                    }
                }
            }

            // Remove response header (62 F1 8C)
            if dataBytes.count > 3 && dataBytes[0] == 0x62 {
                let serialBytes = Array(dataBytes[3...])
                return String(bytes: serialBytes, encoding: .ascii)?.trimmingCharacters(in: .controlCharacters)
            }

            return nil
        } catch {
            print("⚠️ [OBD] Failed to read TCU S/N: \(error)")
            return nil
        }
    }

    // MARK: - Remote Start Status

    /// 원격 시동 기능 활성화 상태 읽기 (BCM DID 0x0122)
    /// Byte 5, Bit 7
    func readRemoteStartStatus() async throws -> Bool {
        // 마세라티 BCM PowerNet 주소 (AlfaOBD 소스에서 확인)
        // Module 14119 (MY2019+ PowerNet): address 70 (0x46)
        // Module 14116 (MY2019): address 68 (0x44)
        // Module 14112-14113 (MY2016-18): address 68 (0x44)
        let bcmCanIds = [
            "746",  // 0x700 + 0x46 (MY2019+ PowerNet standard)
            "744",  // 0x700 + 0x44 (MY2016-19 standard)
            "46",   // Direct hex address (MY2019+)
            "44",   // Direct hex address (MY2016-19)
            "70",   // Direct decimal (MY2019+)
            "68"    // Direct decimal (MY2016-19)
        ]

        // 타임아웃을 짧게 설정 (기본 200ms -> 50ms)
        _ = try? await sendCommand("ATST32")  // 32 * 4ms = 128ms
        print("⏱️ [Status] Set timeout to 128ms for BCM communication")

        for canId in bcmCanIds {
            print("📡 [Status] Trying BCM CAN ID: \(canId)")

            // 1. Set CAN header to BCM
            do {
                _ = try await sendCommand("ATSH\(canId)")
            } catch {
                print("⚠️ [Status] Failed to set header for \(canId): \(error)")
                continue
            }

            // 2. Read DID 0x0122
            let command = "220122"
            let response: String

            do {
                response = try await sendCommand(command)
            } catch {
                print("⚠️ [Status] Timeout with CAN ID \(canId): \(error)")
                continue
            }

            print("📡 [Status] BCM Response (ID \(canId)): \(response)")

            // Check for error responses
            let upperResponse = response.uppercased()
            if upperResponse.contains("NO DATA") ||
               upperResponse.contains("STOPPED") ||
               upperResponse.contains("ERROR") ||
               upperResponse.contains("UNABLE") {
                print("⚠️ [Status] No response from CAN ID \(canId), trying next...")
                continue
            }

            // Response format: "62 01 22 [data bytes...]"
            let bytes = parseHexResponse(response)

            guard bytes.count >= 9,
                  bytes[0] == 0x62,
                  bytes[1] == 0x01,
                  bytes[2] == 0x22 else {
                print("⚠️ [Status] Invalid response from CAN ID \(canId) (got \(bytes.count) bytes), trying next...")
                continue
            }

            // Byte 5 (index 8 in response: 3 header bytes + 5), Bit 7
            let byte5 = bytes[8]
            let remoteStartEnabled = (byte5 & 0x80) != 0

            print("✅ [Status] Successfully read from CAN ID \(canId)")
            print("📡 [Status] Byte 5: 0x\(String(format: "%02X", byte5))")
            print("📡 [Status] Remote Start Enabled: \(remoteStartEnabled)")

            // Reset timeout and header
            _ = try? await sendCommand("ATST64")  // Reset to default
            _ = try? await sendCommand("ATSH7DF")

            return remoteStartEnabled
        }

        // All CAN IDs failed
        print("❌ [Status] Remote start status not available (BCM not accessible)")

        // Reset timeout and header
        _ = try? await sendCommand("ATST64")
        _ = try? await sendCommand("ATSH7DF")

        // Return false instead of throwing error
        return false
    }

    // MARK: - Window Status

    /// 창문 상태 읽기
    /// Service 0x22 with window status DID (예: 0x0301-0x0304)
    func readWindowsStatus() async throws -> VehicleStatus.WindowsStatus {
        var status = VehicleStatus.WindowsStatus()

        // Note: 실제 DID는 차량에 따라 다를 수 있음
        // 여기서는 일반적인 구조를 가정

        do {
            // Front Left Window (DID 0x0301)
            status.frontLeft = try await readSingleWindowStatus(did: "0301")

            // Front Right Window (DID 0x0302)
            status.frontRight = try await readSingleWindowStatus(did: "0302")

            // Rear Left Window (DID 0x0303)
            status.rearLeft = try await readSingleWindowStatus(did: "0303")

            // Rear Right Window (DID 0x0304)
            status.rearRight = try await readSingleWindowStatus(did: "0304")

            print("📡 [Status] Windows - FL:\(status.frontLeft.rawValue) FR:\(status.frontRight.rawValue) RL:\(status.rearLeft.rawValue) RR:\(status.rearRight.rawValue)")

        } catch {
            print("⚠️ [Status] Failed to read all window statuses: \(error)")
            // 일부 창문만 실패한 경우에도 읽은 정보 반환
        }

        return status
    }

    /// 개별 창문 상태 읽기
    private func readSingleWindowStatus(did: String) async throws -> VehicleStatus.WindowState {
        let command = "22\(did)"

        do {
            let response = try await sendCommand(command)
            let bytes = parseHexResponse(response)

            guard bytes.count >= 4,
                  bytes[0] == 0x62 else {
                return .unknown
            }

            // Response data byte (position value: 0-255)
            // 0 = fully closed, 255 = fully open
            let position = bytes[3]

            switch position {
            case 0...10:
                return .closed
            case 245...255:
                return .open
            default:
                return .partial
            }

        } catch {
            print("⚠️ [Status] Failed to read window \(did): \(error)")
            return .unknown
        }
    }

    // MARK: - Sunroof Status

    /// 선루프 상태 읽기
    /// DID 0x0400 (예시)
    func readSunroofStatus() async throws -> VehicleStatus.SunroofStatus {
        let command = "220400"

        do {
            let response = try await sendCommand(command)
            let bytes = parseHexResponse(response)

            guard bytes.count >= 4,
                  bytes[0] == 0x62 else {
                return .unknown
            }

            // Response data byte
            // 0x00 = closed, 0x01 = tilted, 0x02 = open
            let statusByte = bytes[3]

            switch statusByte {
            case 0x00:
                print("📡 [Status] Sunroof: 닫힘")
                return .closed
            case 0x01:
                print("📡 [Status] Sunroof: 환기")
                return .tilted
            case 0x02:
                print("📡 [Status] Sunroof: 열림")
                return .open
            default:
                print("📡 [Status] Sunroof: 알 수 없음 (0x\(String(format: "%02X", statusByte)))")
                return .unknown
            }

        } catch {
            print("❌ [Status] Failed to read sunroof status: \(error)")
            return .unknown
        }
    }

    // MARK: - Comprehensive Status Reading

    /// 차량 전체 상태 읽기 (원격시동, 창문, 선루프)
    func readVehicleStatus() async throws -> VehicleStatus {
        var status = VehicleStatus()

        print("📡 [Status] Reading comprehensive vehicle status...")

        // 1. Remote start status (with timeout)
        if let remoteStart = try? await readRemoteStartStatus() {
            status.remoteStartEnabled = remoteStart
        } else {
            print("⚠️ [Status] Failed to read remote start status")
            status.remoteStartEnabled = false
        }

        // 2. Windows status
        if let windows = try? await readWindowsStatus() {
            status.windowsStatus = windows
        }

        // 3. Sunroof status
        if let sunroof = try? await readSunroofStatus() {
            status.sunroofStatus = sunroof
        }

        status.lastUpdated = Date()

        print("✅ [Status] Vehicle status updated at \(status.lastUpdated)")

        return status
    }

    // MARK: - Helper Functions

    /// Hex 응답 문자열을 바이트 배열로 파싱
    private func parseHexResponse(_ response: String) -> [UInt8] {
        let cleaned = response.replacingOccurrences(of: " ", with: "")
        var bytes: [UInt8] = []

        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let nextIndex = cleaned.index(index, offsetBy: 2, limitedBy: cleaned.endIndex) ?? cleaned.endIndex
            let byteString = cleaned[index..<nextIndex]
            if let byte = UInt8(byteString, radix: 16) {
                bytes.append(byte)
            }
            index = nextIndex
        }

        return bytes
    }
}

// MARK: - OBD Error

enum OBDError: Error, LocalizedError {
    case notConnected
    case invalidCommand
    case timeout
    case parseError

    var errorDescription: String? {
        switch self {
        case .notConnected: return "OBD 어댑터가 연결되지 않았습니다"
        case .invalidCommand: return "잘못된 명령어입니다"
        case .timeout: return "응답 시간 초과"
        case .parseError: return "응답 파싱 실패"
        }
    }
}
