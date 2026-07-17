import Foundation
import Testing
@testable import CodexBarCore

struct CostUsageCacheTests {
    @Test
    func cache_file_URL_uses_provider_artifact_versions() {
        let root = URL(fileURLWithPath: "/tmp/codexbar-cost-cache", isDirectory: true)

        let codexURL = CostUsageCacheIO.cacheFileURL(provider: .codex, cacheRoot: root)
        let claudeURL = CostUsageCacheIO.cacheFileURL(provider: .claude, cacheRoot: root)
        let vertexURL = CostUsageCacheIO.cacheFileURL(provider: .vertexai, cacheRoot: root)

        #expect(codexURL.lastPathComponent == "codex-v10.json")
        #expect(claudeURL.lastPathComponent == "claude-v5.json")
        #expect(vertexURL.lastPathComponent == "vertexai-v5.json")
    }

    @Test
    func cost_cache_ignores_predecessor_artifact_with_persisted_offset() throws {
        let root = try self.makeTemporaryCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let legacyURL = root
            .appendingPathComponent("cost-usage", isDirectory: true)
            .appendingPathComponent("codex-v9.json", isDirectory: false)
        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let producerKey = try #require(CostUsageCacheIO.currentProducerKey(provider: .codex))
        let legacy = """
        {
          "version": 1,
          "producerKey": "\(producerKey)",
          "lastScanUnixMs": 999,
          "files": {
            "/tmp/session.jsonl": {
              "mtimeUnixMs": 1,
              "size": 100,
              "days": {},
              "parsedBytes": 100
            }
          },
          "days": {}
        }
        """
        try legacy.write(to: legacyURL, atomically: false, encoding: .utf8)

        let loaded = CostUsageCacheIO.load(provider: .codex, cacheRoot: root)

        #expect(loaded.lastScanUnixMs == 0)
        #expect(loaded.files.isEmpty)
    }

    @Test
    func Pi_session_cache_ignores_predecessor_artifact_with_persisted_offset() throws {
        let root = try self.makeTemporaryCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let legacyURL = root
            .appendingPathComponent("cost-usage", isDirectory: true)
            .appendingPathComponent("pi-sessions-v5.json", isDirectory: false)
        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        var legacy = PiSessionCostCache(version: 5)
        legacy.lastScanUnixMs = 999
        legacy.files = [
            "/tmp/session.jsonl": PiSessionFileUsage(
                mtimeUnixMs: 1,
                size: 100,
                parsedBytes: 100,
                lastModelContext: nil,
                contributions: [:]),
        ]
        try JSONEncoder().encode(legacy).write(to: legacyURL)

        let loaded = PiSessionCostCacheIO.load(cacheRoot: root)

        #expect(loaded.version == 6)
        #expect(loaded.lastScanUnixMs == 0)
        #expect(loaded.files.isEmpty)
    }

    @Test
    func cache_load_requires_matching_producer_key() throws {
        let root = try self.makeTemporaryCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        var cache = CostUsageCache()
        cache.lastScanUnixMs = 123
        cache.days = ["2026-05-18": ["gpt-5.5": [1, 2, 3]]]

        CostUsageCacheIO.save(
            provider: .codex,
            cache: cache,
            cacheRoot: root,
            producerKey: "codex:cu:p1111111111111111")

        let loaded = CostUsageCacheIO.load(
            provider: .codex,
            cacheRoot: root,
            producerKey: "codex:cu:p1111111111111111")
        #expect(loaded.producerKey == "codex:cu:p1111111111111111")
        #expect(loaded.lastScanUnixMs == 123)
        #expect(loaded.days["2026-05-18"]?["gpt-5.5"] == [1, 2, 3])

        let stale = CostUsageCacheIO.load(
            provider: .codex,
            cacheRoot: root,
            producerKey: "codex:cu:p2222222222222222")
        #expect(stale.lastScanUnixMs == 0)
        #expect(stale.files.isEmpty)
        #expect(stale.days.isEmpty)
    }

    @Test
    func legacy_cache_without_producer_key_is_ignored() throws {
        let root = try self.makeTemporaryCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let url = CostUsageCacheIO.cacheFileURL(provider: .codex, cacheRoot: root)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let legacy = """
        {
          "version": 1,
          "lastScanUnixMs": 999,
          "files": {},
          "days": {
            "2026-05-18": {
              "gpt-5": [1, 0, 0]
            }
          }
        }
        """
        try legacy.write(to: url, atomically: false, encoding: .utf8)

        let loaded = CostUsageCacheIO.load(
            provider: .codex,
            cacheRoot: root,
            producerKey: "codex:cu:p1111111111111111")

        #expect(loaded.lastScanUnixMs == 0)
        #expect(loaded.days.isEmpty)
    }

    @Test
    func current_codex_cache_rejects_pre_interleave_containment_producers() throws {
        // Interleave containment (#2037) changed cumulative delta semantics, so caches from
        // previously compatible parser hashes must be rebuilt instead of reused.
        let root = try self.makeTemporaryCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        for legacyProducerKey in ["codex:cu:p3c27f997569eb3c5", "codex:cu:pc54070a94f6419ea"] {
            var cache = CostUsageCache()
            cache.lastScanUnixMs = 123
            cache.days = ["2026-05-18": ["gpt-5.5": [1, 2, 3]]]
            CostUsageCacheIO.save(
                provider: .codex,
                cache: cache,
                cacheRoot: root,
                producerKey: legacyProducerKey)

            let loaded = CostUsageCacheIO.load(provider: .codex, cacheRoot: root)

            #expect(loaded.lastScanUnixMs == 0)
            #expect(loaded.days.isEmpty)
        }
    }

    @Test
    func non_codex_cache_does_not_require_producer_key() throws {
        let root = try self.makeTemporaryCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let url = CostUsageCacheIO.cacheFileURL(provider: .claude, cacheRoot: root)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let legacy = """
        {
          "version": 1,
          "lastScanUnixMs": 999,
          "files": {},
          "days": {
            "2026-05-18": {
              "claude-sonnet-4-5": [1, 0, 0]
            }
          }
        }
        """
        try legacy.write(to: url, atomically: false, encoding: .utf8)

        let loaded = CostUsageCacheIO.load(provider: .claude, cacheRoot: root)

        #expect(loaded.lastScanUnixMs == 999)
        #expect(loaded.days["2026-05-18"]?["claude-sonnet-4-5"] == [1, 0, 0])
    }

    @Test
    func current_producer_key_uses_generated_parser_hash_for_codex_only() {
        let codexKey = CostUsageCacheIO.currentProducerKey(
            provider: .codex,
            parserHash: "abc1234567890def")
        let standaloneKey = CostUsageCacheIO.currentProducerKey(
            provider: .claude,
            parserHash: "abc1234567890def")

        #expect(codexKey == "codex:cu:pabc1234567890def")
        #expect(standaloneKey == nil)
    }

    @Test
    func generated_parser_hash_is_stable_short_lowercase_hex() {
        let hash = CodexParserHash.value

        #expect(hash.range(of: #"^[0-9a-f]{16}$"#, options: .regularExpression) != nil)
        #expect(CostUsageCacheIO.currentProducerKey(provider: .codex) == "codex:cu:p\(hash)")
    }

    private func makeTemporaryCacheRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-cost-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
