import AppKit
import DocuDeskCore
import PDFKit
import SwiftUI

/// Shows a PDF as floating paper pages. Pages render off the main thread and the previous
/// render stays on screen until the new one is ready, so live edits don't flicker.
struct PagePreview: View {
    let data: Data?
    @State private var pages: [NSImage] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ForEach(Array(pages.enumerated()), id: \.offset) { _, page in
                    Image(nsImage: page)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                }
            }
            .padding(14)
        }
        .overlay {
            if pages.isEmpty, data != nil { ProgressView() }
        }
        .task(id: data) {
            guard let data else {
                pages = []
                return
            }
            let rendered = await Task.detached(priority: .userInitiated) { Self.render(data) }.value
            if !Task.isCancelled { pages = rendered }
        }
    }

    nonisolated static func render(_ data: Data) -> [NSImage] {
        guard let document = PDFDocument(data: data) else { return [] }
        return (0..<document.pageCount).compactMap { index in
            guard let page = document.page(at: index) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            return page.thumbnail(of: CGSize(width: bounds.width * 2, height: bounds.height * 2), for: .mediaBox)
        }
    }
}

/// Renders template previews off the main thread and caches them per template and company.
@MainActor
final class ThumbnailCache: ObservableObject {
    static let shared = ThumbnailCache()

    @Published private(set) var images: [String: NSImage] = [:]
    private var pending: Set<String> = []

    func image(for template: TemplateDefinition, company: CompanyProfile?, logo: NSImage?) -> NSImage? {
        let key = "\(template.id)-\(template.kind.rawValue)-\(template.version)-\(template.theme.hashValue)-\(company?.updatedAt.timeIntervalSince1970 ?? 0)"
        if let image = images[key] { return image }
        guard !pending.contains(key) else { return nil }
        pending.insert(key)
        let document = SampleData.document(kind: template.kind, template: template, company: company)
        let theme = template.theme
        Task.detached(priority: .userInitiated) {
            let data = DocumentRenderer.pdfData(for: document, logo: logo, theme: theme)
            let image = PDFDocument(data: data)?.page(at: 0)?.thumbnail(of: CGSize(width: 420, height: 594), for: .mediaBox)
            await MainActor.run {
                self.pending.remove(key)
                if let image { self.images[key] = image }
            }
        }
        return nil
    }
}

struct TemplateThumbnail: View {
    let template: TemplateDefinition
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var cache = ThumbnailCache.shared

    var body: some View {
        let logo = model.store?.image(at: model.profile?.logoPath)
        ZStack {
            Rectangle().fill(Color.white)
            if let image = cache.image(for: template, company: model.profile, logo: logo) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .aspectRatio(210.0 / 297.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.border))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}

/// Renders any saved document for the dashboard's preview panel.
@MainActor
final class DocumentPreviewLoader: ObservableObject {
    @Published var data: Data?
    @Published var document: DocumentRecord?
    private var task: Task<Void, Never>?

    func load(_ id: UUID?, store: WorkspaceStore?) {
        task?.cancel()
        guard let id, let store, let document = try? store.loadDocument(id: id) else {
            self.document = nil
            data = nil
            return
        }
        self.document = document
        let logo = store.image(at: document.company.logoPath)
        let theme = store.theme(for: document)
        task = Task {
            let data = await Task.detached(priority: .userInitiated) { DocumentRenderer.pdfData(for: document, logo: logo, theme: theme) }.value
            if !Task.isCancelled { self.data = data }
        }
    }
}
