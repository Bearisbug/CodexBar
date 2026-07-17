import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Result of one `API-004` refresh call.
public struct ClaudeRefreshedTokens: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

public enum ClaudeAccountTokenRefreshError: LocalizedError, Equatable, Sendable {
    case requestFailed(detail: String)
    case rejected(status: Int, detail: String?)

    public var errorDescription: String? {
        switch self {
        case let .requestFailed(detail):
            "Token refresh request failed: \(detail)"
        case let .rejected(status, detail):
            "Token refresh rejected (HTTP \(status)\(detail.map { ", \($0)" } ?? "")). "
                + "Sign the account in with `claude /login` and capture it again."
        }
    }
}

/// Side-effect-free refresh of a backup's OAuth tokens (design doc `API-004`).
///
/// Deliberately bypasses `ClaudeOAuthCredentialsStore`'s cache writes and failure
/// gates: this refreshes an arbitrary account's backup mid-switch, not the ambient
/// credential the store owns. Endpoint and client id are shared with the store.
enum ClaudeAccountTokenRefresher {
    static func refresh(
        refreshToken: String,
        transport: any ProviderHTTPTransport = ProviderHTTPClient.shared) async throws -> ClaudeRefreshedTokens
    {
        guard let url = URL(string: ClaudeOAuthCredentialsStore.tokenRefreshEndpoint) else {
            throw ClaudeAccountTokenRefreshError.requestFailed(detail: "invalid token endpoint URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: ClaudeOAuthCredentialsStore.oauthClientID),
        ]
        request.httpBody = (components.percentEncodedQuery ?? "").data(using: .utf8)

        let response: ProviderHTTPResponse
        do {
            response = try await transport.response(for: request)
        } catch {
            throw ClaudeAccountTokenRefreshError.requestFailed(detail: error.localizedDescription)
        }
        guard response.statusCode == 200 else {
            let body = String(data: response.data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let shortened = body.map { $0.count > 200 ? String($0.prefix(200)) + "…" : $0 }
            throw ClaudeAccountTokenRefreshError.rejected(status: response.statusCode, detail: shortened)
        }

        struct RefreshResponse: Decodable {
            let accessToken: String
            let refreshToken: String?
            let expiresIn: Int

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
                case expiresIn = "expires_in"
            }
        }

        let decoded: RefreshResponse
        do {
            decoded = try JSONDecoder().decode(RefreshResponse.self, from: response.data)
        } catch {
            throw ClaudeAccountTokenRefreshError.requestFailed(detail: "malformed refresh response")
        }
        return ClaudeRefreshedTokens(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken ?? refreshToken,
            expiresAt: Date(timeIntervalSinceNow: TimeInterval(decoded.expiresIn)))
    }
}
