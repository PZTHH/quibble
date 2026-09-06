// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Quibble",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "QuibbleCore", targets: ["QuibbleCore"]),
    ],
    targets: [
        .target(name: "QuibbleCore"),
        .target(name: "QuibbleVocabulary", dependencies: ["QuibbleCore"], path: "App", exclude: ["MenuBarController.swift", "AudioInputDevices.swift", "MicrophoneRecorder.swift", "ShortcutConflictMonitor.swift", "HUDSpectrumMonitor.swift", "CloudSpeechConnection.swift", "CloudSpeechView.swift", "SettingsView.swift", "ShortcutEditor.swift", "ModelCapabilities.swift", "ModelIcon.swift", "ApplicationIcon.swift", "DiagnosticsView.swift", "QuickTourView.swift", "WorkflowView.swift", "DeveloperView.swift", "WindowAppearance.swift", "HomeView.swift", "HistoryView.swift", "BenchmarkRunner.swift", "DictationController.swift", "DictationFeedback.swift", "FilePanels.swift", "GlobalShortcut.swift", "ModelLibrary.swift", "ModelLibraryView.swift", "QuibbleApp.swift", "RefinementBenchmark.swift", "Resources", "TargetApplication.swift", "VocabularyBenchmark.swift", "VocabularyView.swift"], sources: ["VocabularyStore.swift", "VocabularySpelling.swift"]),
        .testTarget(name: "QuibbleVocabularyTests", dependencies: ["QuibbleVocabulary", "QuibbleCore"]),

        .testTarget(name: "QuibbleCoreTests", dependencies: ["QuibbleCore"], resources: [.copy("Fixtures/speech-presence.aiff"), .copy("Fixtures/speech-short-yes.wav"), .copy("Fixtures/speech-short-um.wav")]),
        .target(name: "QuibbleInsertion", path: "App", exclude: ["MenuBarController.swift", "AudioInputDevices.swift", "MicrophoneRecorder.swift", "ShortcutConflictMonitor.swift", "HUDSpectrumMonitor.swift", "CloudSpeechConnection.swift", "CloudSpeechView.swift", "SettingsView.swift", "ShortcutEditor.swift", "ModelCapabilities.swift", "ModelIcon.swift", "ApplicationIcon.swift", "DiagnosticsView.swift", "QuickTourView.swift", "WorkflowView.swift", "DeveloperView.swift", "WindowAppearance.swift", "HomeView.swift", "HistoryView.swift", "BenchmarkRunner.swift", "DictationController.swift", "DictationFeedback.swift", "FilePanels.swift", "GlobalShortcut.swift", "ModelLibrary.swift", "ModelLibraryView.swift", "QuibbleApp.swift", "RefinementBenchmark.swift", "Resources", "VocabularyStore.swift", "VocabularyView.swift", "VocabularyBenchmark.swift", "VocabularySpelling.swift"], sources: ["TargetApplication.swift"]),
        .testTarget(name: "QuibbleInsertionTests", dependencies: ["QuibbleInsertion"]),
    ]
)
