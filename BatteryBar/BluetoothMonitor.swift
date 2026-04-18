import CoreBluetooth
import IOKit
import IOKit.hid
import SwiftUI

struct BluetoothDevice: Identifiable {
    let id: String
    let name: String
    let batteryLevel: Int
    let isKeyboard: Bool
    let isMouse: Bool

    var deviceIcon: String {
        if isKeyboard { return "keyboard" }
        if isMouse { return "computermouse" }
        return "dot.radiowaves.left.and.right"
    }

    var menuBarIcon: String { deviceIcon }

    var batteryIcon: String {
        switch batteryLevel {
        case 75...100: return "battery.100"
        case 50..<75:  return "battery.75"
        case 25..<50:  return "battery.25"
        default:       return "battery.0"
        }
    }

    var batteryColor: Color {
        switch batteryLevel {
        case 20...100: return .green
        case 10..<20:  return .orange
        default:       return .red
        }
    }
}

class BLEBatteryReader: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var central: CBCentralManager!
    private var peripherals: [CBPeripheral] = []
    private var completed = Set<UUID>()
    private var results: [String: BluetoothDevice] = [:]

    var onUpdate: ([BluetoothDevice]) -> Void = { _ in }

    private let batteryServiceUUID = CBUUID(string: "180F")
    private let batteryLevelUUID   = CBUUID(string: "2A19")
    private let hidServiceUUID     = CBUUID(string: "1812")

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func scan() {
        guard central.state == .poweredOn else { return }
        results = [:]
        completed = []

        let found = central.retrieveConnectedPeripherals(withServices: [batteryServiceUUID, hidServiceUUID])
        // 重複を除去
        var seen = Set<UUID>()
        peripherals = found.filter { seen.insert($0.identifier).inserted }

        print("[BatteryBar] 検出されたペリフェラル数: \(peripherals.count)")

        if peripherals.isEmpty {
            onUpdate([])
            return
        }

        for p in peripherals {
            p.delegate = self
            central.connect(p)
        }
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("[BatteryBar] Bluetooth 状態: \(central.state.rawValue)")
        if central.state == .poweredOn { scan() }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("[BatteryBar] 接続成功: \(peripheral.name ?? "Unknown")")
        peripheral.discoverServices(nil) // 全サービスを探索してログに出す
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("[BatteryBar] 接続失敗: \(peripheral.name ?? "Unknown") error=\(String(describing: error))")
        finish(peripheral)
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let names = peripheral.services?.map { $0.uuid.uuidString } ?? []
        print("[BatteryBar] \(peripheral.name ?? "Unknown") のサービス: \(names)")

        guard let service = peripheral.services?.first(where: { $0.uuid == batteryServiceUUID }) else {
            print("[BatteryBar] → Battery Service (180F) なし。IOKit でフォールバック試行")
            if let level = ioKitBatteryLevel(name: peripheral.name ?? "") {
                let name = peripheral.name ?? peripheral.identifier.uuidString
                let (isKeyboard, isMouse) = ioKitDeviceType(name: name)
                results[peripheral.identifier.uuidString] = BluetoothDevice(
                    id: peripheral.identifier.uuidString,
                    name: name, batteryLevel: level,
                    isKeyboard: isKeyboard, isMouse: isMouse
                )
            }
            finish(peripheral)
            return
        }
        peripheral.discoverCharacteristics([batteryLevelUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let char = service.characteristics?.first(where: { $0.uuid == batteryLevelUUID }) else {
            print("[BatteryBar] \(peripheral.name ?? "Unknown"): Battery Level 特性なし")
            finish(peripheral); return
        }
        peripheral.readValue(for: char)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        defer { finish(peripheral) }
        guard characteristic.uuid == batteryLevelUUID,
              let level = characteristic.value?.first else { return }

        let name = peripheral.name ?? peripheral.identifier.uuidString
        print("[BatteryBar] \(name) バッテリー: \(level)%")
        let (isKeyboard, isMouse) = ioKitDeviceType(name: name)
        results[peripheral.identifier.uuidString] = BluetoothDevice(
            id: peripheral.identifier.uuidString,
            name: name, batteryLevel: Int(level),
            isKeyboard: isKeyboard, isMouse: isMouse
        )
    }

    private func finish(_ peripheral: CBPeripheral) {
        completed.insert(peripheral.identifier)
        if completed.count >= peripherals.count {
            onUpdate(results.values.sorted { $0.batteryLevel < $1.batteryLevel })
        }
    }

    // IOKit でバッテリー残量を探す（複数キーを試す）
    private func ioKitBatteryLevel(name: String) -> Int? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDDevice"), &iter) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iter) }
            let devName = prop(service, kIOHIDProductKey) as? String
            guard devName == name else { continue }

            // 既知のバッテリーキーを全試行
            for key in ["BatteryPercent", "BatteryCurrentCapacity", "BatteryLevel",
                        "Battery Level", "DeviceBatteryLevel", "MaximumCapacity"] {
                if let v = prop(service, key) as? Int, v > 0 {
                    print("[BatteryBar] IOKit \(name) バッテリー key=\(key) value=\(v)")
                    return v
                }
            }

            // 見つからない場合は全プロパティをログに出す
            if let allProps = IORegistryEntryCreateCFProperties(service, nil, kCFAllocatorDefault, 0) as? [String: Any] {
                let batteryRelated = allProps.filter { $0.key.lowercased().contains("batt") }
                print("[BatteryBar] IOKit \(name) バッテリー関連プロパティ: \(batteryRelated)")
                if batteryRelated.isEmpty {
                    print("[BatteryBar] IOKit \(name) 全プロパティキー: \(allProps.keys.sorted())")
                }
            }
        }
        return nil
    }

    private func ioKitDeviceType(name: String) -> (isKeyboard: Bool, isMouse: Bool) {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDDevice"), &iter) == kIOReturnSuccess else { return (false, false) }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iter) }
            guard prop(service, kIOHIDProductKey) as? String == name else { continue }
            let page  = prop(service, kIOHIDPrimaryUsagePageKey) as? Int ?? 0
            let usage = prop(service, kIOHIDPrimaryUsageKey) as? Int ?? 0
            return (isKeyboard: page == 1 && (usage == 6 || usage == 7),
                    isMouse:    page == 1 && usage == 2)
        }
        return (false, false)
    }

    private func prop(_ service: io_service_t, _ key: String) -> AnyObject? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}

@MainActor
class BluetoothMonitor: ObservableObject {
    @Published var devices: [BluetoothDevice] = []

    private var reader: BLEBatteryReader!
    private var timer: Timer?

    init() {
        reader = BLEBatteryReader()
        reader.onUpdate = { [weak self] devices in
            self?.devices = devices
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() { reader.scan() }

}
