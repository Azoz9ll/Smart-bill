//
//  SmartBillFormatting.swift
//  Smart Bill
//
//  Purpose:
//  توحيد عرض الأرقام الغربية والريال والتواريخ دون تغيير البيانات المخزنة.
//
//  Responsibilities:
//  - تثبيت Locale والأرقام 0-9 في تنسيقات العرض.
//  - عرض العملة برمز الريال مع منزلتين عشريتين.
//  - تحويل أرقام النصوص القادمة من الخادم عند عرضها فقط.
//
import Foundation

nonisolated enum SmartBillLanguage: String, CaseIterable, Identifiable {
    case arabic = "ar"
    case english = "en"

    static let preferenceKey = "appLanguage"
    var id: String { rawValue }
    var nativeName: String { self == .arabic ? "العربية" : "English" }

    static var selected: SmartBillLanguage {
        SmartBillLanguage(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "ar") ?? .arabic
    }

    var locale: Locale {
        switch self {
        case .arabic: Locale(identifier: "ar_SA@numbers=latn")
        case .english: Locale(identifier: "en_US")
        }
    }
}

nonisolated enum SmartBillFormatting {
    static var locale: Locale { SmartBillLanguage.selected.locale }

    static func localizedCategoryKey(_ source: String) -> String? {
        let value = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch value {
        case "مشروبات", "مشروب", "drinks", "drink", "beverages", "beverage": return "مشروبات"
        case "قهوة", "coffee": return "قهوة"
        case "أطعمة", "طعام", "food", "foods", "groceries", "grocery": return "أطعمة"
        case "مخبوزات", "bakery", "baked goods": return "مخبوزات"
        case "حلويات", "dessert", "desserts", "sweets": return "حلويات"
        case "منظفات", "cleaning", "detergents": return "منظفات"
        case "تسوق", "shopping": return "تسوق"
        case "أخرى", "other", "others", "manual": return "أخرى"
        case "غير مصنف", "uncategorized", "unclassified": return "غير مصنف"
        default: return nil
        }
    }
    static func digits(_ text: String) -> String {
        String(text.map { character in
            if "٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹".contains(character), let value = character.wholeNumberValue {
                return Character(String(value))
            }
            return character
        })
    }
    static func money(_ value: Double) -> String { String(format: "%.2f ⃁", locale: locale, value) }
    static func money(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return (formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—") + " ⃁"
    }
    static func date(_ value: Date, time: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = time ? "yyyy/MM/dd HH:mm" : "yyyy/MM/dd"
        return formatter.string(from: value)
    }

    static func relativeDate(_ source: String, now: Date = Date()) -> String {
        guard !source.isEmpty else { return SmartBillLanguage.selected == .english ? "Now" : "الآن" }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.calendar = Calendar(identifier: .gregorian)
        parser.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let parsedDate = parser.date(from: source) else { return digits(source) }

        let minutes = max(0, Int(now.timeIntervalSince(parsedDate)) / 60)
        let isEnglish = SmartBillLanguage.selected == .english
        if minutes < 1 { return isEnglish ? "Now" : "الآن" }
        if minutes < 60 {
            if isEnglish { return "\(minutes) \(minutes == 1 ? "minute" : "minutes") ago" }
            return "منذ \(digits(String(minutes))) دقيقة"
        }
        let hours = minutes / 60
        if hours < 24 {
            if isEnglish { return "\(hours) \(hours == 1 ? "hour" : "hours") ago" }
            return "منذ \(digits(String(hours))) ساعة"
        }
        let days = hours / 24
        if days < 7 {
            if isEnglish { return "\(days) \(days == 1 ? "day" : "days") ago" }
            return "منذ \(digits(String(days))) يوم"
        }
        return date(parsedDate)
    }
}
