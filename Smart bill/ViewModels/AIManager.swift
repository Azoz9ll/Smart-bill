//
//  AIManager.swift
//  Smart Bill
//
//  Purpose:
//  تحليل صور الفواتير عبر وسيط PHP آمن يتصل بـ OpenAI على الخادم.
//
//  Responsibilities:
//  - تجهيز الصورة وإرسالها بدقة عالية
//  - فحص JSON والأسعار والكميات والتصنيفات محليًا
//  - إعادة المحاولة بالصورة المحسنة عند نتيجة غير صالحة أو فارغة فقط
//  - توحيد النصوص العربية وتجميع طلبات الصورة المتكررة
//

import Foundation
import UIKit

extension String {
    /// يقيس تشابه النصين بعد التطبيع اعتمادًا على مسافة Levenshtein.
    func similarity(to other: String) -> Double {
        let a = self.normalized()
        let b = other.normalized()
        
        let distance = levenshtein(a, b)
        let maxLen = max(a.count, b.count)
        
        if maxLen == 0 { return 1.0 }
        return 1.0 - (Double(distance) / Double(maxLen))
    }
    
    /// يوحد الحروف والأرقام والمسافات العربية مع الاحتفاظ بمعلومات المنتج.
    func normalized() -> String {
        return self
            .replacingOccurrences(of: #"[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06EDـ]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "أ", with: "ا")
            .replacingOccurrences(of: "إ", with: "ا")
            .replacingOccurrences(of: "آ", with: "ا")
            .replacingOccurrences(of: "ة", with: "ه")
            .replacingOccurrences(of: "ى", with: "ي")
            .normalizedDigits()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
    
    /// يحسب عدد عمليات التحرير اللازمة لتحويل نص إلى آخر.
    private func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        if aChars.isEmpty { return bChars.count }
        if bChars.isEmpty { return aChars.count }
        
        var dist = Array(
            repeating: Array(repeating: 0, count: bChars.count + 1),
            count: aChars.count + 1
        )
        
        for i in 0...aChars.count { dist[i][0] = i }
        for j in 0...bChars.count { dist[0][j] = j }
        
        for i in 1..<(aChars.count + 1) {
            for j in 1..<(bChars.count + 1) {
                if aChars[i-1] == bChars[j-1] {
                    dist[i][j] = dist[i-1][j-1]
                } else {
                    dist[i][j] = Swift.min(
                        dist[i-1][j] + 1,
                        dist[i][j-1] + 1,
                        dist[i-1][j-1] + 1
                    )
                }
            }
        }
        
        return dist[aChars.count][bChars.count]
    }
    
    /// يحول الأرقام العربية والفارسية إلى الأرقام الغربية.
    func normalizedDigits() -> String {
        var s = self
        let map: [Character: Character] = [
            "٠":"0","١":"1","٢":"2","٣":"3","٤":"4","٥":"5","٦":"6","٧":"7","٨":"8","٩":"9",
            "۰":"0","۱":"1","۲":"2","۳":"3","۴":"4","۵":"5","۶":"6","۷":"7","۸":"8","۹":"9"
        ]
        s.replaceSubrange(s.startIndex..<s.endIndex, with: s.map { map[$0] ?? $0 })
        return s
    }
}

/// ينسق تحليل الصورة عبر OpenAI والتحقق من النتيجة وإعادة المحاولة المحدودة.
class VisionManager {
    static var isUploading = false

    enum AnalysisError: Error {
        case configuration
        case connection
        case authentication
        case forbidden
        case rateLimited
        case imageTooLarge
        case invalidImage
        case server
        case invalidResponse
        case invalidJSON
        case noProducts

