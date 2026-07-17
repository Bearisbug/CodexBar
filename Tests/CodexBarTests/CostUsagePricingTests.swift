import Foundation
import Testing
@testable import CodexBarCore

struct CostUsagePricingTests {
    @Test
    func normalizes_codex_model_variants_exactly() {
        #expect(CostUsagePricing.normalizeCodexModel("openai/gpt-5-codex") == "gpt-5-codex")
        #expect(CostUsagePricing.normalizeCodexModel("gpt-5.2-codex") == "gpt-5.2-codex")
        #expect(CostUsagePricing.normalizeCodexModel("gpt-5.1-codex-max") == "gpt-5.1-codex-max")
        #expect(CostUsagePricing.normalizeCodexModel("gpt-5.4-pro-2026-03-05") == "gpt-5.4-pro")
        #expect(CostUsagePricing.normalizeCodexModel("gpt-5.4-mini-2026-03-17") == "gpt-5.4-mini")
        #expect(CostUsagePricing.normalizeCodexModel("gpt-5.4-nano-2026-03-17") == "gpt-5.4-nano")
        #expect(CostUsagePricing.normalizeCodexModel("gpt-5.5-2026-04-23") == "gpt-5.5")
        #expect(CostUsagePricing.normalizeCodexModel("gpt-5.5-pro-2026-04-23") == "gpt-5.5-pro")
        #expect(CostUsagePricing.normalizeCodexModel("gpt-5.3-codex-2026-03-05") == "gpt-5.3-codex")
        #expect(CostUsagePricing.normalizeCodexModel("gpt-5.3-codex-spark") == "gpt-5.3-codex-spark")
        #expect(CostUsagePricing.normalizeCodexModel("openai/gpt-5.6-sol") == "gpt-5.6-sol")
        #expect(CostUsagePricing.normalizeCodexModel("openai/gpt-5.6-terra") == "gpt-5.6-terra")
        #expect(CostUsagePricing.normalizeCodexModel("gpt-5.6-luna") == "gpt-5.6-luna")
        #expect(CostUsagePricing.normalizeCodexModel("gpt-5.6") == "gpt-5.6-sol")
        // Fictitious dated suffixes only exercise normalize stripping (not released snapshot IDs).
        #expect(CostUsagePricing.normalizeCodexModel("gpt-5.6-sol-2099-01-01") == "gpt-5.6-sol")
        #expect(CostUsagePricing.normalizeCodexModel("openai/gpt-5.6-terra-2099-01-01") == "gpt-5.6-terra")
    }

