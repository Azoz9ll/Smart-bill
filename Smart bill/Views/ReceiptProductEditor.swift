//
//  ReceiptProductEditor.swift
//  Smart Bill
//
//  Purpose:
//  مراجعة منتج مستخرج أو إضافة منتج مفقود دون تعديل السجل مباشرة.
//
//  Responsibilities:
//  - تحرير الاسم والسعر والتصنيف في مسودة.
//  - التحقق من السعر قبل إعادة Product إلى الشاشة الرئيسية.
//
import SwiftUI

struct ReceiptProductEditor: View {
    let product: Product
    let onSave: (Product) -> Void
    @State private var name: String
    @State private var price: String
    @State private var category: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    init(product: Product, onSave: @escaping (Product) -> Void) {
        self.product = product; self.onSave = onSave
        _name = State(initialValue: product.name)
        _price = State(initialValue: product.priceAvailable ? String(format: "%.2f", locale: SmartBillFormatting.locale, product.price) : "")
        _category = State(initialValue: product.category.isEmpty ? "أخرى" : product.category)
    }
    private var validPrice: Double? {
        let normalized = price.normalizedDigits().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "٫", with: ".").replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite, value >= 0, value <= 100_000 else { return nil }
        return value
    }
    var body: some View {
        let style = SmartBillStyle(scheme: scheme)
        NavigationStack {
            Form {
                TextField("اسم المنتج", text: $name, axis: .vertical)
                TextField("السعر بالريال", text: $price).keyboardType(.decimalPad)
                    .onChange(of: price) { _, value in price = SmartBillFormatting.digits(value) }
                    .environment(\.layoutDirection, .leftToRight)
                if validPrice == nil { Text("أدخل سعرًا صالحًا بالريال").font(.caption) }
                Picker("التصنيف", selection: $category) {
                    ForEach(Array(Set(["مشروبات", "أطعمة", "مخبوزات", "حلويات", "منظفات", "أخرى", category])).sorted(), id: \.self) {
                        SmartBillCategoryLabel(category: $0).tag($0)
                    }
                }
            }
            .scrollContentBackground(.hidden).background(style.background)
            .navigationTitle(product.name.isEmpty ? "إضافة منتج" : "تعديل المنتج")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") {
                        guard let value = validPrice else { return }
                        var edited = product
                        edited.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        edited.price = value; edited.priceAvailable = true; edited.category = category
                        onSave(edited); dismiss()
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || validPrice == nil)
                }
            }
        }.tint(style.accent)
    }
}
