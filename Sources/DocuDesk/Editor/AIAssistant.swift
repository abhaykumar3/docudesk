import DocuDeskCore
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Optional drafting help using Apple's on-device language model, so document text never
/// leaves the Mac. Hidden gracefully when Apple Intelligence isn't available.
@MainActor
final class AIAssistant: ObservableObject {
    static let shared = AIAssistant()

    enum Rewrite: String, CaseIterable, Identifiable {
        case improve = "Improve Writing"
        case formal = "Make More Formal"
        case friendly = "Make Friendlier"
        case shorter = "Make Shorter"
        case grammar = "Fix Spelling & Grammar"

        var id: String { rawValue }

        var instruction: String {
            switch self {
            case .improve: "Rewrite the text to be clearer and more professional. Keep the meaning and length roughly the same."
            case .formal: "Rewrite the text in a more formal business tone."
            case .friendly: "Rewrite the text in a warmer, friendlier tone while staying professional."
            case .shorter: "Rewrite the text to be noticeably shorter while keeping every important point."
            case .grammar: "Correct spelling, grammar and punctuation only. Do not change the wording otherwise."
            }
        }
    }

    enum AIError: LocalizedError {
        case unavailable(String)

        var errorDescription: String? {
            switch self {
            case let .unavailable(reason): reason
            }
        }
    }

    static let instructions = """
    You are the writing assistant inside DocuDesk, an offline business document app used by small businesses, \
    freelancers and agencies. Write clear, professional business text for the user to review and edit.
    Format output as plain text using only this markup: lines starting with "# " for a heading, "## " for a subheading, \
    "- " for bullet points, "1. " for numbered points, and **double asterisks** for bold. Separate paragraphs with new lines.
    Use at most two heading levels and only single-level bullet lists. Prefer short paragraphs and concise bullets.
    Never invent prices, amounts, budgets, dates, durations, names or statistics. Where a figure is needed, write a \
    placeholder in square brackets such as [Amount], [Date] or [Number of weeks].
    Keep any placeholders in double braces, such as {{client.name}}, exactly as they are.
    Do not give legal, tax or financial advice and do not claim that any wording is legally valid; produce draft wording only.
    Output only the requested text, with no introduction or closing remarks.
    """

    var availability: (available: Bool, reason: String) {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return (true, "")
            case let .unavailable(reason):
                switch reason {
                case .deviceNotEligible: return (false, "This Mac doesn’t support Apple Intelligence.")
                case .appleIntelligenceNotEnabled: return (false, "Turn on Apple Intelligence in System Settings to use AI drafting.")
                case .modelNotReady: return (false, "The on-device model is still downloading. Try again shortly.")
                @unknown default: return (false, "The on-device model isn’t available right now.")
                }
            }
        }
        #endif
        return (false, "AI drafting needs macOS 26 with Apple Intelligence.")
    }

    func respond(to prompt: String) async throws -> String {
        let status = availability
        guard status.available else { throw AIError.unavailable(status.reason) }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let session = LanguageModelSession(instructions: Self.instructions)
            let response = try await session.respond(to: prompt)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
        throw AIError.unavailable(status.reason)
    }

    func draft(request: String, document: DocumentRecord) async throws -> String {
        var context = "Document type: \(document.typeName)."
        if !document.title.isEmpty { context += " Title: \(document.title)." }
        if !document.customer.name.isEmpty { context += " Recipient: \(document.customer.name)." }
        context += " Sender: \(document.company.displayLegalName)."
        return try await respond(to: "\(context)\n\nWrite: \(request)")
    }

    func rewrite(_ text: String, _ style: Rewrite) async throws -> String {
        try await respond(to: "\(style.instruction)\n\nText:\n\(text)")
    }

    func summarize(_ text: String) async throws -> String {
        try await respond(to: "Write a short executive summary (3 to 5 bullet points) of this document:\n\n\(text.prefix(12_000))")
    }
}
