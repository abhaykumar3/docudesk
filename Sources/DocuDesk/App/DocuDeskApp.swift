import AppKit
import DocuDeskCore
import SwiftUI

@main
struct DocuDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        Window("DocuDesk", id: "main") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1180, minHeight: 720)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
                .onAppear { AppDelegate.model = model }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1500, height: 940)
        .commands { AppCommands(model: model) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM executable rather than from the .app bundle.
        NSApp.setActivationPolicy(.regular)
        if Bundle.main.bundleIdentifier == nil, let icon = BrandMark.appIconImage(side: 512) {
            NSApp.applicationIconImage = NSImage(cgImage: icon, size: NSSize(width: 512, height: 512))
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppDelegate.model?.activeEditor?.flushPendingSave()
        }
    }
}

struct AppCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Invoice") { model.createDocument(.invoice) }
                .keyboardShortcut("n")
                .disabled(model.phase != .ready)
            Menu("New") {
                ForEach(DocumentKind.builtIn) { kind in
                    Button(kind.displayName) { model.createDocument(kind) }
                }
            }
            .disabled(model.phase != .ready)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { model.activeEditor?.saveNow() }
                .keyboardShortcut("s")
                .disabled(model.activeEditor == nil)
            Button("Export PDF…") { model.activeEditor?.exportPDF(choosingDestination: true) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model.activeEditor == nil)
        }
        CommandGroup(replacing: .printItem) {
            Button("Print…") { model.activeEditor?.print() }
                .keyboardShortcut("p")
                .disabled(model.activeEditor == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Search Documents") { model.focusSearch() }
                .keyboardShortcut("k")
                .disabled(model.phase != .ready)
        }
        CommandMenu("Go") {
            ForEach(Array(Screen.allCases.enumerated()), id: \.element) { index, screen in
                Button(screen.title) { model.navigate(to: screen) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command])
            }
        }
    }
}