    @Test
    func unattributed_codex_usage_stays_unpriced_despite_a_catalog_collision() throws {
        let root = try Self.seedModelsDevCache("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "unknown": {
                "id": "unknown",
                "cost": { "input": 99, "output": 199 }
              }
            }
          }
        }
        """)

        let cost = CostUsagePricing.codexCostUSD(
            model: CostUsagePricing.codexUnattributedModel,
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5,
            modelsDevCacheRoot: root)

        #expect(cost == nil)
    }

    @Test
    func codex_cost_supports_gpt51_codex_max() {
        let cost = CostUsagePricing.codexCostUSD(
            model: "gpt-5.1-codex-max",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5)
        #expect(cost != nil)
    }

    @Test
    func codex_cost_supports_gpt53_codex() {
        let cost = CostUsagePricing.codexCostUSD(
            model: "gpt-5.3-codex",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5)
        #expect(cost != nil)
    }

    @Test
    func codex_cost_supports_gpt54_mini_and_nano() {
        let mini = CostUsagePricing.codexCostUSD(
            model: "gpt-5.4-mini-2026-03-17",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5)
        let nano = CostUsagePricing.codexCostUSD(
            model: "gpt-5.4-nano",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5)

        #expect(mini != nil)
        #expect(nano != nil)
    }

    @Test
    func codex_cost_supports_gpt55_bundled_fallback() throws {
        let root = try Self.cacheRoot()
        let cost = CostUsagePricing.codexCostUSD(
            model: "openai/gpt-5.5-2026-04-23",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5,
            modelsDevCacheRoot: root)

        // Codex `input_tokens` includes cached reads, so only the 90 non-cached tokens are
        // billed at the input rate; the 10 cached tokens are billed at the cache rate.
        let expected = (90.0 * 5e-6) + (10.0 * 5e-7) + (5.0 * 3e-5)
        #expect(cost == expected)
    }

    @Test
    func codex_cost_supports_gpt56_sol_terra_luna_bundled_fallback() throws {
        // Empty models.dev cache root forces the built-in table for GPT-5.6 tiers.
        let root = try Self.cacheRoot()

        let sol = CostUsagePricing.codexCostUSD(
            model: "openai/gpt-5.6-sol",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5,
            modelsDevCacheRoot: root)
        let terra = CostUsagePricing.codexCostUSD(
            model: "gpt-5.6-terra",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5,
            modelsDevCacheRoot: root)
        let luna = CostUsagePricing.codexCostUSD(
            model: "gpt-5.6-luna",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5,
            modelsDevCacheRoot: root)
        let alias = CostUsagePricing.codexCostUSD(
            model: "gpt-5.6",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5,
            modelsDevCacheRoot: root)

        // Rates per token: Sol $5/$30 per 1M, Terra $2.50/$15, Luna $1/$6;
        // cache read is 10% of input. Non-cached input is 90 tokens.
        let expectedValueLine138 = (90.0 * 5e-6) + (10.0 * 5e-7) + (5.0 * 3e-5)
        #expect(sol == expectedValueLine138)
        let expectedValueLine139 = (90.0 * 2.5e-6) + (10.0 * 2.5e-7) + (5.0 * 1.5e-5)
        #expect(terra == expectedValueLine139)
        let expectedValueLine140 = (90.0 * 1e-6) + (10.0 * 1e-7) + (5.0 * 6e-6)
        #expect(luna == expectedValueLine140)
        // Unsuffixed gpt-5.6 alias routes to Sol.
        #expect(alias == sol)
    }

    @Test
    func codex_models_dev_falls_back_from_gpt56_alias_to_canonical_sol_pricing() throws {
        let canonicalOnlyRoot = try Self.seedModelsDevCache("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "gpt-5.6-sol": {
                "id": "gpt-5.6-sol",
                "cost": { "input": 7, "output": 31 }
              }
            }
          }
        }
        """)
        let aliasAndCanonicalRoot = try Self.seedModelsDevCache("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "gpt-5.6": {
                "id": "gpt-5.6",
                "cost": { "input": 3, "output": 13 }
              },
              "gpt-5.6-sol": {
                "id": "gpt-5.6-sol",
                "cost": { "input": 7, "output": 31 }
              }
            }
          }
        }
        """)

        let canonicalFallback = CostUsagePricing.codexCostUSD(
            model: "gpt-5.6",
            inputTokens: 100,
            cachedInputTokens: 0,
            outputTokens: 0,
            modelsDevCacheRoot: canonicalOnlyRoot)
        let exactAlias = CostUsagePricing.codexCostUSD(
            model: "gpt-5.6",
            inputTokens: 100,
            cachedInputTokens: 0,
            outputTokens: 0,
            modelsDevCacheRoot: aliasAndCanonicalRoot)

        #expect(canonicalFallback == 100.0 * 7e-6)
        #expect(exactAlias == 100.0 * 3e-6)
    }

    @Test
    func codex_pricing_key_distinguishes_an_empty_long_context_block_from_no_block() throws {
        let withoutLongContext = try Self.modelsDevArtifact("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "gpt-5.6-sol": {
                "id": "gpt-5.6-sol",
                "cost": { "input": 5, "output": 30 }
              }
            }
          }
        }
        """)
        let withEmptyLongContext = try Self.modelsDevArtifact("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "gpt-5.6-sol": {
                "id": "gpt-5.6-sol",
                "cost": {
                  "input": 5,
                  "output": 30,
                  "context_over_200k": {}
                }
              }
            }
          }
        }
        """)

        let withoutKey = CostUsagePricingKey.codex(
            modelsDevArtifact: withoutLongContext,
            formulaVersion: 1)
        let withEmptyKey = CostUsagePricingKey.codex(
            modelsDevArtifact: withEmptyLongContext,
            formulaVersion: 1)

        #expect(withoutKey != withEmptyKey)
    }

    @Test
    func codex_cost_applies_gpt56_long_context_rates() throws {
        let root = try Self.cacheRoot()
        let sol = CostUsagePricing.codexCostUSD(
            model: "gpt-5.6-sol",
            inputTokens: 272_001,
            cachedInputTokens: 10,
            outputTokens: 10,
            cacheWriteInputTokens: 20,
            modelsDevCacheRoot: root)
        let terra = CostUsagePricing.codexCostUSD(
            model: "gpt-5.6-terra",
            inputTokens: 272_001,
            cachedInputTokens: 10,
            outputTokens: 10,
            cacheWriteInputTokens: 20,
            modelsDevCacheRoot: root)
        let luna = CostUsagePricing.codexCostUSD(
            model: "gpt-5.6-luna",
            inputTokens: 272_001,
            cachedInputTokens: 10,
            outputTokens: 10,
            cacheWriteInputTokens: 20,
            modelsDevCacheRoot: root)

        // Long-context (>272K) rates apply to the entire request. Total input contains 10 cached,
        // 20 cache-write, and 271,971 ordinary input tokens.
        let expectedValueLine265 = (271_971.0 * 1e-5) + (10.0 * 1e-6) + (20.0 * 1.25e-5) + (10.0 * 4.5e-5)
        #expect(sol == expectedValueLine265)
        let expectedValueLine266 = (271_971.0 * 5e-6) + (10.0 * 5e-7) + (20.0 * 6.25e-6) + (10.0 * 2.25e-5)
        #expect(terra == expectedValueLine266)
        let expectedValueLine267 = (271_971.0 * 2e-6) + (10.0 * 2e-7) + (20.0 * 2.5e-6) + (10.0 * 9e-6)
        #expect(luna == expectedValueLine267)
    }

    @Test
    func codex_cost_bills_gpt56_cache_writes_at_one_point_two_five_x_input() throws {
        let root = try Self.cacheRoot()
        // Total prompt 100: 70 uncached + 20 cache-write + 10 cache-read.
        let sol = CostUsagePricing.codexCostUSD(
            model: "gpt-5.6-sol",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5,
            cacheWriteInputTokens: 20,
            modelsDevCacheRoot: root)

        let expected = (70.0 * 5e-6) + (10.0 * 5e-7) + (20.0 * 6.25e-6) + (5.0 * 3e-5)
        #expect(sol == expected)
    }

    @Test
    func codex_priority_cost_supports_gpt56_tiers() {
        let sol = CostUsagePricing.codexPriorityCostUSD(
            model: "gpt-5.6-sol",
            inputTokens: 100,
            cachedInputTokens: 20,
            outputTokens: 10)
        let terra = CostUsagePricing.codexPriorityCostUSD(
            model: "gpt-5.6-terra",
            inputTokens: 100,
            cachedInputTokens: 20,
            outputTokens: 10)
        let luna = CostUsagePricing.codexPriorityCostUSD(
            model: "gpt-5.6-luna",
            inputTokens: 100,
            cachedInputTokens: 20,
            outputTokens: 10)

        // Priority is 2x short-context rates (Sol input $10/1M, etc.).
        let expectedValueLine305 = (80.0 * 1e-5) + (20.0 * 1e-6) + (10.0 * 6e-5)
        #expect(sol == expectedValueLine305)
        let expectedValueLine306 = (80.0 * 5e-6) + (20.0 * 5e-7) + (10.0 * 3e-5)
        #expect(terra == expectedValueLine306)
        let expectedValueLine307 = (80.0 * 2e-6) + (20.0 * 2e-7) + (10.0 * 1.2e-5)
        #expect(luna == expectedValueLine307)
    }

    @Test
    func codex_priority_cost_uses_explicit_cache_write_rates() {
        let sol = CostUsagePricing.codexPriorityCostUSD(
            model: "gpt-5.6-sol",
            inputTokens: 100,
            cachedInputTokens: 10,
            cacheWriteInputTokens: 20,
            outputTokens: 5)
        let terra = CostUsagePricing.codexPriorityCostUSD(
            model: "gpt-5.6-terra",
            inputTokens: 100,
            cachedInputTokens: 10,
            cacheWriteInputTokens: 20,
            outputTokens: 5)
        let luna = CostUsagePricing.codexPriorityCostUSD(
            model: "gpt-5.6-luna",
            inputTokens: 100,
            cachedInputTokens: 10,
            cacheWriteInputTokens: 20,
            outputTokens: 5)
        let modelWithoutCacheWriteSupport = CostUsagePricing.codexPriorityCostUSD(
            model: "gpt-5.5",
            inputTokens: 100,
            cachedInputTokens: 10,
            cacheWriteInputTokens: 20,
            outputTokens: 5)

        let expectedValueLine337 = (70.0 * 1e-5) + (10.0 * 1e-6) + (20.0 * 1.25e-5) + (5.0 * 6e-5)
        #expect(sol == expectedValueLine337)
        let expectedValueLine338 = (70.0 * 5e-6) + (10.0 * 5e-7) + (20.0 * 6.25e-6) + (5.0 * 3e-5)
        #expect(terra == expectedValueLine338)
        let expectedValueLine339 = (70.0 * 2e-6) + (10.0 * 2e-7) + (20.0 * 2.5e-6) + (5.0 * 1.2e-5)
        #expect(luna == expectedValueLine339)
        // A model without an explicit Priority cache-write price keeps the legacy input-rate fold.
        let expectedLegacyFold = (90.0 * 1.25e-5) + (10.0 * 1.25e-6) + (5.0 * 7.5e-5)
        #expect(modelWithoutCacheWriteSupport == expectedLegacyFold)
    }

    @Test
    func codex_cost_applies_gpt54_and_gpt55_long_context_rates_to_full_session() throws {
        let root = try Self.cacheRoot()
        let gpt54 = CostUsagePricing.codexCostUSD(
            model: "gpt-5.4",
            inputTokens: 272_001,
            cachedInputTokens: 0,
            outputTokens: 10,
            modelsDevCacheRoot: root)
        let gpt55 = CostUsagePricing.codexCostUSD(
            model: "gpt-5.5",
            inputTokens: 272_001,
            cachedInputTokens: 0,
            outputTokens: 10,
            modelsDevCacheRoot: root)

        #expect(gpt54 == (272_001.0 * 5e-6) + (10.0 * 2.25e-5))
        #expect(gpt55 == (272_001.0 * 1e-5) + (10.0 * 4.5e-5))
    }

    @Test
    func codex_cost_keeps_normal_rates_at_long_context_input_boundary() throws {
        let root = try Self.cacheRoot()
        let gpt55 = CostUsagePricing.codexCostUSD(
            model: "gpt-5.5",
            inputTokens: 272_000,
            cachedInputTokens: 0,
            outputTokens: 128_000,
            modelsDevCacheRoot: root)

        #expect(gpt55 == (272_000.0 * 5e-6) + (128_000.0 * 3e-5))
    }

    @Test
    func codex_cost_applies_long_context_rates_to_all_cached_and_non_cached_input() throws {
        let root = try Self.cacheRoot()
        let gpt55 = CostUsagePricing.codexCostUSD(
            model: "gpt-5.5",
            inputTokens: 300_000,
            cachedInputTokens: 200_000,
            outputTokens: 10,
            modelsDevCacheRoot: root)

        // 200K cached reads are a subset of the 300K input, leaving 100K non-cached input.
        let cached = 200_000.0 * 1e-6
        let nonCached = 100_000.0 * 1e-5
        let output = 10.0 * 4.5e-5

        #expect(gpt55 == cached + nonCached + output)
    }

    @Test
    func codex_cost_clamps_cache_reads_to_input_tokens() throws {
        // `cached_input_tokens` can never exceed `input_tokens` in real Codex data; if it does,
        // clamp cached to input so the surplus is not invented and input is never double-billed.
        let root = try Self.cacheRoot()
        let gpt55 = CostUsagePricing.codexCostUSD(
            model: "gpt-5.5",
            inputTokens: 20,
            cachedInputTokens: 500,
            outputTokens: 5,
            modelsDevCacheRoot: root)

        let expected = (20.0 * 5e-7) + (5.0 * 3e-5)

        #expect(gpt55 == expected)
    }

    @Test
    func codex_cost_does_not_double_bill_cached_input_tokens() throws {
        // Regression for the cached double-count: input_tokens includes cached reads, so a turn
        // with 1000 input / 900 cached must bill 100 tokens at the input rate and 900 at the
        // cache rate — not the full 1000 at the input rate plus 900 again at the cache rate.
        let root = try Self.cacheRoot()
        let cost = CostUsagePricing.codexCostUSD(
            model: "gpt-5-codex",
            inputTokens: 1000,
            cachedInputTokens: 900,
            outputTokens: 10,
            modelsDevCacheRoot: root)

        let expected = (100.0 * 1.25e-6) + (900.0 * 1.25e-7) + (10.0 * 1e-5)
        #expect(cost == expected)
    }

    @Test
    func codex_priority_cost_applies_model_specific_fast_rates() {
        let gpt54 = CostUsagePricing.codexPriorityCostUSD(
            model: "gpt-5.4",
            inputTokens: 100,
            cachedInputTokens: 20,
            outputTokens: 10)
        let gpt55 = CostUsagePricing.codexPriorityCostUSD(
            model: "gpt-5.5",
            inputTokens: 100,
            cachedInputTokens: 20,
            outputTokens: 10)
        let gpt54Mini = CostUsagePricing.codexPriorityCostUSD(
            model: "gpt-5.4-mini",
            inputTokens: 100,
            cachedInputTokens: 20,
            outputTokens: 10)

        let expectedValueLine449 = (80.0 * 5e-6) + (20.0 * 5e-7) + (10.0 * 3e-5)
        #expect(gpt54 == expectedValueLine449)
        let expectedValueLine450 = (80.0 * 1.25e-5) + (20.0 * 1.25e-6) + (10.0 * 7.5e-5)
        #expect(gpt55 == expectedValueLine450)
        let expectedValueLine451 = (80.0 * 1.5e-6) + (20.0 * 1.5e-7) + (10.0 * 9e-6)
        #expect(gpt54Mini == expectedValueLine451)
    }

    @Test
    func codex_priority_cost_is_unavailable_for_long_context_requests() {
        let gpt55 = CostUsagePricing.codexPriorityCostUSD(
            model: "gpt-5.5",
            inputTokens: 272_001,
            cachedInputTokens: 0,
            outputTokens: 10)
        let gpt56Sol = CostUsagePricing.codexPriorityCostUSD(
            model: "gpt-5.6-sol",
            inputTokens: 272_001,
            cachedInputTokens: 0,
            outputTokens: 10)
        let gpt56Terra = CostUsagePricing.codexPriorityCostUSD(
            model: "gpt-5.6-terra",
            inputTokens: 272_001,
            cachedInputTokens: 0,
            outputTokens: 10)
        let gpt56Luna = CostUsagePricing.codexPriorityCostUSD(
            model: "gpt-5.6-luna",
            inputTokens: 272_001,
            cachedInputTokens: 0,
            outputTokens: 10)
        let gpt54Mini = CostUsagePricing.codexPriorityCostUSD(
            model: "gpt-5.4-mini",
            inputTokens: 272_001,
            cachedInputTokens: 0,
            outputTokens: 10)

        #expect(gpt55 == nil)
        #expect(gpt56Sol == nil)
        #expect(gpt56Terra == nil)
        #expect(gpt56Luna == nil)
        #expect(gpt54Mini == nil)
    }

    @Test
    func codex_priority_cost_counts_only_input_tokens_toward_the_limit() {
        let eligible = CostUsagePricing.codexPriorityCostUSD(
            model: "gpt-5.5",
            inputTokens: 200_000,
            cachedInputTokens: 100_000,
            outputTokens: 10)
        let boundary = CostUsagePricing.codexPriorityCostUSD(
            model: "gpt-5.5",
            inputTokens: 272_000,
            cachedInputTokens: 0,
            outputTokens: 10)
        let overLimit = CostUsagePricing.codexPriorityCostUSD(
            model: "gpt-5.5",
            inputTokens: 272_001,
            cachedInputTokens: 0,
            outputTokens: 10)

        let expectedValueLine507 = (100_000.0 * 1.25e-5) + (100_000.0 * 1.25e-6) + (10.0 * 7.5e-5)
        #expect(eligible == expectedValueLine507)
        #expect(boundary != nil)
        #expect(overLimit == nil)
    }

    @Test
    func codex_priority_cost_remains_available_at_priority_input_boundary() {
        let gpt55 = CostUsagePricing.codexPriorityCostUSD(
            model: "gpt-5.5",
            inputTokens: 272_000,
            cachedInputTokens: 0,
            outputTokens: 10)

        #expect(gpt55 == (272_000.0 * 1.25e-5) + (10.0 * 7.5e-5))
    }

    @Test
    func codex_models_dev_pricing_uses_codex_long_context_threshold() throws {
        let root = try Self.seedModelsDevCache("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "gpt-5.5": {
                "id": "gpt-5.5",
                "cost": {
                  "input": 5,
                  "output": 30,
                  "cache_read": 0.5,
                  "context_over_200k": {
                    "input": 10,
                    "output": 45,
                    "cache_read": 1
                  }
                }
              }
            }
          }
        }
        """)

        let atBoundary = CostUsagePricing.codexCostUSD(
            model: "gpt-5.5",
            inputTokens: 272_000,
            cachedInputTokens: 0,
            outputTokens: 10,
            modelsDevCacheRoot: root)
        let aboveBoundary = CostUsagePricing.codexCostUSD(
            model: "gpt-5.5",
            inputTokens: 272_001,
            cachedInputTokens: 0,
            outputTokens: 10,
            modelsDevCacheRoot: root)

        #expect(atBoundary == (272_000.0 * 5e-6) + (10.0 * 3e-5))
        #expect(aboveBoundary == (272_001.0 * 1e-5) + (10.0 * 4.5e-5))
    }

    @Test
    func codex_models_dev_cached_fallback_uses_long_context_input_rate_when_cache_read_is_absent() throws {
        let root = try Self.seedModelsDevCache("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "gpt-5.5": {
                "id": "gpt-5.5",
                "cost": {
                  "input": 5,
                  "output": 30,
                  "context_over_200k": {
                    "input": 10,
                    "output": 45
                  }
                }
              }
            }
          }
        }
        """)

        let cost = CostUsagePricing.codexCostUSD(
            model: "gpt-5.5",
            inputTokens: 300_000,
            cachedInputTokens: 200_000,
            outputTokens: 10,
            modelsDevCacheRoot: root)

        // The catalog has a long-context block but omits cache_read, so preserve its omission
        // semantics: cached tokens fall back to the long-context input rate rather than mixing in
        // one field from the bundled table.
        let expected = (100_000.0 * 10e-6) + (200_000.0 * 10e-6) + (10.0 * 45e-6)
        #expect(cost == expected)
    }
}

extension CostUsagePricingTests {
    @Test
    func codex_models_dev_uses_bundled_short_cache_rates_only_when_catalog_omits_them() throws {
        let missingRoot = try Self.seedModelsDevCache("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "gpt-5.6-sol": {
                "id": "gpt-5.6-sol",
                "cost": { "input": 5, "output": 30 }
              }
            }
          }
        }
        """)
        let explicitZeroRoot = try Self.seedModelsDevCache("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "gpt-5.6-sol": {
                "id": "gpt-5.6-sol",
                "cost": { "input": 5, "output": 30, "cache_read": 0, "cache_write": 0 }
              }
            }
          }
        }
        """)

        let missing = CostUsagePricing.codexCostUSD(
            model: "gpt-5.6-sol",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 0,
            cacheWriteInputTokens: 20,
            modelsDevCacheRoot: missingRoot)
        let explicitZero = CostUsagePricing.codexCostUSD(
            model: "gpt-5.6-sol",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 0,
            cacheWriteInputTokens: 20,
            modelsDevCacheRoot: explicitZeroRoot)

        let expectedValueLine648 = (70.0 * 5e-6) + (10.0 * 5e-7) + (20.0 * 6.25e-6)
        #expect(missing == expectedValueLine648)
        #expect(explicitZero == 70.0 * 5e-6)
    }

    @Test
    func codex_models_dev_falls_back_bundled_long_context_rates_when_catalog_omits_them() throws {
        // Catalog has short-context rates only; bundled table supplies the 272K threshold + rates.
        let root = try Self.seedModelsDevCache("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "gpt-5.6-sol": {
                "id": "gpt-5.6-sol",
                "cost": {
                  "input": 5,
                  "output": 30,
                  "cache_read": 0.5
                }
              }
            }
          }
        }
        """)

        let cost = CostUsagePricing.codexCostUSD(
            model: "gpt-5.6-sol",
            inputTokens: 272_001,
            cachedInputTokens: 0,
            outputTokens: 10,
            modelsDevCacheRoot: root)

        // Without bundled above-threshold fallback this would bill short rates ($5/$30) despite
        // entering long-context mode via the bundled threshold.
        #expect(cost == (272_001.0 * 1e-5) + (10.0 * 4.5e-5))
    }

    @Test
    func codex_models_dev_overrides_every_gpt56_long_context_token_bucket() throws {
        let root = try Self.seedModelsDevCache("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "gpt-5.6-sol": {
                "id": "gpt-5.6-sol",
                "cost": {
                  "input": 1,
                  "output": 2,
                  "cache_read": 0.1,
                  "cache_write": 1.25,
                  "context_over_200k": {
                    "input": 11,
                    "output": 22,
                    "cache_read": 1.1,
                    "cache_write": 13.75
                  }
                }
              }
            }
          }
        }
        """)

        let cost = CostUsagePricing.codexCostUSD(
            model: "gpt-5.6-sol",
            inputTokens: 272_001,
            cachedInputTokens: 100_000,
            outputTokens: 10,
            cacheWriteInputTokens: 50000,
            modelsDevCacheRoot: root)

        let expected = (122_001.0 * 11e-6)
            + (100_000.0 * 1.1e-6)
            + (50000.0 * 13.75e-6)
            + (10.0 * 22e-6)
        #expect(cost == expected)
    }

    @Test
    func codex_cost_supports_gpt55_pro_bundled_fallback() throws {
        let root = try Self.cacheRoot()
        let cost = CostUsagePricing.codexCostUSD(
            model: "openai/gpt-5.5-pro-2026-04-23",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5,
            modelsDevCacheRoot: root)

        // gpt-5.5-pro has no cache-read rate, so cached falls back to the input rate; with 90
        // non-cached + 10 cached priced at the same rate this is 100 tokens at 3e-5.
        let expected = (100.0 * 3e-5) + (5.0 * 1.8e-4)
        #expect(cost == expected)
    }

    @Test
    func codex_cost_returns_zero_for_research_preview_fallback_model() throws {
        let root = try Self.cacheRoot()
        let cost = CostUsagePricing.codexCostUSD(
            model: "gpt-5.3-codex-spark",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5,
            modelsDevCacheRoot: root)
        #expect(cost == 0)
        #expect(CostUsagePricing.codexDisplayLabel(model: "gpt-5.3-codex-spark") == "Research Preview")
        #expect(CostUsagePricing.codexDisplayLabel(model: "gpt-5.2-codex") == nil)
    }

    @Test
    func codex_cost_prefers_models_dev_cache_over_bundled_fallback() throws {
        let root = try Self.seedModelsDevCache("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "gpt-5.5": {
                "id": "gpt-5.5",
                "cost": { "input": 10, "output": 20, "cache_read": 1 }
              }
            }
          }
        }
        """)

        let cost = CostUsagePricing.codexCostUSD(
            model: "openai/gpt-5.5",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5,
            modelsDevCacheRoot: root)

        let expected = (90.0 * 10e-6) + (10.0 * 1e-6) + (5.0 * 20e-6)
        #expect(cost == expected)
    }

    @Test
    func codex_cost_lets_models_dev_override_research_preview_fallback() throws {
        let root = try Self.seedModelsDevCache("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "gpt-5.3-codex-spark": {
                "id": "gpt-5.3-codex-spark",
                "cost": { "input": 2, "output": 8, "cache_read": 0.2 }
              }
            }
          }
        }
        """)

        let cost = CostUsagePricing.codexCostUSD(
            model: "gpt-5.3-codex-spark",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5,
            modelsDevCacheRoot: root)

        let expected = (90.0 * 2e-6) + (10.0 * 0.2e-6) + (5.0 * 8e-6)
        #expect(cost == expected)
        #expect(CostUsagePricing.codexDisplayLabel(model: "gpt-5.3-codex-spark") == "Research Preview")
    }

    @Test
    func codex_cost_falls_back_to_bundled_pricing_when_models_dev_misses_provider_model() throws {
        let root = try Self.seedModelsDevCache("""
        {
          "anthropic": {
            "id": "anthropic",
            "models": {
              "gpt-5.5": {
                "id": "gpt-5.5",
                "cost": { "input": 10, "output": 20, "cache_read": 1 }
              }
            }
          }
        }
        """)

        let cost = CostUsagePricing.codexCostUSD(
            model: "openai/gpt-5.5",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5,
            modelsDevCacheRoot: root)

        let expected = (90.0 * 5e-6) + (10.0 * 5e-7) + (5.0 * 3e-5)
        #expect(cost == expected)
    }

    @Test
    func normalizes_claude_opus41_dated_variants() {
        #expect(CostUsagePricing.normalizeClaudeModel("claude-opus-4-1-20250805") == "claude-opus-4-1")
    }

    @Test
    func claude_cost_supports_opus41_dated_variant() {
        let cost = CostUsagePricing.claudeCostUSD(
            model: "claude-opus-4-1-20250805",
            inputTokens: 10,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 5)
        #expect(cost != nil)
    }

    @Test
    func claude_cost_supports_opus46_dated_variant() {
        let cost = CostUsagePricing.claudeCostUSD(
            model: "claude-opus-4-6-20260205",
            inputTokens: 10,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 5)
        #expect(cost != nil)
    }

    @Test
    func claude_cost_supports_opus47() {
        let cost = CostUsagePricing.claudeCostUSD(
            model: "claude-opus-4-7",
            inputTokens: 10,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 5)
        let expected = (10.0 * 5e-6) + (5.0 * 2.5e-5)
        #expect(cost == expected)
    }

    @Test
    func claude_cost_supports_opus48() throws {
        // Point at a fresh, empty cache root so the models.dev lookup misses and this
        // exercises the built-in fallback table specifically — not a local cache hit.
        let emptyCacheRoot = try Self.cacheRoot()
        let cost = CostUsagePricing.claudeCostUSD(
            model: "claude-opus-4-8",
            inputTokens: 10,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 5,
            modelsDevCacheRoot: emptyCacheRoot)
        let expected = (10.0 * 5e-6) + (5.0 * 2.5e-5)
        #expect(cost == expected)
    }

    @Test
    func claude_cost_supports_fable5_bundled_fallback() throws {
        let emptyCacheRoot = try Self.cacheRoot()
        let cost = CostUsagePricing.claudeCostUSD(
            model: "claude-fable-5",
            inputTokens: 100,
            cacheReadInputTokens: 20,
            cacheCreationInputTokens: 10,
            outputTokens: 5,
            modelsDevCacheRoot: emptyCacheRoot)
        let expected = (100.0 * 1e-5) + (20.0 * 1e-6) + (10.0 * 1.25e-5) + (5.0 * 5e-5)
        #expect(cost == expected)
    }

    @Test
    func claude_cost_preserves_historical_sonnet46_long_context_pricing() throws {
        let emptyCacheRoot = try Self.cacheRoot()
        let historical = CostUsagePricing.claudeCostUSD(
            model: "claude-sonnet-4-6",
            inputTokens: 240_000,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 0,
            pricingDate: Date(timeIntervalSince1970: 1_773_359_999),
            modelsDevCacheRoot: emptyCacheRoot)
        let current = CostUsagePricing.claudeCostUSD(
            model: "claude-sonnet-4-6",
            inputTokens: 240_000,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 0,
            pricingDate: Date(timeIntervalSince1970: 1_773_360_000),
            modelsDevCacheRoot: emptyCacheRoot)

        #expect(historical == 1.44)
        #expect(current == 0.72)
    }

    @Test
    func claude_cost_ignores_stale_sonnet46_threshold_catalog_after_cutover() throws {
        let cacheRoot = try Self.seedModelsDevCache("""
        {
          "anthropic": {
            "id": "anthropic",
            "models": {
              "claude-sonnet-4-6": {
                "id": "claude-sonnet-4-6",
                "cost": {
                  "input": 3,
                  "output": 15,
                  "cache_read": 0.3,
                  "cache_write": 3.75,
                  "context_over_200k": {
                    "input": 6,
                    "output": 22.5,
                    "cache_read": 0.6,
                    "cache_write": 7.5
                  }
                }
              }
            }
          }
        }
        """)
        let cost = CostUsagePricing.claudeCostUSD(
            model: "claude-sonnet-4-6",
            inputTokens: 240_000,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 0,
            pricingDate: Date(timeIntervalSince1970: 1_773_360_000),
            modelsDevCacheRoot: cacheRoot)

        #expect(cost == 0.72)
    }

    @Test
    func claude_cost_prices_one_hour_cache_writes_separately() throws {
        let emptyCacheRoot = try Self.cacheRoot()
        let cost = CostUsagePricing.claudeCostUSD(
            model: "claude-fable-5",
            inputTokens: 100,
            cacheReadInputTokens: 20,
            cacheCreationInputTokens: 30,
            cacheCreationInputTokens1h: 20,
            outputTokens: 5,
            modelsDevCacheRoot: emptyCacheRoot)
        let expected = (100.0 * 1e-5)
            + (20.0 * 1e-6)
            + (10.0 * 1.25e-5)
            + (20.0 * 2e-5)
            + (5.0 * 5e-5)
        #expect(cost == expected)
    }

    @Test
    func claude_cost_applies_long_context_rates_across_cache_write_durations() throws {
        let cacheRoot = try Self.seedModelsDevCache("""
        {
          "anthropic": {
            "id": "anthropic",
            "models": {
              "claude-threshold-model": {
                "id": "claude-threshold-model",
                "cost": {
                  "input": 3,
                  "output": 15,
                  "cache_read": 0.3,
                  "cache_write": 3.75,
                  "context_over_200k": {
                    "input": 6,
                    "output": 22.5,
                    "cache_read": 0.6,
                    "cache_write": 7.5
                  }
                }
              }
            }
          }
        }
        """)
        let cost = CostUsagePricing.claudeCostUSD(
            model: "claude-threshold-model",
            inputTokens: 0,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 240_000,
            cacheCreationInputTokens1h: 120_000,
            outputTokens: 0,
            modelsDevCacheRoot: cacheRoot)
        let expected = (120_000.0 * 12e-6)
            + (120_000.0 * 7.5e-6)
        #expect(cost == expected)
    }

    @Test
    func claude_sonnet46_uses_standard_pricing_across_full_context() throws {
        let emptyCacheRoot = try Self.cacheRoot()
        let cost = CostUsagePricing.claudeCostUSD(
            model: "claude-sonnet-4-6",
            inputTokens: 0,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 240_000,
            outputTokens: 0,
            modelsDevCacheRoot: emptyCacheRoot)
        #expect(cost == 240_000.0 * 3.75e-6)
    }

    @Test
    func claude_cost_returns_nil_for_unknown_models() {
        let cost = CostUsagePricing.claudeCostUSD(
            model: "glm-4.6",
            inputTokens: 100,
            cacheReadInputTokens: 500,
            cacheCreationInputTokens: 0,
            outputTokens: 40)
        #expect(cost == nil)
    }

    @Test
    func claude_cost_prefers_models_dev_cache_with_threshold_pricing() throws {
        let root = try Self.seedModelsDevCache("""
        {
          "anthropic": {
            "id": "anthropic",
            "models": {
              "claude-sonnet-4-6": {
                "id": "claude-sonnet-4-6",
                "cost": {
                  "input": 3,
                  "output": 15,
                  "cache_read": 0.3,
                  "cache_write": 3.75,
                  "context_over_200k": {
                    "input": 6,
                    "output": 22.5,
                    "cache_read": 0.6,
                    "cache_write": 7.5
                  }
                }
              }
            }
          }
        }
        """)

        let cost = CostUsagePricing.claudeCostUSD(
            model: "claude-sonnet-4-6",
            inputTokens: 200_010,
            cacheReadInputTokens: 5,
            cacheCreationInputTokens: 5,
            outputTokens: 5,
            modelsDevCacheRoot: root)

        let expected = (200_010.0 * 6e-6)
            + (5.0 * 0.6e-6)
            + (5.0 * 7.5e-6)
            + (5.0 * 22.5e-6)
        #expect(cost == expected)
    }

    private static func seedModelsDevCache(_ json: String) throws -> URL {
        let root = try Self.cacheRoot()
        let catalog = try JSONDecoder().decode(ModelsDevCatalog.self, from: Data(json.utf8))
        ModelsDevCache.save(catalog: catalog, fetchedAt: Date(), cacheRoot: root)
        return root
    }

    private static func modelsDevArtifact(_ json: String) throws -> ModelsDevCacheArtifact {
        let catalog = try JSONDecoder().decode(ModelsDevCatalog.self, from: Data(json.utf8))
        return ModelsDevCacheArtifact(
            version: ModelsDevCache.artifactVersion,
            fetchedAt: Date(timeIntervalSince1970: 0),
            catalog: catalog)
    }

    private static func cacheRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-pricing-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
