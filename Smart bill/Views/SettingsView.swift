//
//  SettingsView.swift
//  Smart Bill
//
//  Purpose:
//  واجهة إعدادات الحساب والمعلومات العامة للتطبيق.
//
//  Responsibilities:
//  - عرض البريد وبيانات الحساب المحلية
//  - إتاحة تسجيل الخروج
//  - تنسيق أقسام الإعدادات بما يناسب الوضعين الفاتح والداكن
//

import SwiftUI

/// واجهة إعدادات الحساب والمعلومات العامة للتطبيق.
struct SettingsView: View {
    @AppStorage("isLoggedIn") var isLoggedIn = false
    @AppStorage("user_email") var userEmail: String = "user@email.com"
    @AppStorage(SmartBillLanguage.preferenceKey) private var appLanguage = SmartBillLanguage.arabic.rawValue
    @AppStorage("appAppearance") private var appAppearance = "system"
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingLanguagePicker = false
    @State private var confirmLogout = false
    @AppStorage("notifications.enabled") private var notificationsEnabled = false
    @AppStorage("notifications.priceDrops") private var priceDropNotifications = false
    @AppStorage("notifications.offers") private var offerNotifications = false
    @AppStorage("notifications.favorites") private var favoriteNotifications = false
    @AppStorage("notifications.weeklySummary") private var weeklySummaryNotifications = false
    @AppStorage("notifications.receipts") private var receiptNotifications = false

