import Foundation

public struct LineTotal: Codable, Hashable, Sendable {
    public var itemID: UUID
    /// Quantity × unit price.
    @DecimalString public var gross: Decimal = 0
    @DecimalString public var lineDiscount: Decimal = 0
    /// Gross less line discount: the amount shown on the line.
    @DecimalString public var net: Decimal = 0
    /// Share of the document-level discount allocated to this line.
    @DecimalString public var allocatedDiscount: Decimal = 0
    @DecimalString public var taxable: Decimal = 0
    @DecimalString public var taxRate: Decimal = 0

    public init(itemID: UUID) {
        self.itemID = itemID
    }
}

public struct TaxLine: Codable, Hashable, Sendable {
    public var label: String
    @DecimalString public var rate: Decimal = 0
    @DecimalString public var taxable: Decimal = 0
    @DecimalString public var amount: Decimal = 0

    public init(label: String, rate: Decimal, taxable: Decimal, amount: Decimal) {
        self.label = label
        self.rate = rate
        self.taxable = taxable
        self.amount = amount
    }
}

public struct DocumentTotals: Codable, Hashable, Sendable {
    public var lines: [LineTotal] = []
    @DecimalString public var subtotal: Decimal = 0
    @DecimalString public var lineDiscountTotal: Decimal = 0
    @DecimalString public var documentDiscount: Decimal = 0
    @DecimalString public var taxableAmount: Decimal = 0
    public var taxLines: [TaxLine] = []
    @DecimalString public var taxTotal: Decimal = 0
    @DecimalString public var shipping: Decimal = 0
    @DecimalString public var adjustment: Decimal = 0
    @DecimalString public var roundOff: Decimal = 0
    @DecimalString public var grandTotal: Decimal = 0
    @DecimalString public var advancePaid: Decimal = 0
    @DecimalString public var amountPaid: Decimal = 0
    @DecimalString public var balanceDue: Decimal = 0
    public var amountInWords: String = ""

    public init() {}

    public func line(for id: UUID) -> LineTotal? {
        lines.first { $0.itemID == id }
    }
}

