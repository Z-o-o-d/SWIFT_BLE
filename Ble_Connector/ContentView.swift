import SwiftUI
import CoreBluetooth

// 蓝牙管理器
class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var centralManager: CBCentralManager!
    @Published var peripherals: [CBPeripheral] = []
    @Published var connectedPeripheral: CBPeripheral?
    @Published var isFiltering: Bool = true
    @Published var isConnected: Bool = false

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // 开始扫描设备
    func startScanning() {
        centralManager.scanForPeripherals(withServices: nil, options: nil)
    }

    // 停止扫描设备
    func stopScanning() {
        centralManager.stopScan()
    }

    // 连接设备
    func connect(to peripheral: CBPeripheral) {
        centralManager.connect(peripheral, options: nil)
    }

    // 断开连接
    func disconnect(peripheral: CBPeripheral) {
        centralManager.cancelPeripheralConnection(peripheral)
    }

    // 中心管理器状态更新
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanning()
        }
    }

    // 发现新设备
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if isFiltering {
            if let localName = advertisementData["kCBAdvDataLocalName"] as? String, localName.contains("ZeBLE") {
                if !peripherals.contains(peripheral) {
                    peripherals.append(peripheral)
                }
            }
        } else {
            if !peripherals.contains(peripheral) {
                peripherals.append(peripheral)
            }
        }
    }

    // 连接成功
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        stopScanning()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        isConnected = true
        peripheral.discoverServices([CBUUID(string: "fff0")])
    }

    // 连接失败
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
    }

    // 断开连接
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedPeripheral = nil
        isConnected = false
        startScanning()
    }

    // 发现服务
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("Error discovering services: \(error.localizedDescription)")
            return
        }

        guard let services = peripheral.services else { return }
        for service in services {
            if service.uuid == CBUUID(string: "fff0") {
                peripheral.discoverCharacteristics([CBUUID(string: "fff1")], for: service)
            }
        }
    }

    // 发现特征
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("Error discovering characteristics: \(error.localizedDescription)")
            return
        }

        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == CBUUID(string: "fff1") {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    // 特征值更新
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error updating characteristic value: \(error.localizedDescription)")
            return
        }

        if let data = characteristic.value, let string = String(data: data, encoding: .utf8) {
            print("Received data: \(string)")
        }
    }
}

// 连接后视图
struct ConnectedView: View {
    @ObservedObject var bluetoothManager: BluetoothManager

    var body: some View {
        VStack {
            Text("Connected to \(bluetoothManager.connectedPeripheral?.name ?? "Unknown Device")")
            Button("Disconnect") {
                if let peripheral = bluetoothManager.connectedPeripheral {
                    bluetoothManager.disconnect(peripheral: peripheral)
                }
            }
        }
    }
}

// 主视图
struct ContentView: View {
    @StateObject private var bluetoothManager = BluetoothManager()

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Filter Settings")) {
                    Toggle("Filter devices containing 'ZeBLE'", isOn: $bluetoothManager.isFiltering)
                        .onChange(of: bluetoothManager.isFiltering) { _ in
                            bluetoothManager.peripherals.removeAll()
                            bluetoothManager.startScanning()
                        }
                }

                if let connectedPeripheral = bluetoothManager.connectedPeripheral {
                    Section(header: Text("Connected Device")) {
                        NavigationLink(destination: ConnectedView(bluetoothManager: bluetoothManager), isActive: $bluetoothManager.isConnected) {
                            Text(connectedPeripheral.name ?? "Unknown Device")
                                .foregroundColor(.green)
                        }
                        Button("Disconnect") {
                            bluetoothManager.disconnect(peripheral: connectedPeripheral)
                        }
                    }
                }

                Section(header: Text("Available Devices")) {
                    ForEach(bluetoothManager.peripherals, id: \.identifier) { peripheral in
                        Button(action: {
                            bluetoothManager.connect(to: peripheral)
                        }) {
                            Text(peripheral.name ?? "Unknown Device")
                        }
                    }
                }
            }
            .navigationTitle("Bluetooth Devices")
        }
    }
}

// 预览
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
