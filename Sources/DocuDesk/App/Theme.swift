import AppKit
import DocuDeskCore
import SwiftUI

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }

    /// Resolves per appearance so every screen works in light and dark mode.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

enum Theme {
    static let accent = Color.dynamic(light: 0x1A6DF0, dark: 0x4C8DFF)
    static let accentSoft = Color.dynamic(light: 0xE9F1FE, dark: 0x1D2B45)
    static let canvas = Color.dynamic(light: 0xF4F6FA, dark: 0x15171C)
    static let sidebar = Color.dynamic(light: 0xFBFCFE, dark: 0x1A1D23)
    static let surface = Color.dynamic(light: 0xFFFFFF, dark: 0x21242B)
    static let surfaceMuted = Color.dynamic(light: 0xF7F8FB, dark: 0x262A32)
    static let border = Color.dynamic(light: 0xE6E9EF, dark: 0x30343D)
    static let text = Color.dynamic(light: 0x111827, dark: 0xF3F4F6)
    static let secondary = Color.dynamic(light: 0x6B7280, dark: 0xA0A7B4)
    static let tertiary = Color.dynamic(light: 0x9CA3AF, dark: 0x6B7280)
    static let success = Color.dynamic(light: 0x16A34A, dark: 0x4ADE80)
    static let warning = Color.dynamic(light: 0xD97706, dark: 0xFBBF24)
    static let danger = Color.dynamic(light: 0xDC2626, dark: 0xF87171)

    static let radius: CGFloat = 14
}

extension DocumentKind {
    var tint: Color {
        switch self {
        case .invoice: Color(hex: 0x2563EB)
        case .quotation: Color(hex: 0x16A34A)
        case .estimate: Color(hex: 0x7C3AED)
        case .proformaInvoice: Color(hex: 0x4F46E5)
        case .purchaseOrder: Color(hex: 0xEA580C)
        case .creditNote: Color(hex: 0xDC2626)
        case .deliveryChallan: Color(hex: 0xE11D48)
        case .receipt: Color(hex: 0x0D9488)
        case .proposal: Color(hex: 0x0891B2)
        case .agreement: Color(hex: 0x9333EA)
        case .letter: Color(hex: 0x475569)
        case .report: Color(hex: 0xCA8A04)
        case .custom: Color(hex: 0x0F766E)
        }
    }

    var icon: String {
        switch self {
        case .invoice: "doc.text.fill"
        case .quotation: "doc.plaintext.fill"
        case .estimate: "list.bullet.rectangle.portrait.fill"
        case .proformaInvoice: "doc.richtext.fill"
        case .purchaseOrder: "cart.fill"
        case .creditNote: "arrow.uturn.backward.square.fill"
        case .deliveryChallan: "truck.box.fill"
        case .receipt: "checkmark.seal.fill"
        case .proposal: "lightbulb.fill"
        case .agreement: "signature"
        case .letter: "envelope.fill"
        case .report: "chart.bar.doc.horizontal.fill"
        case .custom: "square.grid.2x2.fill"
        }
    }
}

extension DocumentStatus {
    var tint: Color {
        switch self {
        case .draft, .cancelled: Theme.secondary
        case .issued, .sent: Color(hex: 0x2563EB)
        case .accepted, .delivered, .paid, .signed: Color(hex: 0x16A34A)
        case .confirmed: Color(hex: 0x7C3AED)
        case .partiallyPaid: Color(hex: 0xD97706)
        case .declined, .overdue: Color(hex: 0xDC2626)
        }
    }
}

// MARK: - Building blocks

struct Card<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.border))
            .shadow(color: .black.opacity(0.03), radius: 8, y: 2)
    }
}

struct CardHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text)
                if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.secondary) }
            }
            Spacer()
            trailing
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct KindBadge: View {
    let kind: DocumentKind
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: kind.icon)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(kind.tint)
            .frame(width: size, height: size)
            .background(kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

struct StatusPill: View {
    let status: DocumentStatus

    var body: some View {
        Text(status.displayName)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(status.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(status.tint.opacity(0.12), in: Capsule())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(configuration.isPressed ? Theme.surfaceMuted : Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.border))
            .contentShape(Rectangle())
    }
}

struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 34

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.text)
            .frame(width: size, height: size)
            .background(configuration.isPressed ? Theme.surfaceMuted : Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.border))
            .contentShape(Rectangle())
    }
}

struct ChipButtonStyle: ButtonStyle {
    var selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
            .foregroundStyle(selected ? .white : Theme.text)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(selected ? Theme.accent : Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(selected ? .clear : Theme.border))
            .contentShape(Rectangle())
    }
}

/// Text field styled to match the cards.
struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.border))
    }
}

extension View {
    func fieldStyle() -> some View { modifier(FieldStyle()) }
}

struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.secondary)
            content
        }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 30)).foregroundStyle(Theme.tertiary)
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
            Text(message).font(.system(size: 12)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}

/// Plain text field for decimal values that keeps the user's typing intact while editing.
struct DecimalField: View {
    let placeholder: String
    @Binding var value: Decimal
    var alignment: TextAlignment = .trailing

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .multilineTextAlignment(alignment)
            .focused($focused)
            .onAppear { text = Self.format(value) }
            .onChange(of: text) { _, newValue in
                if let parsed = Decimal.parse(newValue) {
                    if parsed != value { value = parsed }
                } else if newValue.trimmingCharacters(in: .whitespaces).isEmpty, value != 0 {
                    value = 0
                }
            }
            .onChange(of: value) { _, newValue in
                if !focused { text = Self.format(newValue) }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { text = Self.format(value) }
            }
    }

    static func format(_ value: Decimal) -> String {
        value == 0 ? "0" : value.plainString
    }
}

/// Makes the hidden-title-bar window draggable from its background.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension Date {
    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