        var userMessage: String {
            switch self {
            case .configuration:
                return "خدمة تحليل الفواتير غير مهيأة على الخادم."
            case .connection:
                return "تعذر الاتصال بخدمة تحليل الفواتير. تحقق من الإنترنت وحاول مرة أخرى."
            case .authentication:
                return "انتهت جلسة الدخول. سجّل الدخول مجددًا ثم أعد التحليل."
            case .forbidden:
                return "لا تملك صلاحية استخدام خدمة تحليل الفواتير."
            case .rateLimited:
                return "وصلت إلى حد التحليلات المؤقت. حاول لاحقًا."
            case .imageTooLarge:
                return "حجم صورة الفاتورة أكبر من الحد المسموح. اختر صورة أصغر."
            case .invalidImage:
                return "تعذر قراءة صورة الفاتورة. اختر صورة واضحة بصيغة مدعومة وحاول مرة أخرى."
            case .server:
                return "خدمة تحليل الفواتير غير متاحة مؤقتًا. حاول مرة أخرى."
            case .invalidResponse, .invalidJSON:
                return "وصل رد غير صالح من خدمة التحليل. حاول مرة أخرى."
            case .noProducts:
                return "لم نعثر على منتجات واضحة في الفاتورة. راجع الصورة أو أضف المنتجات يدويًا."
            }
        }
    }
    
    private let imageContext = CIContext()
    private typealias ReceiptCompletion = (String, [(String, Double?, String)]) -> Void
    private var pending: [ObjectIdentifier: [ReceiptCompletion]] = [:]
    private weak var recentImage: UIImage?
    private var recentResult: (String, [(String, Double?, String)])?
    private var recentFailureMessage: String?
    private var recentResultTime: TimeInterval = 0
    private(set) var lastFailureMessage: String?

