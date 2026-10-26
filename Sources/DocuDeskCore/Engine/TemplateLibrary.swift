import Foundation

public enum TemplateStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case minimal
    case corporate
    case modern
    case classic
    case elegant

    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }
}

/// sRGB colour stored as `#RRGGBB` in JSON.
public struct RGBColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    public init(red: Double, green: Double, blue: Double) {
        self.red = red.clamped01
        self.green = green.clamped01
        self.blue = blue.clamped01
    }

    public init?(hexString: String) {
        let digits = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(hex: value)
    }

    public var hexString: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let color = RGBColor(hexString: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid colour '\(text)'")
        }
        self = color
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hexString)
    }
}

private extension Double {
    var clamped01: Double { Swift.min(Swift.max(self, 0), 1) }
}

public enum HeaderLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Full-width colour band with the company and title inside it.
    case band
    /// Logo and company on the left, large title on the right.
    case left
    /// Everything centred, letterhead style.
    case centered
    /// Company left, title right, divided by a thin accent rule.
    case split

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .band: "Colour band"
        case .left: "Logo left, title right"
        case .centered: "Centred letterhead"
        case .split: "Split with rule"
        }
    }
}

public enum TableStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case minimal
    case striped
    case lined
    case boxed

    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }
}

public enum LayoutDensity: String, Codable, CaseIterable, Identifiable, Sendable, DefaultInitializable {
    case compact
    case normal
    case spacious

    public init() { self = .normal }
    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }
}

public enum LogoSize: String, Codable, CaseIterable, Identifiable, Sendable, DefaultInitializable {
    case small
    case medium
    case large

    public init() { self = .medium }
    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }

    var factor: CGFloat {
        switch self {
        case .small: 0.7
        case .medium: 1
        case .large: 1.45
        }
    }
}

/// Section keys used by `TemplateTheme.sectionOrder`.
public enum NoteSection: String, CaseIterable, Identifiable, Sendable {
    case payment
    case notes
    case terms

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .payment: "Payment details"
        case .notes: "Notes"
        case .terms: "Terms & conditions"
        }
    }
}

/// Everything that controls how a document looks. Saved inside custom templates and inside
/// issued documents (as a snapshot), so it must stay Codable and backwards compatible.
public struct TemplateTheme: Codable, Hashable, Sendable {
    public var accent: RGBColor
    public var ink: RGBColor
    public var muted: RGBColor
    public var tint: RGBColor
    public var headingFont: String
    public var bodyFont: String
    public var bodyBoldFont: String
    public var header: HeaderLayout
    public var table: TableStyle
    public var uppercaseTitle: Bool
    @Defaulted public var hideAmountInWords: Bool = false
    @Defaulted public var hideSignature: Bool = false
    @Defaulted public var hideHSN: Bool = false
    /// Extra line printed in every page footer, e.g. "Subject to Pune jurisdiction".
    @Defaulted public var footerNote: String = ""
    @Defaulted public var density = LayoutDensity()
    @Defaulted public var logoSize = LogoSize()
    @Defaulted public var hideItemNumbers: Bool = false
    @Defaulted public var hideTaxColumn: Bool = false
    /// Replaces "Item & Description" in the items table header when set.
    @Defaulted public var itemColumnTitle: String = ""
    /// Faint diagonal text on every page, e.g. "COPY" or "DUPLICATE".
    @Defaulted public var watermark: String = ""
    /// Order of the payment/notes/terms sections (`NoteSection` raw values); empty means default.
    @Defaulted public var sectionOrder: [String] = []
    /// Prints a UPI QR code for the balance due on unpaid INR invoices.
    @Defaulted public var showPaymentQR: Bool = false

    public var orderedSections: [NoteSection] {
        let chosen = sectionOrder.compactMap(NoteSection.init(rawValue:))
        return chosen + NoteSection.allCases.filter { !chosen.contains($0) }
    }

    public init(accent: RGBColor, ink: RGBColor, muted: RGBColor, tint: RGBColor, headingFont: String, bodyFont: String,
                bodyBoldFont: String, header: HeaderLayout, table: TableStyle, uppercaseTitle: Bool) {
        self.accent = accent
        self.ink = ink
        self.muted = muted
        self.tint = tint
        self.headingFont = headingFont
        self.bodyFont = bodyFont
        self.bodyBoldFont = bodyBoldFont
        self.header = header
        self.table = table
        self.uppercaseTitle = uppercaseTitle
    }
}

