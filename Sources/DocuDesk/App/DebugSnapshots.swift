#if DEBUG
import AppKit
import DocuDeskCore

/// Debug-only: walks through screens and saves PNGs of the app window, for visual review.
///   DOCUDESK_SNAPSHOT_DIR=/tmp/shots DOCUDESK_SNAPSHOT_STEPS=dashboard,editor DocuDesk
extension AppModel {
    func runSnapshotScriptIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["DOCUDESK_SNAPSHOT_DIR"] else { return }
        let steps = (environment["DOCUDESK_SNAPSHOT_STEPS"] ?? "dashboard").split(separator: ",").map(String.init)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            for step in steps {
                if step.hasPrefix("scroll"), let offset = Double(step.dropFirst("scroll".count)) {
                    scrollMainContent(to: offset)
                } else if step.hasPrefix("editor") {
                    let index = Int(step.dropFirst("editor".count)) ?? 0
                    let documents = (try? store?.search(DocumentQuery())) ?? []
                    if documents.indices.contains(index) { openDocument(documents[index].id) }
                } else if let screen = Screen(rawValue: step) {
                    navigate(to: screen)
                }
                try? await Task.sleep(for: .seconds(3))
                snapshot(to: URL(fileURLWithPath: directory).appendingPathComponent("\(step).png"))
            }
            NSApp.terminate(nil)
        }
    }

    private func snapshot(to url: URL) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let view = window.contentView?.superview ?? window.contentView,
              let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: representation)
        if ProcessInfo.processInfo.environment["DOCUDESK_SNAPSHOT_TREE"] != nil { dumpScrollViews(view) }
        try? representation.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// Scrolls the tallest scroll view (the main form) so lower sections can be captured.
    private func scrollMainContent(to offset: Double) {
        guard let root = NSApp.windows.first(where: { $0.isVisible })?.contentView else { return }
        var scrollViews: [NSScrollView] = []
        func collect(_ view: NSView) {
            if let scroll = view as? NSScrollView { scrollViews.append(scroll) }
            view.subviews.forEach(collect)
        }
        collect(root)
        guard let target = scrollViews.max(by: { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }) else { return }
        target.contentView.scroll(to: NSPoint(x: 0, y: offset))
        target.reflectScrolledClipView(target.contentView)
    }

    private func dumpScrollViews(_ view: NSView, depth: Int = 0) {
        if let scroll = view as? NSScrollView {
            FileHandle.standardError.write("scroll frame=\(scroll.frame) doc=\(scroll.documentView?.frame ?? .zero) clip=\(scroll.contentView.bounds) hidden=\(scroll.isHidden) alpha=\(scroll.alphaValue)\n".data(using: .utf8)!)
        }
        for sub in view.subviews { dumpScrollViews(sub, depth: depth + 1) }
    }
}
#endif
