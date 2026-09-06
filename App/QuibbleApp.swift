import SwiftUI
import QuibbleInference

@main
enum QuibbleEntry {
    @MainActor static func main() async {
        let args = CommandLine.arguments
        if args.contains("--cleanup-completion-probe") {
            do {
                guard let index = args.firstIndex(of: "--models"), args.indices.contains(index + 1) else {
                    throw InferenceError.missingModel("Pass --models with a local model root")
                }
                let directory = URL(fileURLWithPath: args[index + 1]).appendingPathComponent("s1-mini")
                let inference = LocalInference()
                let sample = "please send the revised agenda to Morgan before our meeting tomorrow"
                var rejected = false
                do { _ = try await inference.benchmarkCleanup(sample, directory: directory, maxTokens: 1) }
                catch InferenceError.invalidRefinement { rejected = true }
                guard rejected else { throw InferenceError.invalidRefinement }
                let output = try await inference.benchmarkCleanup(sample, directory: directory, maxTokens: 128)
                guard output.localizedCaseInsensitiveContains("Morgan"), output.localizedCaseInsensitiveContains("agenda"),
                      output.localizedCaseInsensitiveContains("tomorrow") else { throw InferenceError.invalidRefinement }
                print("PASS: forced token exhaustion rejected; normal completed S1 output preserved the sample facts.")
            } catch { FileHandle.standardError.write(Data("Cleanup completion probe failed: \(error.localizedDescription)\n".utf8)); exit(1) }
            return
        }
        if args.contains("--audio-vocabulary-fixtures") {
            do { try await VocabularyBenchmark.runAudio(Array(args.dropFirst())) }
            catch { FileHandle.standardError.write(Data("Audio vocabulary benchmark failed: \(error)\n".utf8)); exit(1) }
            return
        }
        if args.contains("--s1-vocabulary-fixtures") {
            do { try await VocabularyBenchmark.runS1Prefixes(Array(args.dropFirst())) }
            catch { FileHandle.standardError.write(Data("S1 vocabulary benchmark failed: \(error.localizedDescription)\n".utf8)); exit(1) }
            return
        }
        if args.contains("--vocabulary-resolver-fixtures") {
            do { try await VocabularyBenchmark.runResolver(Array(args.dropFirst())) }
            catch { FileHandle.standardError.write(Data("Vocabulary benchmark failed: \(error.localizedDescription)\n".utf8)); exit(1) }
            return
        }
        if args.contains("--vocabulary-cpu-fixtures") {
            do { try VocabularyBenchmark.runCPU(Array(args.dropFirst())) }
            catch { FileHandle.standardError.write(Data("Vocabulary benchmark failed: \(error.localizedDescription)\n".utf8)); exit(1) }
            return
        }
        if args.contains("--vocabulary-fixtures") {
            do { try await VocabularyBenchmark.run(Array(args.dropFirst())) }
            catch { FileHandle.standardError.write(Data("Vocabulary benchmark failed: \(error.localizedDescription)\n".utf8)); exit(1) }
            return
        }
        if args.contains("--refine-fixtures") {
            do { try await RefinementBenchmark.run(Array(args.dropFirst())) }
            catch { FileHandle.standardError.write(Data("Refinement benchmark failed: \(error.localizedDescription)\n".utf8)); exit(1) }
            return
        }
        if args.contains("--benchmark") {
            do { try await BenchmarkRunner.run(arguments: Array(args.dropFirst())) }
            catch { FileHandle.standardError.write(Data("Benchmark failed: \(error.localizedDescription)\n".utf8)); exit(1) }
            return
        }
        QuibbleApp.main()
    }
}

