import AppKit
import Charts
import DocuDeskCore
import SwiftUI
import UniformTypeIdentifiers

struct ReportsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var stats = DashboardStats()
    @State private var monthly: [MonthlyAmount] = []
    @State private var topClients: [ClientRanking] = []
    @State private var invoiceStatuses: [(DocumentStatus, Int)] = []
    @State private var months = 12

    private var currency: String { model.profile?.defaultCurrency ?? "INR" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Reports", subtitle: "Calculated from your local records in \(currency). Drafts and cancelled documents are excluded.") {
                    Picker("", selection: $months) {
                        Text("6 months").tag(6)
                        Text("12 months").tag(12)
                        Text("24 months").tag(24)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                    Button { exportWorkbook() } label: { Label("Export Excel", systemImage: "tablecells") }
                        .buttonStyle(SecondaryButtonStyle())
                }

                HStack(spacing: 16) {
                    StatCard(icon: "doc.text.fill", tint: Color(hex: 0x2563EB), title: "Invoiced", value: amount(stats.invoiced), footnote: "all time")
                    StatCard(icon: "checkmark.circle.fill", tint: Color(hex: 0x16A34A), title: "Paid", value: amount(stats.paid), footnote: "marked paid")
                    StatCard(icon: "hourglass", tint: Color(hex: 0xD97706), title: "Outstanding", value: amount(stats.outstanding), footnote: "awaiting payment")
                    StatCard(icon: "exclamationmark.circle.fill", tint: Color(hex: 0xDC2626), title: "Overdue", value: amount(stats.overdue), footnote: "\(stats.overdueCount) invoice\(stats.overdueCount == 1 ? "" : "s")")
                }

                Card {
                    VStack(alignment: .leading, spacing: 16) {
                        CardHeader(title: "Invoiced per month", subtitle: "Issued invoices by issue date")
                        Chart(monthly) { item in
                            BarMark(
                                x: .value("Month", monthLabel(item)),
                                y: .value("Amount", NSDecimalNumber(decimal: item.amount).doubleValue)
                            )
                            .foregroundStyle(Theme.accent.gradient)
                            .cornerRadius(5)
                        }
                        .chartYAxis {
                            AxisMarks { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let number = value.as(Double.self) {
                                        Text(MoneyFormatter.compact(Decimal(number), currency: currency))
                                    }
                                }
                            }
                        }
                        .frame(height: 260)
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            CardHeader(title: "Top clients", subtitle: "By invoiced amount")
                            if topClients.isEmpty {
                                EmptyStateView(icon: "person.2", title: "No invoices yet", message: "Issue invoices to see your top clients.")
                            }
                            ForEach(topClients) { client in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(client.name).font(.system(size: 13, weight: .medium))
                                        Spacer()
                                        Text(MoneyFormatter.compact(client.amount, currency: currency)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                                    }
                                    GeometryReader { proxy in
                                        Capsule().fill(Theme.surfaceMuted)
                                            .overlay(alignment: .leading) {
                                                Capsule().fill(Theme.accent).frame(width: proxy.size.width * share(client))
                                            }
                                    }
                                    .frame(height: 6)
                                }
                            }
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            CardHeader(title: "Invoice status", subtitle: "All invoices")
                            if invoiceStatuses.isEmpty {
                                EmptyStateView(icon: "chart.pie", title: "Nothing to show", message: "Status counts appear once you create invoices.")
                            }
                            ForEach(invoiceStatuses, id: \.0) { status, count in
                                HStack {
                                    StatusPill(status: status)
                                    Spacer()
                                    Text("\(count)").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 12)
        }
        .task(id: "\(model.revision)-\(months)") { load() }
    }

    private func load() {
        guard let store = model.store else { return }
        stats = (try? store.dashboardStats()) ?? DashboardStats()
        monthly = (try? store.monthlyInvoiced(currency: currency, months: months)) ?? []
        topClients = (try? store.topClients(currency: currency)) ?? []
        invoiceStatuses = (try? store.statusBreakdown(kind: .invoice)) ?? []
    }

    private func exportWorkbook() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "xlsx") ?? .data]
        panel.nameFieldStringValue = "DocuDesk Report \(CalendarDate.today.iso).xlsx"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.store?.exportReportXLSX(currency: currency, months: months, to: url)
            model.flash("Report exported")
            model.revealInFinder(url)
        } catch {
            model.show(error, title: "Excel export failed")
        }
    }

    private func amount(_ values: [CurrencyAmount]) -> String {
        let value = values.first { $0.currency == currency }?.amount ?? 0
        let others = values.filter { $0.currency != currency }.count
        return MoneyFormatter.compact(value, currency: currency) + (others > 0 ? " +\(others)" : "")
    }

    private func monthLabel(_ item: MonthlyAmount) -> String {
        let symbols = Calendar.current.shortMonthSymbols
        let name = symbols[max(0, min(11, item.month - 1))]
        return item.month == 1 || item.id == monthly.first?.id ? "\(name) \(item.year % 100)" : name
    }

    private func share(_ client: ClientRanking) -> CGFloat {
        guard let top = topClients.first?.amount, top > 0 else { return 0 }
        return CGFloat(NSDecimalNumber(decimal: client.amount / top).doubleValue)
    }
}
