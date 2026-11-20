//
//  LoginView.swift
//  Smart Bill
//
//  Purpose:
//  واجهات تسجيل الدخول والتسجيل وتوجيه المستخدم حسب الجلسة.
//
//  Responsibilities:
//  - إرسال بيانات الدخول وإنشاء الحساب إلى الخادم
//  - عرض أخطاء المصادقة وتحديث بيانات الجلسة المحلية
//  - اختيار واجهة الدخول أو ContentView عبر RootView
//

import SwiftUI

/// واجهات تسجيل الدخول والتسجيل وتوجيه المستخدم حسب الجلسة.
struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var message = ""
    @State private var showPassword = false

    @AppStorage("isLoggedIn") private var isLoggedIn = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        ZStack {
            background

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: 42)

                    Image("login_logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 132, height: 132)
                        .shadow(
                            color: accentColor.opacity(0.18),
                            radius: 24
                        )

                    Text("Smart Bill")
                        .font(
                            .system(
                                size: 36,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(primaryText)
                        .padding(.top, 10)

                    Text("حوّل فواتيرك إلى بيانات مفيدة")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(secondaryText)
                        .padding(.top, 6)

                    VStack(spacing: 14) {
                        emailField
                        passwordField

                        loginButton

                        HStack(spacing: 14) {
                            Rectangle()
                                .fill(borderColor)
                                .frame(height: 1)

                            Text("أو")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(secondaryText)

                            Rectangle()
                                .fill(borderColor)
                                .frame(height: 1)
                        }
                        .padding(.vertical, 2)

                        registerButton

                        if !message.isEmpty {
                            HStack(spacing: 8) {
                                Image(
                                    systemName:
                                        message.contains("نجاح")
                                        ? "checkmark.circle.fill"
                                        : "exclamationmark.circle.fill"
                                )

                                Text(LocalizedStringKey(message))
                                    .multilineTextAlignment(.center)
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(
                                message.contains("نجاح")
                                ? accentColor
                                : Color.red.opacity(0.9)
                            )
                            .padding(.top, 4)
                        }
                    }
                    .padding(.top, 32)

                    HStack(spacing: 8) {
                        Image(systemName: "chart.bar.fill")
                            .foregroundStyle(accentColor)

                        Text("إدارة فواتيرك بكل سهولة")
                            .foregroundStyle(secondaryText)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .padding(.top, 28)
                    .padding(.bottom, 28)
                }
                .padding(.horizontal, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var emailField: some View {
        HStack(spacing: 14) {
            Image(systemName: "envelope")
                .font(.system(size: 18))
                .foregroundStyle(secondaryText)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text("البريد الإلكتروني")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryText)

                TextField(
                    "smartbill@gmail.com",
                    text: $email
                )
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled(true)
                .foregroundStyle(primaryText)
                .submitLabel(.next)
                .environment(\.layoutDirection, .leftToRight)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 72)
        .background(cardColor)
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(borderColor, lineWidth: 1)
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
    }

    private var passwordField: some View {
        HStack(spacing: 14) {
            Image(systemName: "lock")
                .font(.system(size: 18))
                .foregroundStyle(secondaryText)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text("كلمة المرور")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryText)

                Group {
                    if showPassword {
                        TextField(
                            "كلمة المرور",
                            text: $password
                        )
                    } else {
                        SecureField(
                            "كلمة المرور",
                            text: $password
                        )
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .foregroundStyle(primaryText)
                .submitLabel(.go)
                .environment(\.layoutDirection, .leftToRight)
            }

            Button {
                showPassword.toggle()
            } label: {
                Image(
                    systemName:
                        showPassword
                        ? "eye.slash"
                        : "eye"
                )
                .font(.system(size: 17))
                .foregroundStyle(secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .frame(height: 72)
        .background(cardColor)
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(borderColor, lineWidth: 1)
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
    }

    private var loginButton: some View {
        Button {
            Task {
                await login()
            }
        } label: {
            HStack {
                if isLoading {
                    Spacer()

                    ProgressView()
                        .tint(.white)

                    Spacer()
                } else {
                    Text("دخول")
                        .font(.system(size: 18, weight: .bold))

                    Spacer()

                    Image(systemName: layoutDirection == .rightToLeft ? "arrow.left" : "arrow.right")
                        .font(
                            .system(
                                size: 17,
                                weight: .semibold
                            )
                        )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .padding(.horizontal, 20)
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors:
                        isLoginDisabled
                        ? [
                            Color.gray.opacity(0.7),
                            Color.gray.opacity(0.55)
                        ]
                        : [
                            accentColor,
                            accentColor.opacity(0.72)
                        ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )
            .shadow(
                color:
                    accentColor.opacity(
                        isLoginDisabled ? 0 : 0.18
                    ),
                radius: 14,
                y: 6
            )
        }
        .disabled(isLoginDisabled)
    }

    private var registerButton: some View {
        Button {
            Task {
                await register()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.badge.plus")

                Text("إنشاء حساب جديد")
                    .font(.system(size: 17, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(primaryText)
            .background(cardColor.opacity(0.65))
            .overlay {
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
                .stroke(
                    accentColor.opacity(0.75),
                    lineWidth: 1
                )
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )
        }
    }

    private var background: some View {
        ZStack {
            (
                colorScheme == .dark
                ? Color(
                    red: 0.025,
                    green: 0.04,
                    blue: 0.04
                )
                : Color(
                    red: 0.965,
                    green: 0.975,
                    blue: 0.97
                )
            )
            .ignoresSafeArea()

            Circle()
                .fill(
                    accentColor.opacity(
                        colorScheme == .dark
                        ? 0.10
                        : 0.08
                    )
                )
                .frame(width: 360, height: 360)
                .offset(x: -180, y: -330)

            Circle()
                .fill(
                    accentColor.opacity(
                        colorScheme == .dark
                        ? 0.07
                        : 0.06
                    )
                )
                .frame(width: 420, height: 420)
                .offset(x: 170, y: 430)
        }
    }

    private var accentColor: Color {
        colorScheme == .dark
        ? Color(
            red: 0.40,
            green: 0.63,
            blue: 0.51
        )
        : Color(
            red: 0.20,
            green: 0.48,
            blue: 0.36
        )
    }

    private var cardColor: Color {
        colorScheme == .dark
        ? Color(
            red: 0.075,
            green: 0.095,
            blue: 0.095
        )
        : Color.white.opacity(0.88)
    }

    private var primaryText: Color {
        colorScheme == .dark
        ? .white
        : Color(
            red: 0.07,
            green: 0.10,
            blue: 0.09
        )
    }

    private var secondaryText: Color {
        colorScheme == .dark
        ? Color.white.opacity(0.58)
        : Color.black.opacity(0.52)
    }

    private var borderColor: Color {
        colorScheme == .dark
        ? Color.white.opacity(0.08)
        : Color.black.opacity(0.08)
    }
}

private extension LoginView {
    var isLoginDisabled: Bool {
        isLoading ||
        email
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty ||
        password.isEmpty
    }
}

private extension LoginView {
    /// يفك حالة تسجيل الدخول ورسالة الخادم ومعرف المستخدم.
    struct LoginResponse: Decodable {
        let status: String
        let message: String?
        let user_id: Int?
    }

    /// يحوّل أخطاء الطلب إلى رسائل تميّز تعذر الاتصال عن أخطاء الخادم والاستجابة.
    func authenticationErrorMessage(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotFindHost, .dnsLookupFailed:
                return "تعذر العثور على عنوان الخادم. تحقق من أن نفق Cloudflare الحالي نشط وأن عنوان Debug صحيح."
            case .cannotConnectToHost, .notConnectedToInternet, .networkConnectionLost:
                return "تعذر الاتصال بالخادم. تحقق من اتصال الشبكة وحاول مرة أخرى."
            case .timedOut:
                return "انتهت مهلة الاتصال بالخادم. حاول مرة أخرى."
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate:
                return "تعذر إنشاء اتصال HTTPS آمن بالخادم."
            default:
                return SmartBillLanguage.selected == .english
                    ? "Could not complete the request. Check your connection and try again."
                    : "تعذر إكمال الطلب. تحقق من اتصال الشبكة وحاول مرة أخرى."
            }
        }

        if error is DecodingError || error is CocoaError {
            return "وصل رد من الخادم لكن تعذر قراءة صيغته."
        }

        return SmartBillLanguage.selected == .english
            ? "Could not complete the request. Try again."
            : "تعذر إكمال الطلب. حاول مرة أخرى."
    }

    /// يبني رابط تسجيل الدخول من عنوان الخادم الصالح.
    func loginURL() throws -> URL {
        try ServerConfig.secureEndpoint("login.php")
    }

    @MainActor
    /// يرسل بيانات تسجيل الدخول ويعالج نتيجة المصادقة.
    func login() async {
        message = ""
        isLoading = true

        defer {
            isLoading = false
        }

        do {
            let url = try loginURL()

            ServerSession.debugLog("Login request endpoint=https://\(url.host ?? "unknown")\(url.path); PHPSESSID available before send=\(ServerSession.hasSessionCookie(for: url))")

            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.httpMethod = "POST"

            request.addValue(
                "application/json",
                forHTTPHeaderField: "Content-Type"
            )

            let body: [String: String] = [
                "email":
                    email.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                "password": password
            ]

            request.httpBody =
                try JSONSerialization.data(
                    withJSONObject: body
                )

            let (data, response) =
                try await ServerSession.shared.data(
                    for: request
                )

            guard let http = response as? HTTPURLResponse else {
                message = "استجابة الخادم غير صالحة."
                return
            }

            let setCookieHeaderPresent = http.allHeaderFields.keys.contains {
                String(describing: $0).caseInsensitiveCompare("Set-Cookie") == .orderedSame
            }
            ServerSession.logSessionCookieStatus(for: url, context: "after login response")
            ServerSession.debugLog("Login HTTP \(http.statusCode); HTTP success=\((200...299).contains(http.statusCode)); Set-Cookie header present=\(setCookieHeaderPresent); PHPSESSID stored for endpoint=\(ServerSession.hasSessionCookie(for: url)); response has same HTTPS origin=\(http.url?.scheme == url.scheme && http.url?.host?.lowercased() == url.host?.lowercased())")

            if !(200...299).contains(http.statusCode) {

                message = SmartBillLanguage.selected == .english
                    ? "A server error occurred (\(http.statusCode))."
                    : "حدث خطأ في الخادم (\(http.statusCode))."

                return
            }

            let decoded =
                try JSONDecoder().decode(
                    LoginResponse.self,
                    from: data
                )

            let serverReportedSuccess = decoded.status.lowercased() == "success"
            let sessionCookieStored = ServerSession.hasSessionCookie(for: url)
            ServerSession.debugLog("Login JSON success=\(serverReportedSuccess); PHPSESSID stored for endpoint=\(sessionCookieStored)")

            if serverReportedSuccess {
                guard sessionCookieStored else {
                    message = "تم التحقق من الحساب، لكن تعذر إنشاء جلسة آمنة. تحقق من إعداد جلسة PHP على الخادم ثم حاول مجددًا."
                    return
                }
                let keychainSaved = ServerSession.saveSessionCookie(for: url)
                ServerSession.debugLog("[SessionDebug] PHPSESSID saved to Keychain: \(keychainSaved)")
                if let id = decoded.user_id {
                    UserDefaults.standard.set(
                        id,
                        forKey: "user_id"
                    )
                }

                let cleanEmail =
                    email.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )

                UserDefaults.standard.set(
                    cleanEmail,
                    forKey: "user_email"
                )

                email = ""
                password = ""

                isLoggedIn = true
            } else {
                message =
                    decoded.message ??
                    "خطأ غير معروف"
            }

        } catch {
            if let urlError = error as? URLError {
                ServerSession.debugLog("Login request failed before HTTP response; URLError=\(urlError.code.rawValue)")
            }
            message = authenticationErrorMessage(error)
        }
    }

    /// يبني رابط إنشاء الحساب من عنوان الخادم الصالح.
    func registerURL() throws -> URL {
        try ServerConfig.secureEndpoint("register.php")
    }

    @MainActor
    /// يرسل بيانات الحساب الجديد ويعرض نجاح العملية أو خطأها.
    func register() async {
        message = ""
        isLoading = true

        defer {
            isLoading = false
        }

        do {
            let url = try registerURL()

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 15

            request.addValue(
                "application/json",
                forHTTPHeaderField: "Content-Type"
            )

            let body: [String: String] = [
                "email":
                    email.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                "password": password
            ]

            request.httpBody =
                try JSONSerialization.data(
                    withJSONObject: body
                )

            let (data, response) =
                try await ServerSession.shared.data(
                    for: request
                )

            guard let http = response as? HTTPURLResponse else {
                message = "استجابة الخادم غير صالحة."
                return
            }

            guard (200...299).contains(http.statusCode) else {
                message = SmartBillLanguage.selected == .english
                    ? "A server error occurred (\(http.statusCode))."
                    : "حدث خطأ في الخادم (\(http.statusCode))."
                return
            }

            let decoded = try JSONDecoder().decode(LoginResponse.self, from: data)

            if decoded.status.lowercased() == "success" {

                message =
                    "تم إنشاء الحساب بنجاح ✅"

            } else {
                message = decoded.message ?? "فشل إنشاء الحساب"
            }

        } catch {
            message = authenticationErrorMessage(error)
        }
    }
}

/// يختار شاشة الدخول أو التطبيق وفق حالة isLoggedIn المحلية.
struct RootView: View {
    @AppStorage("isLoggedIn")
    private var isLoggedIn = false
    @State private var sessionRestorationComplete = false

    var body: some View {
        Group {
            if !sessionRestorationComplete {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoggedIn {
                ContentView()
            } else {
                LoginView()
            }
        }
        .task {
            guard !sessionRestorationComplete else { return }
            let loginStateAtStartup = isLoggedIn
            ServerSession.debugLog("[SessionDebug] app startup")
            ServerSession.debugLog("[SessionDebug] isLoggedIn at session check: \(loginStateAtStartup)")
            guard let loginURL = try? ServerConfig.secureEndpoint("login.php") else {
                isLoggedIn = false
                sessionRestorationComplete = true
                return
            }

            let cookieAvailable = ServerSession.restoreSessionCookie(for: loginURL)
            ServerSession.debugLog("[SessionDebug] PHPSESSID available after Keychain restore: \(cookieAvailable)")
            if cookieAvailable {
                // This restores a candidate session only. The first protected API response
                // remains authoritative and clears local credentials on authentication_required.
                isLoggedIn = true
            } else if loginStateAtStartup {
                ServerSession.debugLog("[SessionDebug] RootView reset login state: no restorable PHPSESSID")
                isLoggedIn = false
            }
            sessionRestorationComplete = true
        }
    }
}

#Preview {
    LoginView()
}