@MainActor
final class QuibbleAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@MainActor
struct QuibbleApp: App {
    @NSApplicationDelegateAdaptor(QuibbleAppDelegate.self) private var appDelegate
    @StateObject private var controller = DictationController()
    @StateObject private var menuBar = MenuBarController()
    var body: some Scene {
        Window("Quibble", id: "main") {
            ContentView(controller: controller, menuBar: menuBar)
        }
        .defaultSize(width: 1040, height: 740)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}

enum QuibblePage: String, CaseIterable, Identifiable {
    case home = "Home", history = "History", general = "Settings", modes = "Modes", vocabulary = "Vocabulary", permissions = "Permissions", models = "Models library", timing = "Diagnostics", developer = "Developer"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .home: "house"; case .history: "clock.arrow.circlepath"; case .general: "slider.horizontal.3"; case .modes: "sparkles"; case .vocabulary: "character.book.closed"; case .permissions: "hand.raised"; case .models: "externaldrive"; case .timing: "stopwatch"; case .developer: "wrench.and.screwdriver" }
    }
}

@MainActor
struct ContentView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject var menuBar: MenuBarController
    @Environment(\.openWindow) private var openWindow
    private var page: QuibblePage? {
        get { menuBar.page }
        nonmutating set { menuBar.page = newValue }
    }
    @AppStorage("didFinishQuickTour.v1") private var didFinishTour = false
    @AppStorage("onboarding.completed.v1") private var didFinishSetup = false
    @AppStorage("onboarding.deferred.v1") private var didDeferSetup = false
    @State private var showingTour = false
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var hoveredPage: QuibblePage?
    @FocusState private var focusedPage: QuibblePage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var navigationSelection
    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            VStack(alignment: .leading, spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            navigationGroup(nil, pages: [.home, .history])
                            navigationGroup("Dictation", pages: [.modes, .vocabulary, .models])
                            navigationGroup("Preferences", pages: [.general, .permissions])
                            navigationGroup("Advanced", pages: [.developer, .timing])
                        }
                        .padding(.horizontal, 12).padding(.top, 16).padding(.bottom, 20)
                    }.scrollIndicators(.hidden)
                        .onChange(of: focusedPage) { _, item in
                            if let item { proxy.scrollTo(item) }
                        }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Label(controller.engine.isOnline ? "Online transcription" : "On-device dictation", systemImage: controller.engine.isOnline ? "cloud" : "lock.shield.fill").font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 22).padding(.bottom, 20)
            }
            .navigationSplitViewColumnWidth(min: 205, ideal: 215, max: 250)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if page == .home && !didFinishSetup && !didFinishTour {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles").foregroundStyle(AppPalette.speech)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Make yourself at home").font(.headline)
                                Text("Models, shortcuts, and your first dictation.").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Resume setup") { showingTour = true }.disabled(controller.recording || controller.processing)
                        }.padding(18).background(AppPalette.speech.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                    }
                    switch page ?? .home {
                    case .home: HomeView(controller: controller) { page = $0 }
                    case .history: HistoryView(history: controller.history)
                    case .general: SettingsView(controller: controller)
                    case .modes: WorkflowView(controller: controller)
                    case .vocabulary: VocabularyView(controller: controller)
                    case .permissions: permissions
                    case .models: ModelLibraryView(controller: controller)
                    case .timing: DiagnosticsView(controller: controller)
                    case .developer: DeveloperView(controller: controller)
                    }
                }
                .id(page)
                .transition(.opacity)
                .padding(28).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingTour = true } label: { Image(systemName: "questionmark.circle") }
                    .help("Setup guide").accessibilityLabel("Setup guide")
                    .disabled(controller.recording || controller.processing)
            }
        }
        .modifier(NativeWindowSurface())
        .tint(AppPalette.speech)
        .frame(minWidth: 850, minHeight: 650)
        .onAppear {
            menuBar.install(controller: controller) { openWindow(id: "main") }
            if menuBar.requestID == 0 && !didFinishTour && !didFinishSetup && !didDeferSetup && !controller.recording && !controller.processing { showingTour = true }
        }
        .task(id: menuBar.requestID) {
            guard menuBar.requestID > 0 else { return }
            if showingTour {
                // Present the chooser only after the guide's sheet has dismissed.
                showingTour = false
            } else if menuBar.consumeImportRequest() {
                controller.importAudio()
            }
        }
        .sheet(isPresented: $showingTour, onDismiss: {
            didDeferSetup = true
            if menuBar.consumeImportRequest() { controller.importAudio() }
        }) {
            QuickTourView(controller: controller) { completed, destination in
                if completed { didFinishSetup = true }
                didDeferSetup = true
                showingTour = false
                if let destination { page = destination }
            }
        }
    }

    private func navigationGroup(_ title: String?, pages: [QuibblePage]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(title).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary).padding(.horizontal, 10).padding(.bottom, 4)
            }
            ForEach(pages) { item in navigationRow(item) }
        }
    }

    private func navigationRow(_ item: QuibblePage) -> some View {
        let selected = page == item
        return Button {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { page = item }
            focusedPage = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(navigationColor(item))
                    .frame(width: 28, height: 28)
                    .background(navigationColor(item).opacity(selected ? 0.22 : 0.12), in: RoundedRectangle(cornerRadius: 8))
                Text(item.rawValue).font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
                Spacer(minLength: 0)
                if selected {
                    Circle().fill(AppPalette.speech).frame(width: 5, height: 5).accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 12).fill(AppPalette.speech.opacity(0.12))
                        .matchedGeometryEffect(id: "sidebar-selection", in: navigationSelection)
                } else if hoveredPage == item || focusedPage == item {
                    RoundedRectangle(cornerRadius: 12).fill(.primary.opacity(focusedPage == item ? 0.08 : 0.045))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(SidebarPressStyle())
        .focusable()
        .focused($focusedPage, equals: item)
        .focusEffectDisabled()
        .id(item)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { hoveredPage = hovering ? item : nil }
        }
        .accessibilityIdentifier("navigation." + item.id)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .onMoveCommand { direction in
            let order: [QuibblePage] = [.home, .history, .modes, .vocabulary, .models, .general, .permissions, .developer, .timing]
            guard let index = order.firstIndex(of: item) else { return }
            let next = direction == .down ? index + 1 : direction == .up ? index - 1 : index
            if order.indices.contains(next) { page = order[next]; focusedPage = order[next] }
        }
    }
    private func navigationColor(_ item: QuibblePage) -> Color {
        switch item {
        case .vocabulary: AppPalette.vocabulary
        case .modes: AppPalette.instructions
        case .home, .models: AppPalette.speech
        default: .secondary
        }
    }

    private var permissions: some View {
        Group {
            title("Permissions", subtitle: "Give Quibble access only to what dictation needs.")
            permissionRow("Microphone", detail: "Record while you dictate.", allowed: controller.microphoneAllowed, action: controller.requestMicrophone)
            permissionRow("Accessibility", detail: "Use the global shortcut, insert text, and detect corrections in supported fields.", allowed: controller.accessibilityAllowed, action: controller.requestAccessibility)
            Button("Refresh status") { controller.refreshPermissions() }
            DisclosureGroup("Privacy & updates") {
                Text("Quibble keeps the same app identity across updates so existing permissions can be retained. No screen recording access is requested. Temporary audio is removed after processing or cancellation.")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }
        }
    }

    private func title(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.largeTitle.weight(.bold))
            Text(subtitle).foregroundStyle(.secondary)
        }
    }
    private func permissionRow(_ title: String, detail: String, allowed: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: allowed ? "checkmark.circle.fill" : "circle").foregroundStyle(allowed ? .green : .secondary)
            VStack(alignment: .leading, spacing: 6) { Text(title).font(.headline); Text(detail).font(.callout).foregroundStyle(.secondary) }
            Spacer()
            if allowed { Text("Allowed").foregroundStyle(.secondary) } else { Button("Allow…", action: action) }
        }.quibbleCard()
    }
}

private struct SidebarPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
