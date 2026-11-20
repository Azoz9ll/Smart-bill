import Foundation
import Security

/// One cookie-aware URLSession shared by authentication and authenticated API requests.
enum ServerSession {
    static let shared = makeSession()

    private struct StoredSessionCookie: Codable {
        let value: String
        let domain: String
        let path: String
        let secure: Bool
        let httpOnly: Bool
        let expiresDate: Date?

        init(cookie: HTTPCookie) {
            value = cookie.value
            domain = cookie.domain
            path = cookie.path
            secure = cookie.isSecure
            httpOnly = cookie.isHTTPOnly
            expiresDate = cookie.expiresDate
        }
    }

    private static var keychainService: String {
        "\(Bundle.main.bundleIdentifier ?? "SmartBill").ServerSession"
    }

    private static func keychainQuery(for url: URL) -> [String: Any]? {
        guard let host = url.host?.lowercased() else { return nil }
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "PHPSESSID.\(host)"
        ]
    }

    /// Saves the session cookie in this device's Keychain without logging its value.
    @discardableResult
    static func saveSessionCookie(for url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let cookie = cookieStorage.cookies(for: url)?.first(where: { $0.name == "PHPSESSID" }),
              let query = keychainQuery(for: url),
              let data = try? JSONEncoder().encode(StoredSessionCookie(cookie: cookie)) else {
            return false
        }

        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }
        return updateStatus == errSecSuccess
    }

    /// Restores a Keychain cookie to the shared cookie store; this does not verify server validity.
    @discardableResult
    static func restoreSessionCookie(for url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        if hasSessionCookie(for: url) { return true }
        guard let query = keychainQuery(for: url) else { return false }

        var readQuery = query
        readQuery[kSecReturnData as String] = true
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(readQuery as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return false }
        guard let storedCookie = try? JSONDecoder().decode(StoredSessionCookie.self, from: data),
              storedCookie.expiresDate.map({ $0 > Date() }) ?? true,
              cookieDomain(storedCookie.domain, matches: url.host) else {
            clearSessionCookie(for: url)
            return false
        }

        var properties: [HTTPCookiePropertyKey: Any] = [
            .domain: storedCookie.domain,
            .path: storedCookie.path,
            .name: "PHPSESSID",
            .value: storedCookie.value,
            .secure: storedCookie.secure ? "TRUE" : "FALSE"
        ]
        if let expiresDate = storedCookie.expiresDate {
            properties[.expires] = expiresDate
        }
        if storedCookie.httpOnly {
            properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
        }
        guard let cookie = HTTPCookie(properties: properties) else {
            clearSessionCookie(for: url)
            return false
        }

        cookieStorage.setCookie(cookie)
        return hasSessionCookie(for: url)
    }

    /// Removes the cookie from both Keychain and the shared cookie store.
    static func clearSessionCookie(for url: URL) {
        cookieStorage.cookies(for: url)?
            .filter { $0.name == "PHPSESSID" }
            .forEach(cookieStorage.deleteCookie)
        guard let query = keychainQuery(for: url) else { return }
        SecItemDelete(query as CFDictionary)
    }

    private static var cookieStorage: HTTPCookieStorage {
        shared.configuration.httpCookieStorage ?? HTTPCookieStorage.shared
    }

    private static func cookieDomain(_ domain: String, matches host: String?) -> Bool {
        guard let host else { return false }
        let normalizedDomain = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let normalizedHost = host.lowercased()
        return normalizedHost == normalizedDomain || normalizedHost.hasSuffix(".\(normalizedDomain)")
    }

    /// Logs only whether the PHP session cookie exists; never exposes its value.
    static func logSessionCookieStatus(for url: URL, context: String) {
        debugLog("[SessionDebug] \(context)")
        debugLog("[SessionDebug] PHPSESSID exists: \(hasSessionCookie(for: url))")
    }

    /// Checks for the PHP session cookie scoped to this exact HTTPS endpoint; never exposes its value.
    static func hasSessionCookie(for url: URL) -> Bool {
        let storage = shared.configuration.httpCookieStorage ?? HTTPCookieStorage.shared
        return storage.cookies(for: url)?.contains { $0.name == "PHPSESSID" } ?? false
    }

    nonisolated static func debugLog(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }

    static func makeSession(configuration initialConfiguration: URLSessionConfiguration = .default) -> URLSession {
        let configuration = initialConfiguration
        if configuration.httpCookieStorage == nil {
            configuration.httpCookieStorage = HTTPCookieStorage.shared
        }
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        return URLSession(configuration: configuration)
    }
}
