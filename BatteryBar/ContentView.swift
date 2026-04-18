import SwiftUI

struct ContentView: View {
    @EnvironmentObject var monitor: BluetoothMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if monitor.devices.isEmpty {
                Text("Bluetooth デバイスが見つかりません")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                ForEach(monitor.devices) { device in
                    DeviceRow(device: device)
                    if device.id != monitor.devices.last?.id {
                        Divider().padding(.horizontal, 12)
                    }
                }
            }

            Divider()

            HStack {
                Button("更新") { monitor.refresh() }
                Spacer()
                Button("終了") { NSApplication.shared.terminate(nil) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 300)
    }
}

struct DeviceRow: View {
    let device: BluetoothDevice

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.deviceIcon)
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                ProgressView(value: Double(device.batteryLevel), total: 100)
                    .tint(device.batteryColor)
            }

            Text("\(device.batteryLevel)%")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(device.batteryColor)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
