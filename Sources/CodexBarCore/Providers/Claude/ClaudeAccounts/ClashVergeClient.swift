import Foundation

public struct ClashProxyGroupStatus: Equatable, Sendable {
    public let now: String?
    public let all: [String]

    public init(now: String?, all: [String]) {
        self.now = now
        self.all = all
    }
}

public enum ClashVergeClientError: LocalizedError, Equatable, Sendable {
    case unreachable(detail: String)
    case groupMissing(group: String)
    case nodeMissing(group: String, node: String)
    case invalidResponse(detail: String)

    public var errorDescription: String? {
        switch self {
        case let .unreachable(detail):
            "Clash Verge is unreachable. Check that it is running and the socket path is correct. (\(detail))"
        case let .groupMissing(group):
            "Clash proxy group '\(group)' does not exist."
        case let .nodeMissing(group, node):
            "Clash node '\(node)' is not available in group '\(group)'. Rebind the account to a current node."
        case let .invalidResponse(detail):
            "Clash Verge returned an unexpected response. (\(detail))"
        }
    }
}

public protocol ClashProxyControlling: Sendable {
    func groupStatus(group: String) async throws -> ClashProxyGroupStatus
    func switchNode(group: String, node: String) async throws
}

/// mihomo REST client over the Clash Verge unix domain socket.
///
/// URLSession cannot speak unix sockets, so requests shell out to `/usr/bin/curl`
/// with a fixed argument array (never a shell) — see ADR-002 in the design doc.
public struct ClashVergeClient: ClashProxyControlling {
    public typealias CurlRunner = @Sendable (_ arguments: [String]) async throws -> String

    public static let requestTimeoutSeconds = 3

    private let socketPath: String
    private let runCurl: CurlRunner

    public init(socketPath: String, runCurl: CurlRunner? = nil) {
        self.socketPath = socketPath
        self.runCurl = runCurl ?? Self.defaultCurlRunner
    }

    public func groupStatus(group: String) async throws -> ClashProxyGroupStatus {
        let response = try await self.request(method: "GET", path: "/proxies/\(Self.encodePathComponent(group))")
        switch response.status {
        case 200:
            return try Self.parseGroupStatus(body: response.body)
        case 404:
            throw ClashVergeClientError.groupMissing(group: group)
        default:
            throw ClashVergeClientError.invalidResponse(detail: "HTTP \(response.status)")
        }
    }

    public func switchNode(group: String, node: String) async throws {
        guard let data = try? JSONSerialization.data(withJSONObject: ["name": node]),
              let body = String(bytes: data, encoding: .utf8)
        else {
            throw ClashVergeClientError.invalidResponse(detail: "failed to encode request body")
        }
        let response = try await self.request(
            method: "PUT",
            path: "/proxies/\(Self.encodePathComponent(group))",
            body: body)
        switch response.status {
        case 200...299:
            return
        case 400, 404:
            throw ClashVergeClientError.nodeMissing(group: group, node: node)
        default:
            throw ClashVergeClientError.invalidResponse(detail: "HTTP \(response.status)")
        }
    }

    // MARK: - Request plumbing

    private func request(
        method: String,
        path: String,
        body: String? = nil) async throws -> (status: Int, body: String)
    {
        var arguments = [
            "--silent",
            "--show-error",
            "--max-time", String(Self.requestTimeoutSeconds),
            "--unix-socket", self.socketPath,
            "--write-out", "\n%{http_code}",
            "--request", method,
        ]
        if let body {
            arguments += ["--header", "Content-Type: application/json", "--data", body]
        }
        arguments.append("http://localhost\(path)")

        let output: String
        do {
            output = try await self.runCurl(arguments)
        } catch {
            throw ClashVergeClientError.unreachable(detail: error.localizedDescription)
        }
        return try Self.splitStatusLine(output: output)
    }

    static func splitStatusLine(output: String) throws -> (status: Int, body: String) {
        guard let newlineIndex = output.lastIndex(of: "\n"),
              let status = Int(output[output.index(after: newlineIndex)...]
                  .trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            throw ClashVergeClientError.invalidResponse(detail: "missing HTTP status marker")
        }
        return (status, String(output[..<newlineIndex]))
    }

    static func parseGroupStatus(body: String) throws -> ClashProxyGroupStatus {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ClashVergeClientError.invalidResponse(detail: "group status is not a JSON object")
        }
        let all = (object["all"] as? [Any])?.compactMap { $0 as? String } ?? []
        let now = object["now"] as? String
        return ClashProxyGroupStatus(now: now, all: all)
    }

    static func encodePathComponent(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: self.pathComponentAllowed) ?? component
    }

    private static let pathComponentAllowed: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return allowed
    }()

    @Sendable
    private static func defaultCurlRunner(arguments: [String]) async throws -> String {
        let result = try await SubprocessRunner.run(
            binary: "/usr/bin/curl",
            arguments: arguments,
            environment: [:],
            timeout: TimeInterval(Self.requestTimeoutSeconds + 2),
            label: "clash-verge curl")
        return result.stdout
    }
}
