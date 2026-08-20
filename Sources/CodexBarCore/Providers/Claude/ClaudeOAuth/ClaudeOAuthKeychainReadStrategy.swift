import Foundation

public enum ClaudeOAuthKeychainReadStrategy: String, Sendable, Codable, CaseIterable {
    case securityFramework
    case securityCLIExperimental
}

public enum ClaudeOAuthKeychainReadStrategyPreference {
    private static let userDefaultsKey = "claudeOAuthKeychainReadStrategy"

    #if DEBUG
    @TaskLocal private static var taskOverride: ClaudeOAuthKeychainReadStrategy?
    #endif

    public static func current(userDefaults: UserDefaults = .standard) -> ClaudeOAuthKeychainReadStrategy {
        #if DEBUG
        if let taskOverride { return taskOverride }
        #endif
        if let raw = userDefaults.string(forKey: self.userDefaultsKey) {
            // Fork: honor securityCLIExperimental instead of coercing it back. Ad-hoc builds have
            // no TeamIdentifier, so "Always Allow" can never add them to the item's partition list
            // and an in-process SecItem read re-prompts forever. `/usr/bin/security` is already in
            // both the trusted-application list and the `apple-tool:` partition, so it reads silently.
            return ClaudeOAuthKeychainReadStrategy(rawValue: raw) ?? .securityFramework
        }
        return .securityFramework
    }

    #if DEBUG
    public static func withTaskOverrideForTesting<T>(
        _ strategy: ClaudeOAuthKeychainReadStrategy?,
        operation: () throws -> T) rethrows -> T
    {
        try self.$taskOverride.withValue(strategy) {
            try operation()
        }
    }

    public static func withTaskOverrideForTesting<T>(
        _ strategy: ClaudeOAuthKeychainReadStrategy?,
        operation: () async throws -> T) async rethrows -> T
    {
        try await self.$taskOverride.withValue(strategy) {
            try await operation()
        }
    }

    public static var currentTaskOverrideForTesting: ClaudeOAuthKeychainReadStrategy? {
        self.taskOverride
    }
    #endif
}