/// Font combinations offered in the template editor. Names are PostScript names available on macOS.
public struct FontPairing: Identifiable, Hashable, Sendable {
    public let name: String
    public let heading: String
    public let body: String
    public let bold: String

    public var id: String { name }

    public static let all: [FontPairing] = [
        FontPairing(name: "Helvetica Neue", heading: "HelveticaNeue-Bold", body: "HelveticaNeue", bold: "HelveticaNeue-Medium"),
        FontPairing(name: "Helvetica Neue Light", heading: "HelveticaNeue-Light", body: "HelveticaNeue", bold: "HelveticaNeue-Medium"),
        FontPairing(name: "Avenir Next", heading: "AvenirNext-DemiBold", body: "AvenirNext-Regular", bold: "AvenirNext-DemiBold"),
        FontPairing(name: "Gill Sans", heading: "GillSans-SemiBold", body: "GillSans", bold: "GillSans-SemiBold"),
        FontPairing(name: "Optima", heading: "Optima-Bold", body: "Optima-Regular", bold: "Optima-Bold"),
        FontPairing(name: "Georgia", heading: "Georgia-Bold", body: "Georgia", bold: "Georgia-Bold"),
        FontPairing(name: "Palatino", heading: "Palatino-Bold", body: "Palatino-Roman", bold: "Palatino-Bold"),
        FontPairing(name: "Baskerville", heading: "Baskerville-SemiBold", body: "Baskerville", bold: "Baskerville-SemiBold"),
        FontPairing(name: "Didot & Baskerville", heading: "Didot", body: "Baskerville", bold: "Baskerville-SemiBold"),
    ]

    public static func matching(_ theme: TemplateTheme) -> FontPairing? {
        all.first { $0.heading == theme.headingFont && $0.body == theme.bodyFont }
    }
}

public struct TemplateVersion: Codable, Hashable, Sendable {
    public var version: Int
    public var theme: TemplateTheme
    public var savedAt: Date
}

/// A user-made style based on a built-in one. It applies to every document type and keeps every
/// previous version, so documents can always be matched to the version they used.
public struct CustomTemplate: Codable, Identifiable, Hashable, Sendable {
    public static let idPrefix = "custom."

    public var id: UUID
    public var name: String
    public var baseStyle: TemplateStyle
    public var theme: TemplateTheme
    public var version: Int
    public var history: [TemplateVersion]
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, baseStyle: TemplateStyle, theme: TemplateTheme? = nil, now: Date = Date()) {
        self.id = id
        self.name = name
        self.baseStyle = baseStyle
        self.theme = theme ?? TemplateLibrary.theme(for: baseStyle)
        version = 1
        history = []
        createdAt = now
        updatedAt = now
    }

    public var templateID: String { Self.idPrefix + id.uuidString }

    public static func id(from templateID: String) -> UUID? {
        guard templateID.hasPrefix(idPrefix) else { return nil }
        return UUID(uuidString: String(templateID.dropFirst(idPrefix.count)))
    }

    public func theme(forVersion requested: Int) -> TemplateTheme {
        requested == version ? theme : history.first { $0.version == requested }?.theme ?? theme
    }

    public func definition(for kind: DocumentKind) -> TemplateDefinition {
        TemplateDefinition(id: templateID, kind: kind, style: baseStyle, version: version, name: name,
                           summary: "Custom template based on \(baseStyle.displayName)", tags: ["Custom", baseStyle.displayName], theme: theme)
    }
}

public struct TemplateDefinition: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: DocumentKind
    public let style: TemplateStyle
    public let version: Int
    public let name: String
    public let summary: String
    public let tags: [String]
    public let theme: TemplateTheme
}

/// Built-in templates. Each document stores `templateID` + `templateVersion`; bump `version`
/// whenever a template's rendering changes in a way that would alter existing documents.
public enum TemplateLibrary {
    public static let all: [TemplateDefinition] = DocumentKind.allCases.flatMap { kind in
        TemplateStyle.allCases.map { make(kind: kind, style: $0) }
    }

    public static func template(id: String) -> TemplateDefinition? {
        all.first { $0.id == id }
    }

