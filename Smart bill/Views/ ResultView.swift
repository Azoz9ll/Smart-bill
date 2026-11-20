//
//   ResultView.swift
//  Smart Bill
//
//  Purpose:
//  واجهة نتائج تعرض متجرًا ومنتجات ومجموع أسعارها.
//
//  Responsibilities:
//  - عرض العناصر وحذف عنصر من القائمة المعروضة
//  - حفظ العناصر محليًا في saved_items باستخدام UserDefaults
//

import SwiftUI

/// واجهة نتائج تعرض متجرًا ومنتجات ومجموع أسعارها.
struct ResultView: View {
    
    var storeName: String
    @State var items: [Product]
    
    // 🧠 حساب الإجمالي
    var total: Double {
        items.reduce(0) { $0 + $1.price }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                
                // 🏪 Store Card
                VStack(alignment: .leading, spacing: 6) {
                    Text("المتجر")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Text(SmartBillFormatting.digits(storeName))
                        .font(.title2.bold())
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .cornerRadius(16)
                
                // 🧾 Items List
                VStack(spacing: 12) {
                    ForEach(items, id: \.id) { item in
                        HStack {
                            
                            // التصنيف (يسار)
                            SmartBillCategoryLabel(category: item.category)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(8)
                            
                            Spacer()
                            
                            // اسم المنتج (وسط)
                            Text(SmartBillFormatting.digits(item.name))
                                .font(.body.bold())
                                .multilineTextAlignment(.center)
                            
                            Spacer()
                            
                            // السعر + الريال (يمين)
                            HStack(spacing: 4) {
                                Text(SmartBillFormatting.money(item.price))
                                    .font(.body.bold())
                            }
                            
                            // زر حذف
                            Button {
                                deleteItem(item)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(14)
                        .shadow(color: .black.opacity(0.05), radius: 4)
                    }
                }
                
                // 💰 Total Card
                HStack {
                    Text("الإجمالي")
                        .font(.headline)
                    
                    Spacer()
                    
                    Text(SmartBillFormatting.money(total))
                        .font(.headline.bold())
                }
                .padding()
                .background(Color.green.opacity(0.15))
                .cornerRadius(16)
                
                // 💾 Save Button
                Button(action: saveItems) {
                    Text("حفظ الفاتورة")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                }
            }
            .padding()
        }
        .navigationTitle("النتائج")
    }
    
    /// يحفظ المنتجات المعروضة محليًا في saved_items دون طلب شبكة.
    func saveItems() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: "saved_items")
        }
    }
    
    /// يحذف العنصر من قائمة النتائج المعروضة حسب هويته.
    func deleteItem(_ item: Product) {
        items.removeAll { $0.id == item.id }
    }
}

#Preview {
    ResultView(
        storeName: "بنده",
        items: [
            Product(id: 1, name: "ماء", price: 1.15, category: "مشروبات"),
            Product(id: 2, name: "خبز", price: 2.00, category: "مخبوزات")
        ]
    )
}