    var body: some View {
        NavigationStack {
            ZStack {
                screenBackground
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        headerView
                        profileCard
                        accountSection
                        appSection
                        notificationSection
                        privacySection
                        storageSection
                        supportSection
                        aboutSection
                        Text("Smart Bill")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(secondaryTextColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .padding(SmartBillStyle.horizontalInset)
                    .padding(.bottom, 12)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
            }
            .foregroundStyle(primaryTextColor)
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(backgroundColor, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
        }
        .tint(accentColor)
        .sheet(isPresented: $showingLanguagePicker) {
            languagePickerSheet
                .presentationDetents([.height(250)])
                .presentationDragIndicator(.visible)
                .presentationBackground(backgroundColor)
        }
        .confirmationDialog("تسجيل الخروج؟", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("تسجيل الخروج", role: .destructive) {
                if let sessionURL = try? ServerConfig.secureEndpoint("login.php") {
                    ServerSession.clearSessionCookie(for: sessionURL)
                }
                isLoggedIn = false
            }
            Button("إلغاء", role: .cancel) {}
        }
    }

    // MARK: - Sections

    private var headerView: some View {
        HStack(spacing: 14) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(accentColor)
                .frame(width: 52, height: 52)
                .background(cardColor, in: Circle())
                .overlay(Circle().strokeBorder(accentColor.opacity(0.20), lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("الإعدادات")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text("إدارة حسابك وتفضيلات التطبيق")
                    .font(.subheadline)
                    .foregroundStyle(secondaryTextColor)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    private var profileCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.fill")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(accentColor)
                .frame(width: 52, height: 52)
                .background(accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text("حسابي")
                    .font(.title3.bold())
                Text(userEmail)
                    .font(.subheadline)
                    .foregroundStyle(secondaryTextColor)
                    .environment(\.layoutDirection, .leftToRight)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(cardSurface)
    }

    private var accountSection: some View {
        settingsSection("الحساب", symbol: "person.crop.circle") {
            settingsRow("البريد الإلكتروني", subtitle: userEmail,
                        symbol: "envelope.fill", email: true)
            divider
            Button {
                confirmLogout = true
            } label: {
                settingsRow(
                    "تسجيل الخروج", subtitle: "الخروج من حساب Smart Bill",
                    symbol: "rectangle.portrait.and.arrow.right", destructive: true
                )
            }
        }
    }

    private var appSection: some View {
        settingsSection("التطبيق", symbol: "slider.horizontal.3") {
            Button {
                showingLanguagePicker = true
            } label: {
                settingsRow("اللغة", subtitle: appLanguage == "ar" ? "العربية" : "English", symbol: "globe", showsChevron: true)
            }
            .buttonStyle(.plain)
            divider
            Menu {
                Picker("المظهر", selection: $appAppearance) {
                    Text("حسب النظام").tag("system")
                    Text("الوضع الفاتح").tag("light")
                    Text("الوضع الداكن").tag("dark")
                }
            } label: {
                settingsRow("المظهر", subtitle: appearanceTitle,
                            symbol: appAppearance == "dark" ? "moon.fill" : appAppearance == "light" ? "sun.max.fill" : "circle.lefthalf.filled",
                            showsChevron: true)
            }
            divider
            settingsRow("العملة", subtitle: "الريال السعودي (SAR)", symbol: "banknote")
            divider
            settingsRow("المنطقة", subtitle: "المملكة العربية السعودية", symbol: "mappin.and.ellipse")
        }
    }

    private var notificationSection: some View {
        settingsSection("الإشعارات", symbol: "bell.badge") {
            Toggle("تفعيل الإشعارات", isOn: $notificationsEnabled).padding(16)
            divider
            notificationToggle("تنبيهات انخفاض الأسعار", isOn: $priceDropNotifications)
            notificationToggle("العروض الجديدة", isOn: $offerNotifications)
            notificationToggle("تحديثات المنتجات المفضلة", isOn: $favoriteNotifications)
            notificationToggle("ملخص التوفير الأسبوعي", isOn: $weeklySummaryNotifications)
            notificationToggle("تحديثات معالجة الفواتير", isOn: $receiptNotifications)
            Text("تُحفظ التفضيلات على هذا الجهاز. لا توجد خدمة إشعارات خلفية مهيأة في المشروع.")
                .font(.caption).foregroundStyle(secondaryTextColor).padding(16)
        }
    }

    private func notificationToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn).padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var privacySection: some View {
        settingsSection("الخصوصية والأمان", symbol: "lock.shield") {
            settingsRow("أذونات الكاميرا والصور", subtitle: "تُطلب عند استخدام مسح الفواتير", symbol: "camera")
            divider
            settingsRow("إدارة البيانات الشخصية", subtitle: "إدارة الحساب غير مدعومة من الخادم الحالي", symbol: "person.crop.circle")
            divider
            settingsRow("سياسة الخصوصية", subtitle: "رابط السياسة غير مضبوط", symbol: "hand.raised")
            divider
            settingsRow("الشروط والأحكام", subtitle: "رابط الشروط غير مضبوط", symbol: "doc.text")
            divider
            settingsRow("حذف سجل الفواتير", subtitle: "يتطلب مسار حذف آمن من الخادم", symbol: "trash", destructive: true)
        }
    }

    private var storageSection: some View {
        settingsSection("البيانات والتخزين", symbol: "externaldrive") {
            settingsRow("مساحة التخزين", subtitle: "حجم التخزين غير متاح من التطبيق", symbol: "internaldrive")
            divider
            settingsRow("مسح الذاكرة المؤقتة", subtitle: "لا توجد عملية مسح مهيأة", symbol: "eraser")
            divider
            settingsRow("المزامنة", subtitle: "تُحمّل البيانات عند فتح أقسام التطبيق", symbol: "arrow.triangle.2.circlepath")
            divider
            settingsRow("تحديث كتالوج المنتجات", subtitle: "افتح منتجاتي لإعادة تحميل الكتالوج", symbol: "shippingbox")
            divider
            Button { NotificationCenter.default.post(name: Notification.Name("SmartBillShowReceipts"), object: nil) } label: {
                settingsRow("إدارة الفواتير المحفوظة", subtitle: "عرض سجل الفواتير", symbol: "doc.text")
            }
        }
    }

    private var supportSection: some View {
        settingsSection("الدعم والمعلومات", symbol: "questionmark.circle") {
            settingsRow("مركز المساعدة", subtitle: "رابط المساعدة غير مضبوط", symbol: "questionmark.circle")
            divider
            settingsRow("الأسئلة الشائعة", subtitle: "غير متاح حالياً", symbol: "text.bubble")
            divider
            settingsRow("التواصل مع الدعم", subtitle: "عنوان الدعم غير مضبوط", symbol: "envelope")
            divider
            settingsRow("الإبلاغ عن مشكلة", subtitle: "عنوان الدعم غير مضبوط", symbol: "exclamationmark.bubble")
        }
    }

    private var languagePickerSheet: some View {
        NavigationStack {
            VStack(spacing: 10) {
                ForEach(SmartBillLanguage.allCases) { language in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            appLanguage = language.rawValue
                        }
                        showingLanguagePicker = false
                    } label: {
                        HStack(spacing: 12) {
                            Text(language.nativeName)
                                .font(.body.weight(.semibold))
                            Spacer()
                            if appLanguage == language.rawValue {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(accentColor)
                                    .accessibilityLabel(Text("محدد"))
                            }
                        }
                        .foregroundStyle(primaryTextColor)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 54)
                        .background(cardSurface)
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(appLanguage == language.rawValue ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(backgroundColor.ignoresSafeArea())
            .navigationTitle("اختر اللغة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("إغلاق") { showingLanguagePicker = false }
                }
            }
        }
        .tint(accentColor)
    }

    private var appearanceTitle: String {
        switch appAppearance {
        case "dark": "الوضع الداكن"
        case "light": "الوضع الفاتح"
        default: "حسب النظام"
        }
    }

    private var aboutSection: some View {
        settingsSection("حول التطبيق", symbol: "info.circle") {
            settingsRow("Smart Bill", subtitle: "الإصدار 1.0", symbol: "doc.text.magnifyingglass")
        }
    }

    // MARK: - Shared settings components

    /// ينشئ قسم من أقسام الإعدادات وفق تنسيق الشاشة.
    private func settingsSection<Content: View>(
        _ title: LocalizedStringKey,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(accentColor)
                    .accessibilityHidden(true)
                Text(title)
            }
            .font(.headline)
            .padding(.horizontal, 4)

            VStack(spacing: 0, content: content)
                .buttonStyle(.plain)
                .background(cardSurface)
        }
    }

    /// ينشئ صف إعداد مع أيقونة وعنوان وفق تنسيق الشاشة.
    private func settingsRow(
        _ title: LocalizedStringKey,
        subtitle: String,
        symbol: String,
        email: Bool = false,
        showsChevron: Bool = false,
        destructive: Bool = false
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(destructive ? destructiveColor : accentColor)
                .frame(width: 42, height: 42)
                .background(
                    (destructive ? destructiveColor : accentColor).opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 13)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(destructive ? destructiveColor : primaryTextColor)
                Text(LocalizedStringKey(subtitle))
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
                    .environment(\.layoutDirection, email || appLanguage == "en" ? .leftToRight : .rightToLeft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsChevron {
                Image(systemName: appLanguage == "ar" ? "chevron.left" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor.opacity(0.70))
                    .accessibilityHidden(true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Rectangle()
            .fill(borderColor)
            .frame(height: 1)
            .padding(.leading, 70)
            .padding(.trailing, 16)
            .accessibilityHidden(true)
    }

    // MARK: - Smart Bill appearance

    private var accentColor: Color {
        colorScheme == .dark
        ? Color(red: 0.40, green: 0.63, blue: 0.51)
        : Color(red: 0.20, green: 0.48, blue: 0.36)
    }

    private var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.025, green: 0.04, blue: 0.04)
        : Color(red: 0.965, green: 0.975, blue: 0.97)
    }

    private var cardColor: Color {
        colorScheme == .dark
        ? Color(red: 0.075, green: 0.095, blue: 0.095)
        : .white
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : Color(red: 0.07, green: 0.10, blue: 0.09)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.58) : .black.opacity(0.56)
    }

    private var borderColor: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08)
    }

    private var destructiveColor: Color {
        colorScheme == .dark
        ? Color(red: 0.79, green: 0.47, blue: 0.46)
        : Color(red: 0.60, green: 0.25, blue: 0.25)
    }

    private var cardSurface: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(cardColor)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
    }

    private var screenBackground: some View {
        backgroundColor
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(accentColor.opacity(0.06))
                    .frame(width: 280, height: 280)
                    .blur(radius: 60)
                    .offset(x: 120, y: -130)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

#Preview {
    SettingsView()
}
