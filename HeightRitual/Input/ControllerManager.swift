import CoreBluetooth
import Foundation

/// Finds the ESP32 controller over Bluetooth LE, keeps it connected, turns its 2-byte packets
/// into ControlEvents and writes the light state back. Protocol: SPEC section 6, which must match
/// Firmware/controller/controller.ino.
///
/// Not run on a device yet. CoreBluetooth does not work in the simulator.
@MainActor
final class ControllerManager: NSObject, ControllerLink {
    nonisolated static let serviceUUID = CBUUID(string: "6F1D0001-8A3C-4B6E-9A51-2C7E0B1D4A01")
    nonisolated static let inputUUID = CBUUID(string: "6F1D0002-8A3C-4B6E-9A51-2C7E0B1D4A01")
    nonisolated static let lightUUID = CBUUID(string: "6F1D0003-8A3C-4B6E-9A51-2C7E0B1D4A01")

    var onEvent: ((ControlEvent) -> Void)?
    var onStatus: ((ControllerStatus) -> Void)?
    var onRaw: (([UInt8]) -> Void)?
    var onNote: ((String) -> Void)?

    /// The full firmware sends the mode switch position as soon as notifications start. If nothing
    /// arrives within this time, the test page says so. The link is kept: the buttons-only
    /// firmware sends nothing until a button is pressed.
    static let handshakeSeconds = 3.0
    private var handshakeTask: Task<Void, Never>?
    private var gotPacket = false
    private var rescanAfterDisconnect = false

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var lightCharacteristic: CBCharacteristic?
    private var light = LightState()
    private var debouncer = EventDebouncer()
    private let savedIDKey = "controller.peripheral.id"

    private(set) var status: ControllerStatus = ControllerManager.needsPermission ? .notAllowed : .bluetoothOff {
        didSet { if status != oldValue { onStatus?(status) } }
    }

    /// Whether starting would show the Bluetooth permission prompt.
    static var needsPermission: Bool { CBManager.authorization == .notDetermined }

    /// Starting asks for Bluetooth permission the first time.
    func start() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        }
    }

    func setLight(_ light: LightState) {
        self.light = light
        writeLight()
    }

    /// Use when a new controller board replaces the old one.
    func forget() {
        handshakeTask?.cancel()
        UserDefaults.standard.removeObject(forKey: savedIDKey)
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        lightCharacteristic = nil
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
        handshakeTask?.cancel()
        gotPacket = false
        peripheral = target
        target.delegate = self
        status = .connecting
        central?.connect(target)
    }

    private func writeLight() {
        guard let peripheral, let lightCharacteristic else { return }
        peripheral.writeValue(Data(light.bytes), for: lightCharacteristic, type: .withResponse)
    }

    fileprivate func received(_ data: Data) {
        let bytes = [UInt8](data)
        gotPacket = true
        onRaw?(bytes)
        guard bytes.count >= 2 else { return }
        guard let event = ControlEvent.from(id: bytes[0], value: Int8(bitPattern: bytes[1])) else { return }
        guard debouncer.accept(event, at: ProcessInfo.processInfo.systemUptime) else { return }
        onEvent?(event)
    }
}

// The central manager runs on the main queue, so every callback is on the main actor.
extension ControllerManager: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            switch central.state {
            case .poweredOn: connectOrScan()
            case .unauthorized: status = .notAllowed
            default: status = .bluetoothOff
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            central.stopScan()
            guard status != .connected else { return }
            // Already connecting to this one (saved controller); a second connect only confuses it.
            if peripheral.identifier == self.peripheral?.identifier, status == .connecting { return }
            if let current = self.peripheral, current.identifier != peripheral.identifier {
                central.cancelPeripheralConnection(current)
            }
            connect(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            central.stopScan()
            UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: savedIDKey)
            onNote?("Connected to \(peripheral.name ?? "unnamed device")")
            peripheral.discoverServices([Self.serviceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        MainActor.assumeIsolated {
            onNote?("Could not connect: \(error?.localizedDescription ?? "no reason given")")
            scan()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        MainActor.assumeIsolated {
            lightCharacteristic = nil
            handshakeTask?.cancel()
            guard peripheral.identifier == self.peripheral?.identifier else { return }
            onNote?("Disconnected: \(error?.localizedDescription ?? "by the app")")
            if rescanAfterDisconnect {
                // Start over from the advertisement, as Forget does.
                rescanAfterDisconnect = false
                self.peripheral = nil
                scan()
                return
            }
            // A pending connect waits until the controller is back in range or switched on again.
            status = .connecting
            central.connect(peripheral)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            if let error {
                onNote?("Service search failed: \(error.localizedDescription)")
                return
            }
            let services = peripheral.services ?? []
            guard let service = services.first(where: { $0.uuid == Self.serviceUUID }) else {
                onNote?("Height Ritual service not found")
                return
            }
            peripheral.discoverCharacteristics([Self.inputUUID, Self.lightUUID], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        MainActor.assumeIsolated {
            if let error {
                onNote?("Characteristic search failed: \(error.localizedDescription)")
                return
            }
            let characteristics = service.characteristics ?? []
            let input = characteristics.first { $0.uuid == Self.inputUUID }
            lightCharacteristic = characteristics.first { $0.uuid == Self.lightUUID }
            onNote?("Input \(input == nil ? "missing" : "found"), light \(lightCharacteristic == nil ? "missing" : "found")")
            guard let input else { return }
            // The firmware sends the mode switch position when this subscription starts.
            peripheral.setNotifyValue(true, for: input)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard characteristic.uuid == Self.inputUUID else { return }
            if let error {
                onNote?("Notifications failed: \(error.localizedDescription)")
                restartLink(peripheral)
                return
            }
            guard characteristic.isNotifying else { return }
            onNote?("Notifications on")
            status = .connected
            writeLight()
            handshakeTask?.cancel()
            handshakeTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.handshakeSeconds))
                guard let self, !Task.isCancelled, !gotPacket else { return }
                onNote?("No data yet. Press a button on the controller.")
            }
        }
    }

    /// Drops the link and connects again from scratch, as Forget does, but keeps the saved controller.
    private func restartLink(_ target: CBPeripheral) {
        handshakeTask?.cancel()
        status = .connecting
        rescanAfterDisconnect = true
        central?.cancelPeripheralConnection(target)
        // didDisconnect connects again.
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        guard characteristic.uuid == Self.inputUUID, let data = characteristic.value else { return }
        MainActor.assumeIsolated { received(data) }
    }
}
