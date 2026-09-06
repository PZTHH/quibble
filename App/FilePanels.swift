import AppKit

extension NSSavePanel {
    @MainActor func present() async -> NSApplication.ModalResponse {
        await withCheckedContinuation { continuation in
            let completion: (NSApplication.ModalResponse) -> Void = { continuation.resume(returning: $0) }
            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                beginSheetModal(for: window, completionHandler: completion)
            } else { begin(completionHandler: completion) }
        }
    }
}