/// Deterministic money arithmetic. All values are `Decimal`, rounded half-up to two places at
/// well-defined points so the PDF, the index and the tests always agree.
public enum DocumentCalculator {
    public static func totals(for document: DocumentRecord) -> DocumentTotals {
        var totals = DocumentTotals()

        if document.kind == .receipt {
            let amount = (document.receipt?.amountReceived ?? 0).rounded(2)
            totals.subtotal = amount
            totals.taxableAmount = amount
            totals.grandTotal = amount
            totals.amountInWords = AmountInWords.words(for: amount, currency: document.currency)
            return totals
        }

        let applyTax = document.taxSplit != .none

        // 1. Per-line gross, line discount and net.
        var lines: [LineTotal] = document.items.map { item in
            var line = LineTotal(itemID: item.id)
            line.gross = (item.quantity * item.unitPrice).rounded(2)
            let discount: Decimal
            if line.gross <= 0 {
                discount = 0
            } else if item.discountKind == .percent {
                discount = (line.gross * item.discountValue.clamped(0, 100) / 100).rounded(2)
            } else {
                discount = item.discountValue.rounded(2).clamped(0, line.gross)
            }
            line.lineDiscount = discount
            line.net = line.gross - discount
            line.taxRate = applyTax ? max(item.taxRate, 0) : 0
            return line
        }

        let subtotal = lines.reduce(Decimal(0)) { $0 + $1.net }
        totals.subtotal = subtotal
        totals.lineDiscountTotal = lines.reduce(Decimal(0)) { $0 + $1.lineDiscount }

        // 2. Document discount, allocated across lines in proportion to their net so tax stays correct.
        var documentDiscount: Decimal = 0
        if subtotal > 0 {
            if document.documentDiscountKind == .percent {
                documentDiscount = (subtotal * document.documentDiscountValue.clamped(0, 100) / 100).rounded(2)
            } else {
                documentDiscount = document.documentDiscountValue.rounded(2).clamped(0, subtotal)
            }
        }
        totals.documentDiscount = documentDiscount
        allocate(documentDiscount, across: &lines, total: subtotal)

        // 3. Taxable value per line.
        for index in lines.indices {
            let afterDiscount = lines[index].net - lines[index].allocatedDiscount
            if document.taxMode == .inclusive, lines[index].taxRate > 0 {
                lines[index].taxable = (afterDiscount * 100 / (100 + lines[index].taxRate)).rounded(2)
            } else {
                lines[index].taxable = afterDiscount
            }
        }

        // 4. Tax grouped by rate, rounded once per group.
        var taxLines: [TaxLine] = []
        if applyTax {
            let rates = Set(lines.map(\.taxRate)).filter { $0 > 0 }.sorted()
            for rate in rates {
                let group = lines.filter { $0.taxRate == rate }
                let taxable = group.reduce(Decimal(0)) { $0 + $1.taxable }
                let tax: Decimal
                if document.taxMode == .inclusive {
                    tax = group.reduce(Decimal(0)) { $0 + ($1.net - $1.allocatedDiscount - $1.taxable) }
                } else {
                    tax = (taxable * rate / 100).rounded(2)
                }
                taxLines += split(tax: tax, rate: rate, taxable: taxable, document: document)
            }
        }

        totals.lines = lines
        totals.taxLines = taxLines
        totals.taxableAmount = lines.reduce(Decimal(0)) { $0 + $1.taxable }
        totals.taxTotal = taxLines.reduce(Decimal(0)) { $0 + $1.amount }
        totals.shipping = document.shipping.rounded(2)
        totals.adjustment = document.adjustment.rounded(2)

        let beforeRounding = totals.taxableAmount + totals.taxTotal + totals.shipping + totals.adjustment
        totals.roundOff = document.roundOffTotal ? beforeRounding.rounded(0) - beforeRounding : 0
        totals.grandTotal = beforeRounding + totals.roundOff
        totals.advancePaid = document.advancePaid.rounded(2)
        totals.amountPaid = document.amountPaid.rounded(2)
        totals.balanceDue = totals.grandTotal - totals.advancePaid - totals.amountPaid
        totals.amountInWords = AmountInWords.words(for: totals.grandTotal, currency: document.currency)
        return totals
    }

    /// Splits `amount` across lines by weight; the last positive line absorbs the rounding remainder.
    private static func allocate(_ amount: Decimal, across lines: inout [LineTotal], total: Decimal) {
        guard amount > 0, total > 0 else { return }
        let eligible = lines.indices.filter { lines[$0].net > 0 }
        guard let last = eligible.last else { return }
        var allocated: Decimal = 0
        for index in eligible where index != last {
            let share = (amount * lines[index].net / total).rounded(2)
            lines[index].allocatedDiscount = share
            allocated += share
        }
        lines[last].allocatedDiscount = amount - allocated
    }

    private static func split(tax: Decimal, rate: Decimal, taxable: Decimal, document: DocumentRecord) -> [TaxLine] {
        let rateText = MoneyFormatter.quantity(rate)
        switch document.taxSplit {
        case .none:
            return []
        case .single:
            let label = document.taxLabel.isEmpty ? "Tax" : document.taxLabel
            return [TaxLine(label: "\(label) @ \(rateText)%", rate: rate, taxable: taxable, amount: tax)]
        case .igst:
            return [TaxLine(label: "IGST @ \(rateText)%", rate: rate, taxable: taxable, amount: tax)]
        case .cgstSgst:
            let half = rate / 2
            let halfText = MoneyFormatter.quantity(half)
            let central = (tax / 2).rounded(2)
            return [
                TaxLine(label: "CGST @ \(halfText)%", rate: half, taxable: taxable, amount: central),
                TaxLine(label: "SGST @ \(halfText)%", rate: half, taxable: taxable, amount: tax - central),
            ]
        }
    }
}
