import CoreBluetooth
import Foundation

/// Finds the ESP32 controller over Bluetooth Low Energy, keeps it connected,
/// turns its 2-byte packets into ControlEvents and sends LED patterns back.
///
/// Protocol (must match Firmware/controller_v2.ino):
///   Input characteristic (notify): [controlId, value as Int8]
///     1 knob turn (signed clicks), 21 knob push, 11 Record, 12 Playback,
///     13 Confirm, 23 Confirm held (Cancel), 14 Left, 15 Right, 31 mode switch (0 View, 1 Record)
///   LED characteristic (write): one byte, see LEDPattern
final class ControllerManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    enum Status: Equatable {
        case bluetoothOff, searching, connecting, connected

        var label: String {
            switch self {
            case .bluetoothOff: return "Bluetooth off"
            case .searching: return "Searching"
            case .connecting: return "Connecting"
            case .connected: return "Connected"
            }
        }
    }

    static let serviceUUID = CBUUID(string: "6F1D0001-8A3C-4B6E-9A51-2C7E0B1D4A01")
    static let inputUUID = CBUUID(string: "6F1D0002-8A3C-4B6E-9A51-2C7E0B1D4A01")
    static let ledUUID = CBUUID(string: "6F1D0003-8A3C-4B6E-9A51-2C7E0B1D4A01")

    var onEvent: ((ControlEvent) -> Void)?
    var onStatus: ((Status) -> Void)?

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var ledCharacteristic: CBCharacteristic?
    private var currentLED: LEDPattern = .off
    private var lastEvent: (event: ControlEvent, time: Date)?
    private let savedIDKey = "controller.peripheral.id"

    private(set) var status: Status = .bluetoothOff {
        didSet { if status != oldValue { onStatus?(status) } }
    }

    /// Starting asks for Bluetooth permission the first time.
    func start() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        }
    }

    func setLED(_ pattern: LEDPattern) {
        currentLED = pattern
        writeLED()
    }

    /// Use when a new controller board replaces the old one.
    func forgetController() {
        UserDefaults.standard.removeObject(forKey: savedIDKey)
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        ledCharacteristic = nil
        scan()
    }

    // MARK: Connecting

    private func connectOrScan() {
        guard let central, central.state == .poweredOn else { return }
        if let known = central.retrieveConnectedPeripherals(withServices: [Self.serviceUUID]).first {
            connect(known)
            return
        }
        if let idString = UserDefaults.standard.string(forKey: savedIDKey),
           let id = UUID(uuidString: idString),
           let saved = central.retrievePeripherals(withIdentifiers: [id]).first {
            connect(saved)
            // Also scan, in case the saved board is gone and a new one is on.
            central.scanForPeripherals(withServices: [Self.serviceUUID])
            return
        }
        scan()
    }

    private func scan() {
        guard let central, central.state == .poweredOn else { return }
        status = .searching
        central.scanForPeripherals(withServices: [Self.serviceUUID])
    }

    private func connect(_ target: CBPeripheral) {
        peripheral = target
        target.delegate = self
        status = .connecting
        central?.connect(target)
    }

    private func writeLED() {
        guard let peripheral, let ledCharacteristic else { return }
        peripheral.writeValue(Data([currentLED.rawValue]), for: ledCharacteristic, type: .withResponse)
    }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            connectOrScan()
        } else {
            status = .bluetoothOff
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard status != .connected else { central.stopScan(); return }
        central.stopScan()
        if let current = self.peripheral, current.identifier != peripheral.identifier {
            central.cancelPeripheralConnection(current)
        }
        connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        central.stopScan()
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: savedIDKey)
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        scan()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        ledCharacteristic = nil
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        // A pending connect waits until the controller is back in range or switched on again.
        status = .connecting
        central.connect(peripheral)
    }

    // MARK: CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] where service.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics([Self.inputUUID, Self.ledUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == Self.inputUUID {
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == Self.ledUUID {
                ledCharacteristic = characteristic
            }
        }
        status = .connected
        writeLED()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.inputUUID, let data = characteristic.value, data.count >= 2 else { return }
        let bytes = [UInt8](data)
        let value = Int(Int8(bitPattern: bytes[1]))
        guard let event = Self.event(id: bytes[0], value: value) else { return }

        // Ignore the same button arriving twice within 100 ms. Knob turns always pass.
        if case .knob = event {} else if let last = lastEvent, last.event == event,
                                          Date().timeIntervalSince(last.time) < 0.1 {
            return
        }
        lastEvent = (event, Date())
        onEvent?(event)
    }

    static func event(id: UInt8, value: Int) -> ControlEvent? {
        switch id {
        case 1: return value == 0 ? nil : .knob(value)
        case 21: return .knobPress
        case 11: return .record
        case 12: return .playback
        case 13: return .confirm
        case 23: return .cancel
        case 14: return .left
        case 15: return .right
        case 31: return .modeSwitch(record: value == 1)
        default: return nil
        }
    }
}
