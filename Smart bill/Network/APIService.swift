//
//  APIService.swift
//  Smart Bill
//
//  Purpose:
//  خدمة الطلبات القديمة إلى عنوان الخادم المحلي المحدد داخل الملف.
//
//  Responsibilities:
//  - توفير نسخة shared لتسجيل الدخول والحفظ
//  - إرسال JSON إلى ملفات PHP
//  - إرجاع النتيجة إلى المستدعي عبر completion
//

//
//  APIService.swift
//  Smart bill
//
//  Created by abdulaziz on 07/04/2026.
//

import Foundation

/// خدمة الطلبات القديمة إلى عنوان الخادم المحلي المحدد داخل الملف.
class APIService {

    nonisolated private struct LoginResponse: Decodable {
        let status: String
    }
    
    static let shared = APIService()
    
    // تسجيل دخول
    /// يرسل بيانات تسجيل الدخول ويعالج نتيجة المصادقة.
    func login(email: String, password: String, completion: @escaping (Bool) -> Void) {
        guard let url = try? ServerConfig.secureEndpoint("login.php") else {
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "email": email,
            "password": password
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        ServerSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil,
                  let data,
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let decoded = try? JSONDecoder().decode(LoginResponse.self, from: data) else {
                completion(false)
                return
            }
            completion(decoded.status.lowercased() == "success")
        }.resume()
    }
    
    // حفظ الفاتورة
    /// يجهز بيانات الفاتورة ويرسلها عبر مسار الحفظ الخاص بهذا المكون.
    func saveReceipt(
        store: String,
        items: [(name: String, price: String)],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let url = try? ServerConfig.endpoint("save_receipt.php") else {
            completion(.failure(ServerConfig.ConfigurationError.invalidBaseURL))
            return
        }
        
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
        
        ServerSession.shared.dataTask(with: request) { data, response, error in
            
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data,
                  let responseString = String(data: data, encoding: .utf8) else {
                completion(.failure(NSError(domain: "NoData", code: -1)))
                return
            }
            
            print(responseString)
            
            if responseString.contains("success") {
                completion(.success(()))
            } else {
                completion(.failure(NSError(domain: responseString, code: -1)))
            }
            
        }.resume()
    }
}
