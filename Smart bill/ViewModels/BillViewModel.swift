//
//  BillViewModel.swift
//  Smart bill
//
//  Created by abdulaziz on 07/04/2026.
//

import Foundation
import Combine

class BillViewModel: ObservableObject {
    
    func saveReceipt(store: String, items: [Product]) {
        let formatted: [(name: String, price: String)] = items.map {
            (name: $0.name, price: String($0.price))
        }
        
        APIService.shared.saveReceipt(store: store, items: formatted)
    }
}
