//
//  APIService.swift
//  Smart bill
//
//  Created by abdulaziz on 07/04/2026.
//

import Foundation

class APIService {
    
    static let shared = APIService()
    private let baseURL = "http://192.168.1.10" // غيره IPك
    
    // تسجيل دخول
    func login(email: String, password: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/login.php") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "email": email,
            "password": password
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else { return }
            
            if let response = String(data: data, encoding: .utf8) {
                print(response)
                completion(response.contains("success"))
            }
        }.resume()
    }
    
    // حفظ الفاتورة
    func saveReceipt(store: String, items: [(name: String, price: String)]) {
        guard let url = URL(string: "\(baseURL)/save_receipt.php") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let itemsArray = items.map {
            ["name": $0.name, "price": $0.price]
        }
        
        let body: [String: Any] = [
            "store": store,
            "items": itemsArray
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request).resume()
    }
}
