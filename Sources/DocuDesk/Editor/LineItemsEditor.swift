import DocuDeskCore
import SwiftUI

struct LineItemsEditor: View {
    @ObservedObject var model: DocumentEditorModel

    private var pricing: Bool { model.document.showsPricing }
    private var taxed: Bool { model.document.taxSplit != .none }

    var body: some View {
        let totals = model.totals
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Item").frame(maxWidth: .infinity, alignment: .leading)
                Text("Qty").frame(width: 64, alignment: .trailing)
                Text("Unit").frame(width: 56, alignment: .leading)
                if pricing {
                    Text("Rate").frame(width: 92, alignment: .trailing)
                    Text("Amount").frame(width: 96, alignment: .trailing)
                }
                Color.clear.frame(width: 44)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 10)

            if model.document.items.isEmpty {
                Text("No items yet. Add one below.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }

            ForEach($model.document.items) { $item in
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        TextField("Item or service name", text: $item.name).fieldStyle()
                        DecimalField(placeholder: "1", value: $item.quantity).fieldStyle().frame(width: 64)
                        TextField("nos", text: $item.unit).fieldStyle().frame(width: 56)
                        if pricing {
                            DecimalField(placeholder: "0.00", value: $item.unitPrice).fieldStyle().frame(width: 92)
                            Text(MoneyFormatter.number(totals.line(for: item.id)?.net ?? 0, currency: model.document.currency))
                                .font(.system(size: 13, weight: .semibold))
                                .monospacedDigit()
                                .frame(width: 96, alignment: .trailing)
                        }
                        Menu {
                            Button("Move Up") { model.moveItem(item.id, by: -1) }
                            Button("Move Down") { model.moveItem(item.id, by: 1) }
                            Divider()
                            Button("Remove", role: .destructive) { model.removeItem(item.id) }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .frame(width: 44)
                    }
                    HStack(spacing: 8) {
                        TextField("Description (optional)", text: $item.details).fieldStyle()
                        TextField("HSN/SAC", text: $item.hsnSac).fieldStyle().frame(width: 84)
                        if pricing {
                            HStack(spacing: 4) {
                                DecimalField(placeholder: "0", value: $item.discountValue).fieldStyle().frame(width: 58)
                                Picker("", selection: $item.discountKind) {
                                    Text("%").tag(DiscountKind.percent)
                                    Text("Amt").tag(DiscountKind.amount)
                                }
                                .labelsHidden()
                                .frame(width: 66)
                            }
                            .help("Line discount")
                            if taxed {
                                HStack(spacing: 2) {
                                    DecimalField(placeholder: "0", value: $item.taxRate).fieldStyle().frame(width: 52)
                                    Text("%").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                                }
                                .help("Tax rate")
                            }
                        }
                        Color.clear.frame(width: 44)
                    }
                }
                .padding(10)
                .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}
