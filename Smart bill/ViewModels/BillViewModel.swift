//
//  BillViewModel.swift
//  Smart Bill
//
//  Purpose:
//  إدارة حالة حفظ الفاتورة في المسار الذي يستخدم APIService.
//
//  Responsibilities:
//  - التحقق من وجود متجر ومنتجات
//  - تنسيق الأسعار وإرسالها لخدمة الحفظ
//  - تحديث حالة التحميل والنجاح والخطأ
//

//
//  BillViewModel.swift
//  Smart bill
//
//  Created by abdulaziz on 07/04/2026.
//

import Foundation
import Combine

/// إدارة حالة حفظ الفاتورة في المسار الذي يستخدم APIService.
class BillViewModel: ObservableObject {
    
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    
    /// يجهز بيانات الفاتورة ويرسلها عبر مسار الحفظ الخاص بهذا المكون.
    func saveReceipt(store: String, items: [Product]) {
        guard !store.isEmpty, !items.isEmpty else {
            errorMessage = "Invalid data"
            return
        }
        
        isLoading = true
        errorMessage = nil
        successMessage = nil
        
        let formatted: [(name: String, price: String)] = items.map {
            (name: $0.name, price: String(format: "%.2f", $0.price))
        }
        
        APIService.shared.saveReceipt(store: store, items: formatted) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                switch result {
                case .success:
                    self?.successMessage = "Saved successfully"
                case .failure(let error):
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
