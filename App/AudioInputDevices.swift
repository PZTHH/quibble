import AudioToolbox
import Combine
import CoreAudio
import Foundation

/// Per-app input preference. Reading devices never starts audio or changes the system route.
@MainActor
final class AudioInputDevices: ObservableObject {
    struct Device: Equatable, Identifiable, Sendable {
        let deviceID: AudioDeviceID
        let uid: String
        let name: String
        let inputChannels: UInt32
        let transportType: UInt32
        var id: String { uid }
        var symbolName: String {
            switch transportType {
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: "headphones"
            case kAudioDeviceTransportTypeUSB: "cable.connector"
            case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate: "waveform.path"
            default: "mic"
            }
        }
    }

    struct Snapshot: Equatable, Sendable {
        let devices: [Device]
        let defaultDeviceID: AudioDeviceID?
        var hardwareDeviceIDs: [AudioDeviceID] = []
    }

    enum InputError: LocalizedError {
        case enumerationFailed(OSStatus)
        case noDefaultInput
        case unavailable(String)
        case routingFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .enumerationFailed: "The microphone list could not be read. Try again."
            case .noDefaultInput: "No system input microphone is available. Choose a microphone in the menu."
            case .unavailable(let name): "\(name) is unavailable. Reconnect it or choose another microphone in the menu."
            case .routingFailed: "The selected microphone could not be opened. Choose another microphone or try again."
            }
        }
    }

    static let preferenceKey = "audioInputUID.v1"
    private static let namePreferenceKey = "audioInputName.v1"
    @Published private(set) var devices: [Device] = []
    @Published private(set) var selectedUID: String?
    @Published private(set) var systemDefaultUID: String?
    @Published private(set) var error: String?
    /// Main-actor notification for menu refresh and active-device disconnect handling.
    var onDevicesChanged: (() -> Void)?
    private let defaults: UserDefaults
    private let readSnapshot: () throws -> Snapshot
    private let observesChanges: Bool
    private var savedName: String?
    private var systemListeners: [InputDeviceListener] = []
    private var deviceListeners: [InputDeviceListener] = []
    private var observedDeviceIDs: Set<AudioDeviceID> = []

    init(defaults: UserDefaults = .standard, observeChanges: Bool = true,
         readSnapshot: @escaping () throws -> Snapshot = AudioInputDevices.systemSnapshot) {
        self.defaults = defaults
        self.readSnapshot = readSnapshot
        self.observesChanges = observeChanges
        selectedUID = defaults.string(forKey: Self.preferenceKey).flatMap { $0.isEmpty ? nil : $0 }
        savedName = defaults.string(forKey: Self.namePreferenceKey)
        refresh()
        if observeChanges {
            systemListeners = [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice].compactMap {
                makeListener(object: AudioObjectID(kAudioObjectSystemObject), selector: $0)
            }
        }
    }

    var resolvedDevice: Device? {
        guard let uid = selectedUID ?? systemDefaultUID else { return nil }
        return devices.first { $0.uid == uid }
    }
    var selectionName: String {
        guard selectedUID != nil else { return "System Default" }
        return resolvedDevice?.name ?? savedName ?? "Selected microphone"
    }
    var systemDefaultName: String? { devices.first { $0.uid == systemDefaultUID }?.name }
    var selectionUnavailable: Bool { resolvedDevice == nil }

    /// Nil follows the system default at the next recording. An explicit UID is never silently replaced.
    @discardableResult
    func select(uid: String?) -> Bool {
        refresh()
        let device = uid.flatMap { id in devices.first { $0.uid == id } }
        guard uid == nil || device != nil else {
            error = InputError.unavailable("That microphone").localizedDescription
            return false
        }
        selectedUID = uid
        savedName = device?.name
        defaults.set(uid, forKey: Self.preferenceKey)
        defaults.set(savedName, forKey: Self.namePreferenceKey)
        error = nil
        onDevicesChanged?()
        return true
    }

    func refresh() {
        do {
            let snapshot = try readSnapshot()
            let updated = snapshot.devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            let defaultUID = updated.first { $0.deviceID == snapshot.defaultDeviceID }?.uid
            let changed = devices != updated || systemDefaultUID != defaultUID
            if devices != updated { devices = updated }
            if systemDefaultUID != defaultUID { systemDefaultUID = defaultUID }
            if let selectedUID, let selected = updated.first(where: { $0.uid == selectedUID }), savedName != selected.name {
                savedName = selected.name
                defaults.set(savedName, forKey: Self.namePreferenceKey)
            }
            error = nil
            if observesChanges { updateDeviceListeners(ids: Set(snapshot.hardwareDeviceIDs.isEmpty ? updated.map(\.deviceID) : snapshot.hardwareDeviceIDs)) }
            if changed { onDevicesChanged?() }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Capture one route for a whole utterance; recording and visualization must use this same device.
    func resolveForRecording() throws -> Device {
        refresh()
        if let error { throw NSError(domain: "Quibble.AudioInput", code: 1, userInfo: [NSLocalizedDescriptionKey: error]) }
        guard let device = resolvedDevice else {
            throw selectedUID == nil ? InputError.noDefaultInput : InputError.unavailable(selectionName)
        }
        return device
    }

    /// AudioQueue's route is local to this recording client. Call before starting/enqueuing input.
    nonisolated static func configure(queue: AudioQueueRef, for device: Device) throws {
        let uid = device.uid as CFString
        var reference = Unmanaged.passUnretained(uid)
        let status = withExtendedLifetime(uid) {
            AudioQueueSetProperty(queue, kAudioQueueProperty_CurrentDevice,
                &reference, UInt32(MemoryLayout<Unmanaged<CFString>>.size))
        }
        guard status == noErr else { throw InputError.routingFailed(status) }
    }

    private func makeListener(object: AudioObjectID, selector: AudioObjectPropertySelector,
                              scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> InputDeviceListener? {
        InputDeviceListener(object: object, selector: selector, scope: scope, changed: { [weak self] in
            Task { @MainActor [weak self] in self?.refresh() }
        })
    }

    private func updateDeviceListeners(ids: Set<AudioDeviceID>) {
        guard ids != observedDeviceIDs else { return }
        observedDeviceIDs = ids
        deviceListeners = ids.flatMap { id in
            [makeListener(object: id, selector: kAudioObjectPropertyName),
             makeListener(object: id, selector: kAudioDevicePropertyDeviceIsAlive),
             makeListener(object: id, selector: kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeInput)]
                .compactMap { $0 }
        }
    }

    nonisolated static func systemSnapshot() throws -> Snapshot {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        let sizeStatus = AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size)
        guard sizeStatus == noErr else { throw InputError.enumerationFailed(sizeStatus) }
        guard size > 0 else { return Snapshot(devices: [], defaultDeviceID: nil) }
        var ids = Array(repeating: AudioDeviceID(0), count: Int(size) / MemoryLayout<AudioDeviceID>.stride)
        let status = ids.withUnsafeMutableBytes { AudioObjectGetPropertyData(system, &address, 0, nil, &size, $0.baseAddress!) }
        guard status == noErr else { throw InputError.enumerationFailed(status) }
        let devices = ids.compactMap { id -> Device? in
            guard scalar(id, selector: kAudioDevicePropertyDeviceIsAlive) == 1,
                  let uid = string(id, selector: kAudioDevicePropertyDeviceUID), !uid.isEmpty,
                  let name = string(id, selector: kAudioObjectPropertyName), !name.isEmpty,
                  let channels = inputChannelCount(id), channels > 0 else { return nil }
            return Device(deviceID: id, uid: uid, name: name, inputChannels: channels,
                transportType: scalar(id, selector: kAudioDevicePropertyTransportType) ?? 0)
        }
        return Snapshot(devices: devices, defaultDeviceID: scalar(system, selector: kAudioHardwarePropertyDefaultInputDevice), hardwareDeviceIDs: ids)
    }

    private nonisolated static func scalar(_ object: AudioObjectID, selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private nonisolated static func string(_ object: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private nonisolated static func inputChannelCount(_ device: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size else { return nil }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, storage) == noErr else { return nil }
        let list = storage.assumingMemoryBound(to: AudioBufferList.self)
        let header = MemoryLayout<AudioBufferList>.size - MemoryLayout<AudioBuffer>.stride
        let maximumBuffers = (Int(size) - header) / MemoryLayout<AudioBuffer>.stride
        guard list.pointee.mNumberBuffers <= maximumBuffers else { return nil }
        return UnsafeMutableAudioBufferListPointer(list).reduce(UInt32(0)) { total, buffer in
            let next = total.addingReportingOverflow(buffer.mNumberChannels)
            return next.overflow ? UInt32.max : next.partialValue
        }
    }
}

/// Listener blocks are constructed outside MainActor and only enqueue actor-bound UI work.
private final class InputDeviceListener {
    private let object: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let block: AudioObjectPropertyListenerBlock

    init?(object: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope,
          changed: @escaping @Sendable () -> Void) {
        self.object = object
        address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        block = { _, _ in changed() }
        guard AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr else { return nil }
    }

    deinit { AudioObjectRemovePropertyListenerBlock(object, &address, .main, block) }
}
