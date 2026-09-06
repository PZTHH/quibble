import AppKit
import Combine

/// Lives with the application, independently of the settings window.
@MainActor
final class MenuBarController: NSObject, ObservableObject, NSMenuDelegate {
    @Published var page: QuibblePage? = .home
    @Published private(set) var requestID = 0
    private(set) var importRequested = false
    private var statusItem: NSStatusItem?
    private weak var controller: DictationController?
    private var openWindow: (() -> Void)?
    private var observation: AnyCancellable?

    func install(controller: DictationController, openWindow: @escaping () -> Void) {
        self.openWindow = openWindow
        guard statusItem == nil else { return }
        self.controller = controller
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "QuibbleStatusItem"
        item.isVisible = true
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
        updateImage()
        observation = controller.$recording.removeDuplicates().sink { [weak self] recording in
            self?.updateImage(recording: recording)
        }
    }

    private func updateImage(recording: Bool = false) {
        let image = recording
            ? NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Quibble — Recording")
            : NSImage(named: "QuibbleMark")?.copy() as? NSImage
        let resolved = image ?? NSImage(systemSymbolName: "quote.bubble.fill", accessibilityDescription: "Quibble")
        resolved?.size = NSSize(width: 18, height: 18)
        resolved?.isTemplate = true
        statusItem?.button?.image = resolved
        statusItem?.button?.imageScaling = .scaleProportionallyDown
        statusItem?.button?.toolTip = recording ? "Quibble — Recording" : "Quibble"
        statusItem?.button?.setAccessibilityLabel(recording ? "Quibble — Recording" : "Quibble")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let controller else { return }
        controller.audioInputs.refresh()
        let busy = controller.recording || controller.processing || controller.inserting
        menu.removeAllItems()
        add("Transcribe File…", to: menu, action: #selector(transcribeFile), enabled: !busy)
        add("History", to: menu, action: #selector(history))
        add("Settings…", to: menu, action: #selector(settings), key: ",")
        menu.addItem(.separator())

        let microphones = NSMenu(title: "Microphone")
        microphones.autoenablesItems = false
        add("System Default", to: microphones, action: #selector(selectMicrophone(_:)),
            enabled: !busy, checked: controller.audioInputs.selectedUID == nil)
        microphones.addItem(.separator())
        for device in controller.audioInputs.devices {
            add(device.name, to: microphones, action: #selector(selectMicrophone(_:)),
                enabled: !busy, checked: controller.audioInputs.selectedUID == device.uid, value: device.uid)
        }
        if let selected = controller.audioInputs.selectedUID,
           !controller.audioInputs.devices.contains(where: { $0.uid == selected }) {
            add("Selected microphone unavailable", to: microphones, enabled: false, checked: true)
        }
        let microphone = add("Microphone", to: menu)
        microphone.submenu = microphones

        let modes = NSMenu(title: "Mode")
        modes.autoenablesItems = false
        for mode in controller.workflows.workflows {
            add(mode.name, to: modes, action: #selector(selectMode(_:)), enabled: !busy,
                checked: mode.id == controller.workflows.selectedID, value: mode.id)
        }
        let mode = add("Mode", to: menu)
        mode.submenu = modes
        menu.addItem(.separator())
        add("Quit Quibble", to: menu, action: #selector(quit), key: "q")
    }

    @discardableResult private func add(_ title: String, to menu: NSMenu, action: Selector? = nil,
                                       key: String = "", enabled: Bool = true, checked: Bool = false,
                                       value: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.isEnabled = enabled
        item.state = checked ? .on : .off
        item.representedObject = value
        menu.addItem(item)
        return item
    }

    private func navigate(_ page: QuibblePage, importing: Bool = false) {
        self.page = page
        importRequested = importing
        requestID += 1
        openWindow?()
        NSApplication.shared.activate()
    }
    func consumeImportRequest() -> Bool {
        let requested = importRequested
        importRequested = false
        return requested
    }
    @objc private func transcribeFile() { navigate(.home, importing: true) }
    @objc private func history() { navigate(.history) }
    @objc private func settings() { navigate(.general) }
    @objc private func selectMicrophone(_ item: NSMenuItem) {
        guard let controller, !controller.recording && !controller.processing && !controller.inserting else { return }
        controller.audioInputs.select(uid: item.representedObject as? String)
    }
    @objc private func selectMode(_ item: NSMenuItem) {
        guard let controller, !controller.recording && !controller.processing && !controller.inserting,
              let id = item.representedObject as? String else { return }
        controller.workflows.select(id)
    }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
