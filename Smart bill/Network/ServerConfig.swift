//
//  ServerConfig.swift
//  Smart Bill
//
//  Purpose:
//  تجميع عناوين الخدمات المشتركة في التطبيق.
//
//  Responsibilities:
//  - توفير baseURL لمسارات PHP المستخدمة في الشاشات
//  - توفير رابط البحث في Apple Maps
//

//
//  ma.swift
//  Smart bill
//
//  Created by Abdulaziz on 03/05/2026.
//

import Foundation

/// تجميع عناوين الخدمات المشتركة في التطبيق.
enum ServerConfig {
    enum ConfigurationError: LocalizedError {
        case invalidBaseURL
        case invalidEndpoint

        var errorDescription: String? {
            switch self {
            case .invalidBaseURL:
                return "عنوان خادم SmartBill غير مضبوط أو غير صالح."
            case .invalidEndpoint:
                return "مسار خدمة SmartBill غير صالح."
            }
        }
    }

    static var baseURL: String {
        #if DEBUG
        if let configured = ProcessInfo.processInfo.environment["SMARTBILL_API_BASE_URL"] {
            let candidate = normalized(configured)
            if isValidOrigin(candidate, requireHTTPS: false) {
                return candidate
            }
        }
        // Use the same explicit API origin on simulator and device. Never silently
        // fall back to a device-specific or localhost address.
        let configured = normalized(Bundle.main.object(forInfoDictionaryKey: "SMARTBILL_API_BASE_URL") as? String ?? "")
        return isValidOrigin(configured, requireHTTPS: false) ? configured : ""
        #else
        // Production must be configured with the verified HTTPS API hostname.
        // Never fall back to an unrelated host or the scraper's sync endpoint.
        let configured = normalized(Bundle.main.object(forInfoDictionaryKey: "SMARTBILL_API_BASE_URL") as? String ?? "")
        return isValidOrigin(configured, requireHTTPS: true) ? configured : ""
        #endif
    }

    /// Builds an absolute API URL while validating the configured origin and path.
    static func endpoint(_ path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        let route = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !route.isEmpty, !route.contains(".."), !route.contains("?") else {
            throw ConfigurationError.invalidEndpoint
        }

        guard var components = URLComponents(string: baseURL),
              let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              components.host != nil,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else {
            throw ConfigurationError.invalidBaseURL
        }

        #if !DEBUG
        guard scheme == "https" else { throw ConfigurationError.invalidBaseURL }
        #endif

        let prefix = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [prefix, route].filter { !$0.isEmpty }.joined(separator: "/")
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url, url.host != nil else {
            throw ConfigurationError.invalidBaseURL
        }
        return url
    }

    /// Authentication and receipt analysis carry credentials/cookies, so they require HTTPS in Debug too.
    static func secureEndpoint(_ path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        let url = try endpoint(path, queryItems: queryItems)
        guard url.scheme?.lowercased() == "https" else {
            throw ConfigurationError.invalidBaseURL
        }
        return url
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func isValidOrigin(_ value: String, requireHTTPS: Bool) -> Bool {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              (!requireHTTPS || scheme == "https"),
              components.host != nil,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else {
            return false
        }
        return true
    }

    static let appleMapsSearch = "http://maps.apple.com/?q="
}
