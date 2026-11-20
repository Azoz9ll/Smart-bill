//
//  Smart_billApp.swift
//  Smart Bill
//
//  Purpose:
//  نقطة تشغيل تطبيق Smart Bill وعرض شاشة البداية.
//
//  Responsibilities:
//  - إنشاء نافذة التطبيق
//  - عرض الشعار مؤقتًا ثم الانتقال إلى RootView
//

//
//  Smart_billApp.swift
//  Smart bill
//
//  Created by abdulaziz on 30/03/2026.
//

import SwiftUI

@main
/// نقطة تشغيل تطبيق Smart Bill وعرض شاشة البداية.
struct Smart_billApp: App {
    @State private var showSplash = true
    @AppStorage(SmartBillLanguage.preferenceKey) private var appLanguage = SmartBillLanguage.arabic.rawValue
    @AppStorage("appAppearance") private var appAppearance = "system"

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showSplash {
                    SplashView()
                } else {
                    RootView()
                }
            }
            .environment(\.locale, SmartBillLanguage.selected.locale)
            .environment(\.layoutDirection, appLanguage == "en" ? .leftToRight : .rightToLeft)
            .environment(\.calendar, Calendar(identifier: .gregorian))
            .preferredColorScheme(preferredColorScheme)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    withAnimation {
                        showSplash = false
                    }
                }
            }
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch appAppearance {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }
}

/// يعرض شعار التطبيق عند البداية قبل فتح الواجهة الرئيسية.
struct SplashView: View {
    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.09, blue: 0.06)
                .ignoresSafeArea()
            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: 450, height: 450)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
