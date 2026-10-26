import Foundation

/// Minimal SpreadsheetML (.xlsx) writer: typed cells, money and date formats, a bold frozen
/// header row and column widths. Strings are written inline, so no shared-string table is needed.
public enum XLSXWriter {
    public enum Cell: Hashable, Sendable {
        case text(String)
        case number(Decimal)
        case money(Decimal)
        case date(CalendarDate)
        case empty
    }

    public struct Column: Sendable {
        public var title: String
        public var width: Double

        public init(_ title: String, width: Double = 16) {
            self.title = title
            self.width = width
        }
    }

    public struct Sheet: Sendable {
        public var name: String
        public var columns: [Column]
        public var rows: [[Cell]]

        public init(name: String, columns: [Column], rows: [[Cell]]) {
            self.name = name
            self.columns = columns
            self.rows = rows
        }
    }

    public static func write(_ sheets: [Sheet], to url: URL) throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("DocuDesk-Xlsx-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        for folder in ["_rels", "xl/_rels", "xl/worksheets", "docProps"] {
            try fileManager.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        func put(_ path: String, _ text: String) throws {
            try Data(text.utf8).write(to: root.appendingPathComponent(path))
        }
        let names = uniqueSheetNames(sheets.map(\.name))
        try put("[Content_Types].xml", contentTypes(count: sheets.count))
        try put("_rels/.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>\
        </Relationships>
        """)
        try put("xl/workbook.xml", workbook(names))
        try put("xl/_rels/workbook.xml.rels", workbookRelationships(count: sheets.count))
        try put("xl/styles.xml", styles)
        for (index, sheet) in sheets.enumerated() {
            try put("xl/worksheets/sheet\(index + 1).xml", worksheet(sheet))
        }
        try Packager.zip(directory: root, to: url)
    }

    // MARK: Parts

    static func escape(_ text: String) -> String {
        DocxWriter.escape(text)
    }

    /// Excel limits sheet names to 31 characters and forbids `[]:*?/\`.
    static func uniqueSheetNames(_ names: [String]) -> [String] {
        var used = Set<String>()
        return names.map { name in
            let cleaned = String(name.filter { !"[]:*?/\\".contains($0) }.prefix(28)).trimmingCharacters(in: .whitespaces)
            var candidate = cleaned.isEmpty ? "Sheet" : cleaned
            var counter = 2
            while used.contains(candidate.lowercased()) {
                candidate = "\(cleaned.prefix(25)) \(counter)"
                counter += 1
            }
            used.insert(candidate.lowercased())
            return candidate
        }
    }

    static func columnLetter(_ index: Int) -> String {
        var value = index + 1
        var letters = ""
        while value > 0 {
            let remainder = (value - 1) % 26
            letters = String(UnicodeScalar(65 + remainder)!) + letters
            value = (value - 1) / 26
        }
        return letters
    }

    /// Days since 1899-12-30, Excel's date epoch.
    static func serial(_ date: CalendarDate) -> Int {
        var components = DateComponents()
        components.year = 1899
        components.month = 12
        components.day = 30
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let epoch = calendar.date(from: components) else { return 0 }
        var target = DateComponents()
        target.year = date.year
        target.month = date.month
        target.day = date.day
        guard let day = calendar.date(from: target) else { return 0 }
        return calendar.dateComponents([.day], from: epoch, to: day).day ?? 0
    }

    private static func worksheet(_ sheet: Sheet) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
        <sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>\
        <cols>
        """
        for (index, column) in sheet.columns.enumerated() {
            xml += "<col min=\"\(index + 1)\" max=\"\(index + 1)\" width=\"\(column.width)\" customWidth=\"1\"/>"
        }
        xml += "</cols><sheetData><row r=\"1\">"
        for (index, column) in sheet.columns.enumerated() {
            xml += "<c r=\"\(columnLetter(index))1\" t=\"inlineStr\" s=\"1\"><is><t>\(escape(column.title))</t></is></c>"
        }
        xml += "</row>"
        for (rowIndex, row) in sheet.rows.enumerated() {
            let r = rowIndex + 2
            xml += "<row r=\"\(r)\">"
            for (index, cell) in row.enumerated() {
                let ref = "\(columnLetter(index))\(r)"
                switch cell {
                case let .text(value):
                    xml += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escape(value))</t></is></c>"
                case let .number(value):
                    xml += "<c r=\"\(ref)\"><v>\(value.plainString)</v></c>"
                case let .money(value):
                    xml += "<c r=\"\(ref)\" s=\"2\"><v>\(value.rounded(2).plainString)</v></c>"
                case let .date(value):
                    xml += "<c r=\"\(ref)\" s=\"3\"><v>\(serial(value))</v></c>"
                case .empty:
                    continue
                }
            }
            xml += "</row>"
        }
        let lastColumn = columnLetter(max(sheet.columns.count - 1, 0))
        xml += "</sheetData><autoFilter ref=\"A1:\(lastColumn)\(max(sheet.rows.count + 1, 1))\"/></worksheet>"
        return xml
    }

    private static func workbook(_ names: [String]) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>
        """
        for (index, name) in names.enumerated() {
            xml += "<sheet name=\"\(escape(name))\" sheetId=\"\(index + 1)\" r:id=\"rId\(index + 1)\"/>"
        }
        return xml + "</sheets></workbook>"
    }

    private static func workbookRelationships(count: Int) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        """
        for index in 1...max(count, 1) {
            xml += "<Relationship Id=\"rId\(index)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(index).xml\"/>"
        }
        xml += "<Relationship Id=\"rIdStyles\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
        return xml + "</Relationships>"
    }

    private static func contentTypes(count: Int) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
        <Default Extension="xml" ContentType="application/xml"/>\
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        """
        for index in 1...max(count, 1) {
            xml += "<Override PartName=\"/xl/worksheets/sheet\(index).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        return xml + "</Types>"
    }

    /// Cell styles: 0 default, 1 bold header, 2 money (#,##0.00), 3 date (dd mmm yyyy).
    private static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
    <numFmts count="2"><numFmt numFmtId="164" formatCode="#,##0.00"/><numFmt numFmtId="165" formatCode="dd mmm yyyy"/></numFmts>\
    <fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>\
    <fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>\
    <fill><patternFill patternType="solid"><fgColor rgb="FFE9F1FE"/><bgColor indexed="64"/></patternFill></fill></fills>\
    <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>\
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>\
    <cellXfs count="4"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>\
    <xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>\
    <xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>\
    <xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs>\
    <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>
    """
}

/// Zips a folder's contents (not the folder itself) with the system `zip` tool.
enum Packager {
    static func zip(directory: URL, to url: URL) throws {
        let fileManager = FileManager.default
        let temporary = fileManager.temporaryDirectory.appendingPathComponent("DocuDesk-\(UUID().uuidString).zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = directory
        process.arguments = ["-X", "-r", "-q", temporary.path, "."]
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DocxExporter.ExportError.zipFailed(String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        }
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
        try fileManager.moveItem(at: temporary, to: url)
    }
}
