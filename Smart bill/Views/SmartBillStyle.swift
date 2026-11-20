//
//  SmartBillStyle.swift
//  Smart Bill
//
//  Purpose:
//  ألوان ومكونات وتنسيقات مشتركة لواجهات الأسعار.
//
//  Responsibilities:
//  - توفير ألوان فاتحة وداكنة وسطح البطاقة
//  - تنسيق الريال السعودي
//  - قراءة تواريخ ISO 8601
//

import SwiftUI

struct SmartBillCategoryLabel: View {
    let category: String

    var body: some View {
        if let key = SmartBillFormatting.localizedCategoryKey(category) {
            Text(LocalizedStringKey(key))
        } else {
            Text(SmartBillFormatting.digits(category))
        }
    }
}

/// ألوان ومكونات وتنسيقات مشتركة لواجهات الأسعار.
struct SmartBillStyle {
    let scheme: ColorScheme
    static let cardRadius: CGFloat = 18
    static let controlHeight: CGFloat = 52
    static let horizontalInset: CGFloat = 20
    var accent: Color { scheme == .dark ? Color(red: 0.40, green: 0.63, blue: 0.51) : Color(red: 0.20, green: 0.48, blue: 0.36) }
    var background: Color { scheme == .dark ? Color(red: 0.025, green: 0.04, blue: 0.04) : Color(red: 0.965, green: 0.975, blue: 0.97) }
    var card: Color { scheme == .dark ? Color(red: 0.075, green: 0.095, blue: 0.095) : .white }
    var primary: Color { scheme == .dark ? .white : Color(red: 0.07, green: 0.10, blue: 0.09) }
    var secondary: Color { scheme == .dark ? .white.opacity(0.58) : .black.opacity(0.56) }
    var border: Color { scheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08) }
    var surface: some View {
        RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
            .fill(card)
            .overlay(RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous).strokeBorder(border, lineWidth: 1))
    }
}

