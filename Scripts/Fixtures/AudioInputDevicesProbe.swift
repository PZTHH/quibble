import Foundation

@main
struct AudioInputDeviceRegression {
    @MainActor
    static func main() throws {
        let suite = "quibble-audio-input-probe-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let builtIn = AudioInputDevices.Device(deviceID: 1, uid: "test.builtin", name: "Built-in microphone", inputChannels: 1, transportType: 0)
        let usb = AudioInputDevices.Device(deviceID: 2, uid: "test.usb", name: "USB microphone", inputChannels: 2, transportType: 0)
        var snapshot = AudioInputDevices.Snapshot(devices: [builtIn, usb], defaultDeviceID: builtIn.deviceID)
        let service = AudioInputDevices(defaults: defaults, observeChanges: false, readSnapshot: { snapshot })
        precondition(service.selectedUID == nil && service.resolvedDevice == builtIn)
        precondition(service.select(uid: usb.uid))
        let selected = try service.resolveForRecording()
        precondition(selected == usb)
        let reopened = AudioInputDevices(defaults: defaults, observeChanges: false, readSnapshot: { snapshot })
        precondition(reopened.selectedUID == usb.uid, "Selection was not persisted by UID")
        var changes = 0
        service.onDevicesChanged = { changes += 1 }
        snapshot = .init(devices: [builtIn], defaultDeviceID: builtIn.deviceID)
        service.refresh()
        precondition(service.selectedUID == usb.uid && service.selectionUnavailable && service.selectionName == usb.name)
        do { _ = try service.resolveForRecording(); fatalError("Disconnected preference silently fell back") }
        catch AudioInputDevices.InputError.unavailable { }
        precondition(changes == 1)
        let reconnected = AudioInputDevices.Device(deviceID: 9, uid: usb.uid, name: usb.name, inputChannels: 2, transportType: 0)
        snapshot = .init(devices: [builtIn, reconnected], defaultDeviceID: builtIn.deviceID)
        service.refresh()
        let resolved = try service.resolveForRecording()
        precondition(resolved == reconnected, "Device ID changed but UID should reconnect")
        precondition(service.select(uid: nil))
        snapshot = .init(devices: [builtIn, reconnected], defaultDeviceID: reconnected.deviceID)
        service.refresh()
        precondition(service.selectedUID == nil && service.resolvedDevice == reconnected)
        precondition(!service.select(uid: "unknown"), "Unknown devices must not create a fake preference")
        precondition(service.selectedUID == nil)
        let native = try AudioInputDevices.systemSnapshot()
        precondition(native.devices.allSatisfy { !$0.uid.isEmpty && $0.inputChannels > 0 })
        print("Input-device probe passed: UID persistence, disconnect/reconnect, system-default following, invalid choice rejection; read-only enumeration found \(native.devices.count) inputs.")
    }
}