    // Kept for compatibility; unused OCR heuristics never choose the AI's prices.
    static let priceRegex: NSRegularExpression = {
        // The pattern is a fixed literal, not user input.
        return try! NSRegularExpression(pattern: #"(?<!\d)(\d{1,4}(?:[.,]\d{1,2})?)(?!\d)"#, options: [.caseInsensitive])
    }()

    /// يضبط اتجاه الصورة وحجمها الأقصى دون قص أو تمديد.
    private func preparedImage(_ image: UIImage) -> UIImage? {
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        let scale = min(1, 4096 / max(width, height))
        let size = CGSize(width: max(1, (width * scale).rounded()), height: max(1, (height * scale).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        // Drawing also resolves UIImage orientation without cropping or stretching.
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// يحسن التباين والحدة قليلًا وينتج JPEG لمحاولة التحليل البديلة.
    private func preprocessedJPEGData(from image: UIImage) -> Data? {
        guard let ciImage = CIImage(image: image),
              let controls = CIFilter(name: "CIColorControls"),
              let sharpen = CIFilter(name: "CISharpenLuminance") else { return nil }
        controls.setValue(ciImage, forKey: kCIInputImageKey)
        controls.setValue(0.25, forKey: kCIInputSaturationKey)
        controls.setValue(1.10, forKey: kCIInputContrastKey)
        guard let adjusted = controls.outputImage else { return nil }
        sharpen.setValue(adjusted, forKey: kCIInputImageKey)
        sharpen.setValue(0.15, forKey: kCIInputSharpnessKey)
        guard let output = sharpen.outputImage,
              let cgImage = imageContext.createCGImage(output, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.95)
    }

    /// نقطة توافق قديمة تعيد nil ولا تطلب رمز وصول.
    func fetchAccessToken(completion: @escaping (String?) -> Void) {
        completion(nil)
    }
    
    /// يجمع طلبات الصورة المتكررة ويبدأ التحليل أو يعيد النتيجة الحديثة.
    func process(image: UIImage, retry: Bool = false, completionWithCategory: @escaping (String, [(String, Double?, String)]) -> Void) {
        DispatchQueue.main.async {
            let key = ObjectIdentifier(image)
            if self.pending[key] != nil {
                self.pending[key]?.append(completionWithCategory)
                return
            }
            // ContentView immediately calls process again after an empty result.
            // Reuse that result briefly so its legacy retry cannot double our two-attempt budget.
            if self.recentImage === image, let result = self.recentResult,
               ProcessInfo.processInfo.systemUptime - self.recentResultTime < 3 {
                self.lastFailureMessage = self.recentFailureMessage
                completionWithCategory(result.0, result.1)
                return
            }
            self.lastFailureMessage = nil
            self.pending[key] = [completionWithCategory]
            guard let prepared = self.preparedImage(image) else {
                Self.debugLog("Receipt analysis stopped: image preparation failed")
                self.finish(image: image, store: "", items: [], failureMessage: AnalysisError.invalidImage.userMessage)
                return
            }
            self.analyze(prepared: prepared, original: image, enhanced: retry)
        }
    }

    /// يحلل الصورة ويستخدم النسخة المحسنة فقط إذا كانت النتيجة غير قابلة للاستخدام.
    private func analyze(prepared: UIImage, original: UIImage, enhanced: Bool) {
        let data = enhanced ? preprocessedJPEGData(from: prepared) : prepared.jpegData(compressionQuality: 0.95)
        guard let data else {
            finish(image: original, store: "", items: [])
            return
        }
        callGPTImage(base64: data.base64EncodedString()) { result in
            DispatchQueue.main.async {
                // Transport, auth, HTTP, and server errors are not improved by changing the image.
                guard case .success(let response) = result else {
                    if case .failure(let error) = result {
                        self.finish(image: original, store: "", items: [], failureMessage: error.userMessage)
                    }
                    return
                }
                let parsed = ReceiptAIResponse.parse(response)
                if let parsed, !parsed.items.isEmpty {
                    Self.debugLog("Receipt analysis decoded \(parsed.items.count) product rows")
                    self.finish(image: original, store: parsed.store, items: parsed.items)
                } else if !enhanced {
                    Self.debugLog("Receipt analysis returned \(parsed?.items.count ?? 0) products; retrying enhanced image")
                    Self.debugLog("🔄 Retrying receipt with enhanced image")
                    self.analyze(prepared: prepared, original: original, enhanced: true)
                } else {
                    Self.debugLog("❌ No usable products after fallback")
                    let message = parsed == nil
                        ? AnalysisError.invalidJSON.userMessage
                        : AnalysisError.noProducts.userMessage
                    self.finish(image: original, store: "", items: [], failureMessage: message)
                }
            }
        }
    }

    /// ينهي طلب الصورة ويبلغ جميع المستدعين ويحفظ النتيجة مؤقتًا.
    private func finish(image: UIImage, store: String, items: [ReceiptAIItem], failureMessage: String? = nil) {
        let key = ObjectIdentifier(image)
        guard let callbacks = pending.removeValue(forKey: key) else { return }
        let result = (store, items.map { ($0.name, $0.price, $0.category) })
        recentImage = image
        recentResult = result
        recentFailureMessage = failureMessage
        lastFailureMessage = failureMessage
        recentResultTime = ProcessInfo.processInfo.systemUptime
        for callback in callbacks { callback(result.0, result.1) }
    }

    /// يطبع معلومات التشخيص في بناء DEBUG فقط.
    nonisolated private static func debugLog(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }

    /// Only returns fixed error codes/messages emitted by the local PHP endpoint; unknown text is never logged.
    nonisolated private static func safeEndpointErrorDetails(from data: Data?) -> (code: String?, message: String?) {
        let knownCodes: Set<String> = [
            "method_not_allowed", "unsupported_media_type", "request_too_large",
            "authentication_required", "rate_limited", "invalid_json", "invalid_image",
            "jpeg_required", "service_unavailable", "openai_unavailable", "openai_error",
            "invalid_openai_response", "internal_error"
        ]
        let knownMessages: Set<String> = [
            "استخدم POST لتحليل صورة الفاتورة.", "أرسل الطلب بصيغة JSON.",
            "حجم الصورة أكبر من الحد المسموح.", "سجّل الدخول قبل تحليل الفاتورة.",
            "وصلت إلى حد التحليلات المؤقت. حاول لاحقًا.",
            "تعذر استقبال الصورة أو تجاوزت الحد المسموح.", "صيغة الطلب غير صالحة.",
            "بيانات صورة الفاتورة غير صالحة.", "تعذر قراءة صورة الفاتورة أو تجاوزت الحد المسموح.",
            "صيغة الصورة المدعومة هي JPEG.", "خدمة تحليل الفواتير غير مهيأة حاليًا.",
            "تعذر بدء خدمة تحليل الفواتير.", "تعذر تجهيز طلب التحليل.",
            "تعذر الاتصال بخدمة التحليل. حاول مرة أخرى لاحقًا.",
            "تعذر تحليل الفاتورة حاليًا. حاول مرة أخرى لاحقًا.",
            "وصل رد غير مكتمل من خدمة التحليل.", "تعذر التحقق من نتيجة التحليل.",
            "تعذر التحقق من أحد صفوف المنتجات."
        ]
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else { return (nil, nil) }
        let rawCode = error["code"] as? String
        let rawMessage = error["message"] as? String
        return (
            rawCode.flatMap { knownCodes.contains($0) ? $0 : nil },
            rawMessage.flatMap { knownMessages.contains($0) ? $0 : nil }
        )
    }

    /// يرسل الصورة إلى وسيط SmartBill الآمن ويعيد JSON التحليل عند نجاح الاستجابة.
    func callGPTImage(base64: String, completion: @escaping (Result<String, AnalysisError>) -> Void) {
        let url: URL
        do {
            url = try ServerConfig.secureEndpoint("analyze_receipt.php")
        } catch {
            Self.debugLog("Receipt analysis stopped: endpoint configuration is invalid")
            completion(.failure(.configuration))
            return
        }
        let sessionCookieAvailable = ServerSession.hasSessionCookie(for: url)
        Self.debugLog("Receipt request endpoint=https://\(url.host ?? "unknown")\(url.path); PHPSESSID available=\(sessionCookieAvailable)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: Any] = [
            "image_base64": base64
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(.invalidResponse))
            return
        }
        ServerSession.shared.dataTask(with: request) { data, response, error in
            if error != nil {
                let urlCode = (error as? URLError)?.code.rawValue
                Self.debugLog("Receipt analysis transport failure before HTTP response; URLError=\(urlCode.map(String.init) ?? "unknown")")
                completion(.failure(.connection))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                Self.debugLog("Receipt analysis failed: response was not HTTP")
                completion(.failure(.invalidResponse))
                return
            }
            let errorDetails = Self.safeEndpointErrorDetails(from: data)
            let errorCode = errorDetails.code
            let setCookieHeaderPresent = http.allHeaderFields.keys.contains {
                String(describing: $0).caseInsensitiveCompare("Set-Cookie") == .orderedSame
            }
            let explicitAuthenticationFailure = http.statusCode == 401 && errorCode == "authentication_required"
            let sameOrigin = http.url?.scheme == url.scheme
                && http.url?.host?.lowercased() == url.host?.lowercased()
            Self.debugLog("Receipt HTTP \(http.statusCode); PHPSESSID available before send=\(sessionCookieAvailable); Set-Cookie header present=\(setCookieHeaderPresent); PHPSESSID available after response=\(ServerSession.hasSessionCookie(for: url)); explicit auth rejection=\(explicitAuthenticationFailure); response same HTTPS origin=\(sameOrigin); error.code=\(errorCode ?? "omitted"); error.message=\(errorDetails.message ?? "omitted")")
            guard (200...299).contains(http.statusCode) else {
                switch http.statusCode {
                case 401 where explicitAuthenticationFailure:
                    ServerSession.clearSessionCookie(for: url)
                    UserDefaults.standard.set(false, forKey: "isLoggedIn")
                    Self.debugLog("Stored login state cleared after explicit authentication rejection")
                    completion(.failure(.authentication))
                case 401: completion(.failure(.server))
                case 403: completion(.failure(.forbidden))
                case 413: completion(.failure(.imageTooLarge))
                case 400 where errorCode == "invalid_image": completion(.failure(.invalidImage))
                case 415 where errorCode == "jpeg_required": completion(.failure(.invalidImage))
                case 429: completion(.failure(.rateLimited))
                case 503 where errorCode == "service_unavailable": completion(.failure(.configuration))
                case 500...599: completion(.failure(.server))
                default:
                    completion(.failure(.invalidResponse))
                }
                return
            }
            guard let data, !data.isEmpty else {
                Self.debugLog("Receipt analysis failed: empty successful HTTP response")
                completion(.failure(.invalidResponse))
                return
            }
            guard (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) != nil else {
                Self.debugLog("Receipt analysis failed: successful HTTP response was not JSON")
                completion(.failure(.invalidJSON))
                return
            }
            completion(.success(String(decoding: data, as: UTF8.self)))
        }.resume()
    }
}
