import SwiftUI
import CoreBluetooth
import UserNotifications

// 蓝牙管理器
class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var centralManager: CBCentralManager!
    @Published var peripherals: [CBPeripheral] = []
    @Published var connectedPeripheral: CBPeripheral?
    @Published var isFiltering: Bool = true
    @Published var isConnected: Bool = false
    @Published var receivedDataList: [String] = []
    @Published var connectionStatus: String = "Disconnected"
    private var reconnectTimer: Timer?
    private var connectionCheckTimer: Timer?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        // 请求通知权限
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Error requesting notification authorization: \(error.localizedDescription)")
            }
        }
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
        if let currentConnected = connectedPeripheral, currentConnected != peripheral {
            disconnect(peripheral: currentConnected)
        }
        centralManager.connect(peripheral, options: nil)
    }

    // 断开连接
    func disconnect(peripheral: CBPeripheral) {
        centralManager.cancelPeripheralConnection(peripheral)
        connectedPeripheral = nil
        isConnected = false
        connectionStatus = "Disconnected"
        startScanning()
        startReconnectTimer(for: peripheral)
    }

    // 开始重连定时器
    private func startReconnectTimer(for peripheral: CBPeripheral) {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.connectedPeripheral == nil {
                self.centralManager.connect(peripheral, options: nil)
                self.connectionStatus = "Reconnecting..."
            } else {
                self.reconnectTimer?.invalidate()
            }
        }
    }

    // 停止重连定时器
    private func stopReconnectTimer() {
        reconnectTimer?.invalidate()
    }

    // 开始连接检查定时器
    func startConnectionCheck() {
        connectionCheckTimer?.invalidate()
        connectionCheckTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.connectedPeripheral != nil && !self.isConnected {
                self.startReconnectTimer(for: self.connectedPeripheral!)
            }
        }
    }

    // 停止连接检查定时器
    func stopConnectionCheck() {
        connectionCheckTimer?.invalidate()
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
        connectionStatus = "Connected"
        stopReconnectTimer()
        peripheral.discoverServices([CBUUID(string: "fff0")])
    }

    // 连接失败
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
        connectionStatus = "Connection failed"
    }

    // 断开连接回调
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedPeripheral = nil
        isConnected = false
        connectionStatus = "Disconnected"
        startScanning()
        startReconnectTimer(for: peripheral)
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
            // 发送本地通知
            let content = UNMutableNotificationContent()
            content.title = "BLE Data Received"
            content.body = string
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Error sending notification: \(error.localizedDescription)")
                }
            }
            // 更新接收到的数据列表
            receivedDataList.append(string)
        }
    }
}

// 连接后视图
struct ConnectedView: View {
    @ObservedObject var bluetoothManager: BluetoothManager

    var body: some View {
        VStack {
            Text("Connection Status: \(bluetoothManager.connectionStatus)")
            if let connectedPeripheral = bluetoothManager.connectedPeripheral {
                Text("Connected to \(connectedPeripheral.name ?? "Unknown Device")")
            }
            // 显示接收到的数据列表
            Section(header: Text("Received Data")) {
                List(bluetoothManager.receivedDataList, id: \.self) { data in
                    Text(data)
                }
            }
        }
        .onAppear {
            bluetoothManager.startConnectionCheck()
        }
        .onDisappear {
            bluetoothManager.stopConnectionCheck()
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
                        NavigationLink(destination: ConnectedView(bluetoothManager: bluetoothManager)) {
                            Text(connectedPeripheral.name ?? "Unknown Device")
                               .foregroundColor(.green)
                               .swipeActions(edge: .trailing) {
                                    Button("Disconnect", role: .destructive) {
                                        bluetoothManager.disconnect(peripheral: connectedPeripheral)
                                    }
                                }
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
