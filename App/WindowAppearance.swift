import AppKit
import SwiftUI

/// SwiftUI owns the native window surface on modern macOS, including its frame.
struct NativeWindowSurface: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            // The native split view supplies glass to navigation. A stable content
            // surface avoids tinting every page and label with the desktop behind it.
            content.containerBackground(Color(nsColor: .windowBackgroundColor), for: .window)
                .background(WindowAppearance())
        } else {
            content.background(WindowAppearance().ignoresSafeArea())
        }
    }
}

/// Configure native window controls without masking or rounding the hosting view.
struct WindowAppearance: NSViewRepresentable {
    final class MaterialView: NSVisualEffectView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            if #unavailable(macOS 15.0) {
                window.isOpaque = false
                window.backgroundColor = .clear
            }
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.toolbarStyle = .unified
            window.titlebarSeparatorStyle = .none
            window.collectionBehavior.remove(.fullScreenPrimary)
            window.collectionBehavior.insert(.fullScreenNone)
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isEnabled = false
            window.toolbar?.showsBaselineSeparator = false
        }
    }
    func makeNSView(context: Context) -> MaterialView {
        let view = MaterialView()
        if #available(macOS 15.0, *) { view.isHidden = true }
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: MaterialView, context: Context) {}
}
