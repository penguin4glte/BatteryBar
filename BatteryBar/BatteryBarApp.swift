import AppKit
import Combine
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var monitor: BluetoothMonitor!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // Dock に表示しない

        monitor = BluetoothMonitor()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }

        let contentView = ContentView().environmentObject(monitor)
        popover = NSPopover()
        popover.contentViewController = NSHostingController(rootView: contentView)
        popover.behavior = .transient

        monitor.$devices
            .receive(on: RunLoop.main)
            .sink { [weak self] devices in self?.updateButton(devices: devices) }
            .store(in: &cancellables)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func updateButton(devices: [BluetoothDevice]) {
        guard let button = statusItem.button else { return }

        guard !devices.isEmpty else {
            button.image = NSImage(systemSymbolName: "battery.0", accessibilityDescription: nil)
            button.attributedTitle = NSAttributedString()
            return
        }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let result = NSMutableAttributedString()

        for (i, device) in devices.enumerated() {
            if i > 0 {
                result.append(NSAttributedString(string: "   ", attributes: [.font: font]))
            }

            if let baseImg = NSImage(systemSymbolName: device.menuBarIcon, accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
                let img = baseImg.withSymbolConfiguration(config) ?? baseImg
                img.isTemplate = true
                let attachment = NSTextAttachment()
                attachment.image = img
                attachment.bounds = CGRect(x: 0, y: -3, width: img.size.width, height: img.size.height)
                result.append(NSAttributedString(attachment: attachment))
            }

            result.append(NSAttributedString(
                string: " \(device.batteryLevel)%",
                attributes: [.font: font]
            ))
        }

        button.image = nil
        button.attributedTitle = result
    }
}

@main
struct BatteryBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
