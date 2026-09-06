#!/usr/bin/env python3
"""Exercise the production native menu with isolated controller/preferences.

Creates a temporary native status item; no microphone, model or user data access.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
STUBS = r'''
import Foundation
@MainActor enum QuibblePage { case home, history, general }
@MainActor final class DictationController: ObservableObject {
    @Published var recording = false
    var processing = false
    var inserting = false
    let audioInputs = Inputs()
    let workflows = Workflows()
}
@MainActor final class Inputs {
    struct Device { let name: String; let uid: String }
    var devices = [Device(name: "Test microphone", uid: "test")]
    var selectedUID: String?
    func refresh() {}
    func select(uid: String?) { selectedUID = uid }
}
@MainActor final class Workflows {
    struct Mode { let name: String; let id: String }
    let workflows = [Mode(name: "Exact", id: "exact"), Mode(name: "Cleanup", id: "cleanup")]
    var selectedID = "exact"
    func select(_ id: String) { selectedID = id }
}
@main struct Probe {
    @MainActor static func main() {
        _ = NSApplication.shared
        guard let mark = NSImage(contentsOfFile: CommandLine.arguments[1]) else { fatalError("Brand asset missing") }
        precondition(mark.setName("QuibbleMark"))
        let controller = DictationController()
        let subject = MenuBarController()
        var opened = 0
        subject.install(controller: controller) { opened += 1 }
        guard let item = Mirror(reflecting: subject).children.first(where: { $0.label == "statusItem" })?.value as? NSStatusItem else { fatalError("No retained native status item") }
        precondition(item.isVisible && item.length == NSStatusItem.squareLength)
        precondition(item.button?.image?.isTemplate == true)
        precondition(item.button?.image?.size == NSSize(width: 18, height: 18))
        let menu = NSMenu()
        subject.menuNeedsUpdate(menu)
        precondition(menu.items.filter { !$0.isSeparatorItem }.map(\.title) == ["Transcribe File…", "History", "Settings…", "Microphone", "Mode", "Quit Quibble"])
        let microphones = menu.items[4].submenu!
        precondition(microphones.items[0].state == .on && microphones.items[2].state == .off)
        controller.audioInputs.selectedUID = "test"
        controller.workflows.selectedID = "cleanup"
        subject.menuNeedsUpdate(menu)
        precondition(menu.items[4].submenu!.items[2].state == .on)
        precondition(menu.items[5].submenu!.items[1].state == .on)
        controller.recording = true
        subject.menuNeedsUpdate(menu)
        // Native submenus validate items again when opened.
        menu.items[4].submenu!.update()
        menu.items[5].submenu!.update()
        precondition(!menu.items[0].isEnabled && menu.items[1].isEnabled && menu.items[2].isEnabled)
        precondition(menu.items[4].submenu!.items.allSatisfy { $0.isSeparatorItem || !$0.isEnabled })
        precondition(menu.items[5].submenu!.items.allSatisfy { !$0.isEnabled })
        let exact = menu.items[5].submenu!.items[0]
        _ = subject.perform(exact.action!, with: exact)
        precondition(controller.workflows.selectedID == "cleanup")
        let systemDefault = menu.items[4].submenu!.items[0]
        _ = subject.perform(systemDefault.action!, with: systemDefault)
        precondition(controller.audioInputs.selectedUID == "test")
        controller.recording = false
        _ = subject.perform(exact.action!, with: exact)
        _ = subject.perform(systemDefault.action!, with: systemDefault)
        precondition(controller.workflows.selectedID == "exact" && controller.audioInputs.selectedUID == nil)
        subject.menuNeedsUpdate(menu)
        // Exercise selectors against this isolated fixture, not the user's app.
        _ = subject.perform(menu.items[1].action!)
        precondition(subject.page == .history && opened == 1 && !subject.consumeImportRequest())
        _ = subject.perform(menu.items[2].action!)
        precondition(subject.page == .general && opened == 2)
        _ = subject.perform(menu.items[0].action!)
        precondition(subject.page == .home && opened == 3 && subject.consumeImportRequest() && !subject.consumeImportRequest())
        controller.audioInputs.selectedUID = "missing"
        subject.menuNeedsUpdate(menu)
        precondition(menu.items[4].submenu!.items.last!.title == "Selected microphone unavailable")
        precondition(menu.items[4].submenu!.items.last!.state == .on)
        NSStatusBar.system.removeStatusItem(item)
        print("PASS: retained template status item, requested menu, routing, selections, missing-device state, and busy guards")
    }
}
'''
with tempfile.TemporaryDirectory(prefix="quibble-menu-") as directory:
    directory = Path(directory)
    source = directory / "Probe.swift"
    source.write_text((ROOT / "App/MenuBarController.swift").read_text() + STUBS)
    executable = directory / "Probe"
    subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-parse-as-library", str(source), "-o", str(executable)], check=True)
    subprocess.run([str(executable), str(ROOT / "App/Resources/Branding.xcassets/QuibbleMark.imageset/quotation-marks.png")], check=True)
