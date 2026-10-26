import DocuDeskCore
import SwiftUI

/// Chooses the starting content for a proposal, agreement, letter or report.
struct StarterPicker: View {
    let request: StarterRequest
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var starters: [DocumentStarter] {
        DocumentStarter.starters(for: request.kind) + [DocumentStarter.blank(for: request.kind)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                KindBadge(kind: request.kind, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("New \(request.kind.displayName)").font(.system(size: 19, weight: .bold))
                    Text("Pick a starting point. Everything stays editable, and client details fill in automatically.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.secondary)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(starters) { starter in
                    StarterTile(starter: starter) {
                        dismiss()
                        model.createDocument(request.kind, templateID: request.templateID, customer: request.customer, starter: starter)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 620)
    }
}

private struct StarterTile: View {
    let starter: DocumentStarter
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: starter.id.hasSuffix(".blank") ? "doc" : starter.kind.icon)
                    .font(.system(size: 15))
                    .foregroundStyle(starter.kind.tint)
                    .frame(width: 34, height: 34)
                    .background(starter.kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    Text(starter.name).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(starter.summary).font(.system(size: 11.5)).foregroundStyle(Theme.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
            .background(hovering ? Theme.accentSoft.opacity(0.6) : Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(hovering ? Theme.accent : Theme.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