    /// Resolves a document's template, falling back to the kind's default if it no longer exists.
    public static func resolve(id: String, kind: DocumentKind) -> (template: TemplateDefinition, isFallback: Bool) {
        if let found = template(id: id) { return (found, false) }
        return (defaultTemplate(for: kind, style: .modern), true)
    }

    public static func templates(for kind: DocumentKind) -> [TemplateDefinition] {
        all.filter { $0.kind == kind }
    }

    public static func defaultTemplate(for kind: DocumentKind, style: TemplateStyle) -> TemplateDefinition {
        template(id: "\(kind.rawValue).\(style.rawValue)") ?? make(kind: kind, style: style)
    }

    public static func theme(for style: TemplateStyle) -> TemplateTheme {
        switch style {
        case .minimal:
            TemplateTheme(accent: RGBColor(hex: 0x1F2328), ink: RGBColor(hex: 0x1F2328), muted: RGBColor(hex: 0x6E7781), tint: RGBColor(hex: 0xF6F8FA),
                          headingFont: "HelveticaNeue-Light", bodyFont: "HelveticaNeue", bodyBoldFont: "HelveticaNeue-Medium",
                          header: .left, table: .minimal, uppercaseTitle: true)
        case .corporate:
            TemplateTheme(accent: RGBColor(hex: 0x1F3A5F), ink: RGBColor(hex: 0x1B1F24), muted: RGBColor(hex: 0x5B6573), tint: RGBColor(hex: 0xEEF2F7),
                          headingFont: "HelveticaNeue-Bold", bodyFont: "HelveticaNeue", bodyBoldFont: "HelveticaNeue-Bold",
                          header: .band, table: .striped, uppercaseTitle: true)
        case .modern:
            TemplateTheme(accent: RGBColor(hex: 0x0F766E), ink: RGBColor(hex: 0x111827), muted: RGBColor(hex: 0x6B7280), tint: RGBColor(hex: 0xECFDF8),
                          headingFont: "AvenirNext-DemiBold", bodyFont: "AvenirNext-Regular", bodyBoldFont: "AvenirNext-DemiBold",
                          header: .split, table: .striped, uppercaseTitle: false)
        case .classic:
            TemplateTheme(accent: RGBColor(hex: 0x7A1F2B), ink: RGBColor(hex: 0x1A1A1A), muted: RGBColor(hex: 0x555555), tint: RGBColor(hex: 0xF4F1EC),
                          headingFont: "Georgia-Bold", bodyFont: "Georgia", bodyBoldFont: "Georgia-Bold",
                          header: .centered, table: .boxed, uppercaseTitle: true)
        case .elegant:
            TemplateTheme(accent: RGBColor(hex: 0x9A7432), ink: RGBColor(hex: 0x22201C), muted: RGBColor(hex: 0x6F675C), tint: RGBColor(hex: 0xFAF6EE),
                          headingFont: "Didot", bodyFont: "Baskerville", bodyBoldFont: "Baskerville-SemiBold",
                          header: .split, table: .lined, uppercaseTitle: false)
        }
    }

    private static func make(kind: DocumentKind, style: TemplateStyle) -> TemplateDefinition {
        let summaries: [TemplateStyle: String] = [
            .minimal: "Quiet black-and-white layout with generous whitespace.",
            .corporate: "Navy header band and striped table for established businesses.",
            .modern: "Teal accents, rounded type and a clean split header.",
            .classic: "Centred letterhead, serif type and a fully ruled table.",
            .elegant: "Didot headings, gold rules and refined spacing.",
        ]
        let industries: [TemplateStyle: [String]] = [
            .minimal: ["Freelance", "Design"],
            .corporate: ["Agency", "Consulting", "Enterprise"],
            .modern: ["Tech", "Startup", "Services"],
            .classic: ["Trading", "Manufacturing", "Professional"],
            .elegant: ["Boutique", "Events", "Hospitality"],
        ]
        return TemplateDefinition(
            id: "\(kind.rawValue).\(style.rawValue)",
            kind: kind,
            style: style,
            version: 1,
            name: "\(style.displayName) \(kind.displayName)",
            summary: summaries[style] ?? "",
            tags: [kind.displayName, style.displayName] + (industries[style] ?? []),
            theme: theme(for: style)
        )
    }
}
