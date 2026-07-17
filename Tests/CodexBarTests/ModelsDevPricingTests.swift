import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

struct ModelsDevPricingTests {
    @Test
    func parses_models_dev_subset() throws {
        let catalog = try Self.fixtureCatalog()

        #expect(catalog.providers["openai"]?.name == "OpenAI")
        #expect(catalog.providers["anthropic"]?.models["claude-sonnet-4-6"]?.cost?.cacheWrite == 3.75)
        #expect(catalog.providers["anthropic"]?.models["claude-sonnet-4-6"]?.limit?.context == 1_000_000)
    }

    @Test
    func looks_up_pricing_by_provider_and_model() throws {
        let catalog = try Self.fixtureCatalog()

        let openAI = try #require(catalog.pricing(providerID: "openai", modelID: "shared-model"))
        let anthropic = try #require(catalog.pricing(providerID: "anthropic", modelID: "shared-model"))

        #expect(openAI.pricing.inputCostPerToken == 1 / 1_000_000.0)
        #expect(openAI.pricing.outputCostPerToken == 2 / 1_000_000.0)
        #expect(anthropic.pricing.inputCostPerToken == 3 / 1_000_000.0)
        #expect(anthropic.pricing.outputCostPerToken == 4 / 1_000_000.0)
    }

    @Test
    func does_not_fall_back_across_providers() throws {
        let catalog = try Self.fixtureCatalog()

        #expect(catalog.pricing(providerID: "openai", modelID: "claude-sonnet-4-6") == nil)
        #expect(catalog.pricing(providerID: "anthropic", modelID: "gpt-4o-mini") == nil)
    }

    @Test
    func supports_provider_scoped_model_normalization() throws {
        let catalog = try Self.fixtureCatalog()

        let anthropic = try #require(catalog.pricing(
            providerID: "anthropic",
            modelID: "us.anthropic.claude-sonnet-4-6"))
        let vertex = try #require(catalog.pricing(
            providerID: "google-vertex-anthropic",
            modelID: "claude-sonnet-4-6"))

        #expect(anthropic.normalizedModelID == "claude-sonnet-4-6")
        #expect(vertex.normalizedModelID == "claude-sonnet-4-6")
        #expect(vertex.pricing.inputCostPerToken == 3.1 / 1_000_000.0)
    }

    @Test
    func converts_models_dev_per_million_token_prices_to_per_token_prices() throws {
        let pricing = try #require(try Self.fixtureCatalog().pricing(
            providerID: "anthropic",
            modelID: "claude-sonnet-4-6")?
            .pricing)

        #expect(pricing.inputCostPerToken == 3 / 1_000_000.0)
        #expect(pricing.outputCostPerToken == 15 / 1_000_000.0)
        #expect(pricing.cacheReadInputCostPerToken == 0.3 / 1_000_000.0)
        #expect(pricing.cacheCreationInputCostPerToken == 3.75 / 1_000_000.0)
        #expect(pricing.thresholdTokens == 200_000)
        #expect(pricing.inputCostPerTokenAboveThreshold == 6 / 1_000_000.0)
        #expect(pricing.outputCostPerTokenAboveThreshold == 22.5 / 1_000_000.0)
        #expect(pricing.cacheReadInputCostPerTokenAboveThreshold == 0.6 / 1_000_000.0)
        #expect(pricing.cacheCreationInputCostPerTokenAboveThreshold == 7.5 / 1_000_000.0)
    }

    @Test
    func stale_cache_is_still_readable() throws {
        let root = try Self.cacheRoot()
        let old = Date(timeIntervalSince1970: 1)
        try ModelsDevCache.save(catalog: Self.fixtureCatalog(), fetchedAt: old, cacheRoot: root)

        let load = ModelsDevCache.load(
            now: Date(timeIntervalSince1970: 1 + ModelsDevCache.ttlSeconds + 1),
            cacheRoot: root)

        #expect(load.artifact != nil)
        #expect(load.isStale)
        #expect(load.error == nil)
    }

    @Test
    func pipeline_lookup_reads_cached_pricing() throws {
        let root = try Self.cacheRoot()
        try ModelsDevCache.save(catalog: Self.fixtureCatalog(), fetchedAt: Date(), cacheRoot: root)

        let lookup = try #require(ModelsDevPricingPipeline.lookup(
            providerID: "openai",
            modelID: "gpt-4o-mini",
            cacheRoot: root))

        #expect(lookup.pricing.inputCostPerToken == 0.15 / 1_000_000.0)
    }

    @Test
    func network_failure_preserves_last_valid_cache() async throws {
        let root = try Self.cacheRoot()
        let old = Date(timeIntervalSince1970: 1)
        try ModelsDevCache.save(catalog: Self.fixtureCatalog(), fetchedAt: old, cacheRoot: root)

        await ModelsDevPricingPipeline.refreshIfNeeded(
            now: Date(timeIntervalSince1970: 1 + ModelsDevCache.ttlSeconds + 1),
            cacheRoot: root,
            client: ModelsDevClient(transport: MockTransport(result: .failure(MockError.failed))))

        let lookup = try #require(ModelsDevPricingPipeline.lookup(
            providerID: "openai",
            modelID: "gpt-4o-mini",
            cacheRoot: root))

        #expect(lookup.pricing.inputCostPerToken == 0.15 / 1_000_000.0)
    }

    @Test
    func refresh_preserves_cache_when_fetched_catalog_drops_cached_provider() async throws {
        let root = try Self.cacheRoot()
        let old = Date(timeIntervalSince1970: 1)
        try ModelsDevCache.save(catalog: Self.fixtureCatalog(), fetchedAt: old, cacheRoot: root)

        let partialCatalog = Data("""
        {
          "openai": { "id": 7, "models": [] },
          "anthropic": {
            "id": "anthropic",
            "models": {
              "shared-model": {
                "id": "shared-model",
                "cost": { "input": 99, "output": 99 }
              }
            }
          }
        }
        """.utf8)
        await ModelsDevPricingPipeline.refreshIfNeeded(
            now: Date(timeIntervalSince1970: 1 + ModelsDevCache.ttlSeconds + 1),
            cacheRoot: root,
            client: ModelsDevClient(transport: MockTransport(
                result: .success((partialCatalog, Self.response(status: 200))))))

        let lookup = try #require(ModelsDevPricingPipeline.lookup(
            providerID: "openai",
            modelID: "gpt-4o-mini",
            cacheRoot: root))

        #expect(lookup.pricing.inputCostPerToken == 0.15 / 1_000_000.0)
    }
}

extension ModelsDevPricingTests {
    @Test
    func unknown_model_refresh_makes_newly_published_pricing_available() async throws {
        let root = try Self.cacheRoot()
        let now = Date(timeIntervalSince1970: 10000)
        try ModelsDevCache.save(
            catalog: Self.fixtureCatalog(),
            fetchedAt: now.addingTimeInterval(-901),
            cacheRoot: root)
        let refreshed = Data("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "gpt-new": { "id": "gpt-new", "cost": { "input": 2, "output": 8 } }
            }
          },
          "anthropic": {
            "id": "anthropic",
            "models": {
              "claude-new": { "id": "claude-new", "cost": { "input": 3, "output": 15 } }
            }
          }
        }
        """.utf8)
        let transport = TrackingTransport(result: .success((refreshed, Self.response(status: 200))))
        let client = ModelsDevClient(transport: transport)

        let outcome = await ModelsDevPricingPipeline.refreshForUnknownModelsIfNeeded(
            providerID: "openai",
            modelIDs: ["gpt-new"],
            now: now,
            cacheRoot: root,
            client: client)
        #expect(outcome == .pricingAvailable)
        #expect(transport.calls == 1)
        #expect(ModelsDevPricingPipeline.lookup(
            providerID: "openai",
            modelID: "gpt-new",
            cacheRoot: root) != nil)
    }

    @Test
    func unknown_model_refresh_is_bounded_per_provider_cache() async throws {
        let root = try Self.cacheRoot()
        let now = Date(timeIntervalSince1970: 20000)
        try ModelsDevCache.save(
            catalog: Self.fixtureCatalog(),
            fetchedAt: now.addingTimeInterval(-901),
            cacheRoot: root)
        let transport = try TrackingTransport(result: .success((
            JSONEncoder().encode(Self.fixtureCatalog()),
            Self.response(status: 200))))
        let client = ModelsDevClient(transport: transport)

        let first = await ModelsDevPricingPipeline.refreshForUnknownModelsIfNeeded(
            providerID: "openai",
            modelIDs: ["still-unknown"],
            now: now,
            cacheRoot: root,
            client: client)
        let second = await ModelsDevPricingPipeline.refreshForUnknownModelsIfNeeded(
            providerID: "openai",
            modelIDs: ["another-unknown-model"],
            now: now.addingTimeInterval(60),
            cacheRoot: root,
            client: client)

        #expect(first == .unavailable)
        #expect(second == .unavailable)
        #expect(transport.calls == 1)
    }

    @Test
    func known_requested_model_does_not_mask_an_unresolved_unknown_model() async throws {
        let root = try Self.cacheRoot()
        let now = Date(timeIntervalSince1970: 25000)
        let catalog = try Self.catalog("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "already-priced": { "id": "already-priced", "cost": { "input": 1, "output": 2 } }
            }
          },
          "anthropic": {
            "id": "anthropic",
            "models": {
              "catalog-anchor": { "id": "catalog-anchor", "cost": { "input": 3, "output": 4 } }
            }
          }
        }
        """)
        ModelsDevCache.save(
            catalog: catalog,
            fetchedAt: now.addingTimeInterval(-901),
            cacheRoot: root)
        let transport = try TrackingTransport(result: .success((
            JSONEncoder().encode(catalog),
            Self.response(status: 200))))

        let outcome = await ModelsDevPricingPipeline.refreshForUnknownModelsIfNeeded(
            providerID: "openai",
            modelIDs: ["already-priced", "still-unknown"],
            now: now,
            cacheRoot: root,
            client: ModelsDevClient(transport: transport))

        #expect(outcome == .unavailable)
        #expect(transport.calls == 1)
    }

    @Test
    func pricing_added_by_a_completed_background_refresh_requests_a_rescan() async throws {
        let root = try Self.cacheRoot()
        let now = Date(timeIntervalSince1970: 30000)
        let refreshed = Data("""
        {
          "openai": {
            "id": "openai",
            "models": { "gpt-new": { "id": "gpt-new", "cost": { "input": 2, "output": 8 } } }
          },
          "anthropic": {
            "id": "anthropic",
            "models": { "claude-new": { "id": "claude-new", "cost": { "input": 3, "output": 15 } } }
          }
        }
        """.utf8)
        let refreshedCatalog = try JSONDecoder().decode(ModelsDevCatalog.self, from: refreshed)
        ModelsDevCache.save(catalog: refreshedCatalog, fetchedAt: now, cacheRoot: root)
        let transport = TrackingTransport(result: .failure(MockError.failed))

        let outcome = await ModelsDevPricingPipeline.refreshForUnknownModelsIfNeeded(
            providerID: "openai",
            modelIDs: ["gpt-new"],
            now: now,
            cacheRoot: root,
            client: ModelsDevClient(transport: transport))

        #expect(outcome == .pricingAvailable)
        #expect(transport.calls == 0)
    }

    @Test
    func ttl_and_unknown_model_refreshes_share_one_download() async throws {
        let root = try Self.cacheRoot()
        let now = Date(timeIntervalSince1970: 40000)
        try ModelsDevCache.save(
            catalog: Self.fixtureCatalog(),
            fetchedAt: now.addingTimeInterval(-ModelsDevCache.ttlSeconds - 1),
            cacheRoot: root)
        let transport = try TrackingTransport(
            result: .success((JSONEncoder().encode(Self.fixtureCatalog()), Self.response(status: 200))),
            delayNanoseconds: 100_000_000)
        let client = ModelsDevClient(transport: transport)

        async let ttl: Void = ModelsDevPricingPipeline.refreshIfNeeded(
            now: now,
            cacheRoot: root,
            client: client)
        async let unknown = ModelsDevPricingPipeline.refreshForUnknownModelsIfNeeded(
            providerID: "openai",
            modelIDs: ["still-unknown"],
            now: now,
            cacheRoot: root,
            client: client)
        _ = await (ttl, unknown)

        #expect(transport.calls == 1)
    }

    @Test
    func completed_ttl_refresh_bounds_a_following_unknown_model_refresh() async throws {
        let root = try Self.cacheRoot()
        let now = Date(timeIntervalSince1970: 45000)
        try ModelsDevCache.save(
            catalog: Self.fixtureCatalog(),
            fetchedAt: now.addingTimeInterval(-ModelsDevCache.ttlSeconds - 1),
            cacheRoot: root)
        let transport = try TrackingTransport(result: .success((
            JSONEncoder().encode(Self.fixtureCatalog()),
            Self.response(status: 200))))
        let client = ModelsDevClient(transport: transport)

        await ModelsDevPricingPipeline.refreshIfNeeded(
            now: now,
            cacheRoot: root,
            client: client)
        let outcome = await ModelsDevPricingPipeline.refreshForUnknownModelsIfNeeded(
            providerID: "openai",
            modelIDs: ["still-unknown"],
            now: now,
            cacheRoot: root,
            client: client)

        #expect(outcome == .unavailable)
        #expect(transport.calls == 1)
    }

    @Test
    func failed_ttl_refresh_bounds_a_following_unknown_model_refresh_within_cooldown() async throws {
        let root = try Self.cacheRoot()
        let now = Date(timeIntervalSince1970: 46000)
        try ModelsDevCache.save(
            catalog: Self.fixtureCatalog(),
            fetchedAt: now.addingTimeInterval(-ModelsDevCache.ttlSeconds - 1),
            cacheRoot: root)
        let transport = TrackingTransport(result: .failure(MockError.failed))
        let client = ModelsDevClient(transport: transport)

        await ModelsDevPricingPipeline.refreshIfNeeded(
            now: now,
            cacheRoot: root,
            client: client)
        let outcome = await ModelsDevPricingPipeline.refreshForUnknownModelsIfNeeded(
            providerID: "openai",
            modelIDs: ["still-unknown"],
            now: now,
            cacheRoot: root,
            client: client)

        #expect(outcome == .unavailable)
        #expect(transport.calls == 1)
    }

    @Test
    func failed_unknown_model_refresh_bounds_a_following_ttl_refresh_within_cooldown() async throws {
        let root = try Self.cacheRoot()
        let now = Date(timeIntervalSince1970: 47000)
        try ModelsDevCache.save(
            catalog: Self.fixtureCatalog(),
            fetchedAt: now.addingTimeInterval(-ModelsDevCache.ttlSeconds - 1),
            cacheRoot: root)
        let transport = TrackingTransport(result: .failure(MockError.failed))
        let client = ModelsDevClient(transport: transport)

        let outcome = await ModelsDevPricingPipeline.refreshForUnknownModelsIfNeeded(
            providerID: "openai",
            modelIDs: ["still-unknown"],
            now: now,
            cacheRoot: root,
            client: client)
        await ModelsDevPricingPipeline.refreshIfNeeded(
            now: now,
            cacheRoot: root,
            client: client)

        #expect(outcome == .unavailable)
        #expect(transport.calls == 1)
    }

    @Test
    func ttl_refresh_rechecks_cache_freshness_after_coordination() async throws {
        let root = try Self.cacheRoot()
        let now = Date(timeIntervalSince1970: 48000)
        try ModelsDevCache.save(
            catalog: Self.fixtureCatalog(),
            fetchedAt: now.addingTimeInterval(-ModelsDevCache.ttlSeconds - 1),
            cacheRoot: root)
        #expect(ModelsDevCache.load(now: now, cacheRoot: root).isStale)

        try ModelsDevCache.save(catalog: Self.fixtureCatalog(), fetchedAt: now, cacheRoot: root)
        let transport = TrackingTransport(result: .failure(MockError.failed))
        let cacheIsCurrent = await ModelsDevPricingPipeline.refreshStaleCache(
            now: now,
            cacheRoot: root,
            client: ModelsDevClient(transport: transport))

        #expect(cacheIsCurrent)
        #expect(transport.calls == 0)
    }

    @Test
    func failed_cache_save_does_not_report_pricing_available() async {
        let root = URL(fileURLWithPath: "/dev/null", isDirectory: true)
        let now = Date(timeIntervalSince1970: 50000)
        let refreshed = Data("""
        {
          "openai": {
            "id": "openai",
            "models": { "gpt-new": { "id": "gpt-new", "cost": { "input": 2, "output": 8 } } }
          },
          "anthropic": {
            "id": "anthropic",
            "models": { "claude-new": { "id": "claude-new", "cost": { "input": 3, "output": 15 } } }
          }
        }
        """.utf8)

        let outcome = await ModelsDevPricingPipeline.refreshForUnknownModelsIfNeeded(
            providerID: "openai",
            modelIDs: ["gpt-new"],
            now: now,
            cacheRoot: root,
            client: ModelsDevClient(transport: MockTransport(
                result: .success((refreshed, Self.response(status: 200))))))

        #expect(outcome == .unavailable)
    }

    @Test
    func refresh_accepts_model_churn_and_preserves_removed_pricing_as_fallback() async throws {
        let root = try Self.cacheRoot()
        let old = Date(timeIntervalSince1970: 1)
        try ModelsDevCache.save(catalog: Self.fixtureCatalog(), fetchedAt: old, cacheRoot: root)

        let partialCatalog = Data("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "shared-model": {
                "id": "shared-model",
                "cost": { "input": 99, "output": 99 }
              },
              "provider-a-new": {
                "id": "provider-a-new",
                "cost": { "input": 7, "output": 8 }
              }
            }
          },
          "anthropic": {
            "id": "anthropic",
            "models": {
              "shared-model": {
                "id": "shared-model",
                "cost": { "input": 99, "output": 99 }
              }
            }
          },
          "google-vertex-anthropic": {
            "id": "google-vertex-anthropic",
            "models": {
              "claude-sonnet-4-6": {
                "id": "claude-sonnet-4-6",
                "cost": { "input": 99, "output": 99 }
              }
            }
          }
        }
        """.utf8)
        await ModelsDevPricingPipeline.refreshIfNeeded(
            now: Date(timeIntervalSince1970: 1 + ModelsDevCache.ttlSeconds + 1),
            cacheRoot: root,
            client: ModelsDevClient(transport: MockTransport(
                result: .success((partialCatalog, Self.response(status: 200))))))

        let oldLookup = try #require(ModelsDevPricingPipeline.lookup(
            providerID: "openai",
            modelID: "gpt-4o-mini",
            cacheRoot: root))
        let newLookup = try #require(ModelsDevPricingPipeline.lookup(
            providerID: "openai",
            modelID: "provider-a-new",
            cacheRoot: root))
        let updatedLookup = try #require(ModelsDevPricingPipeline.lookup(
            providerID: "openai",
            modelID: "shared-model",
            cacheRoot: root))

        #expect(oldLookup.pricing.inputCostPerToken == 0.15 / 1_000_000.0)
        #expect(newLookup.pricing.inputCostPerToken == 7 / 1_000_000.0)
        #expect(updatedLookup.pricing.inputCostPerToken == 99 / 1_000_000.0)
    }

    @Test
    func accumulated_fallback_models_do_not_freeze_later_refreshes() async throws {
        let root = try Self.cacheRoot()
        let old = Date(timeIntervalSince1970: 1)
        let cachedCatalog = try Self.catalog("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "provider-a-old": { "id": "provider-a-old", "cost": { "input": 1, "output": 2 } }
            }
          },
          "anthropic": {
            "id": "anthropic",
            "models": {
              "provider-b-old": { "id": "provider-b-old", "cost": { "input": 3, "output": 4 } }
            }
          },
          "stale-a": {
            "id": "stale-a",
            "models": {
              "model-a": { "id": "model-a", "cost": { "input": 5, "output": 6 } }
            }
          },
          "stale-b": {
            "id": "stale-b",
            "models": {
              "model-b": { "id": "model-b", "cost": { "input": 7, "output": 8 } }
            }
          },
          "stale-c": {
            "id": "stale-c",
            "models": {
              "model-c": { "id": "model-c", "cost": { "input": 9, "output": 10 } }
            }
          }
        }
        """)
        ModelsDevCache.save(catalog: cachedCatalog, fetchedAt: old, cacheRoot: root)

        let fetchedCatalog = Data("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "provider-a-new": { "id": "provider-a-new", "cost": { "input": 11, "output": 12 } }
            }
          },
          "anthropic": {
            "id": "anthropic",
            "models": {
              "provider-b-new": { "id": "provider-b-new", "cost": { "input": 13, "output": 14 } }
            }
          }
        }
        """.utf8)
        await ModelsDevPricingPipeline.refreshIfNeeded(
            now: Date(timeIntervalSince1970: 1 + ModelsDevCache.ttlSeconds + 1),
            cacheRoot: root,
            client: ModelsDevClient(transport: MockTransport(
                result: .success((fetchedCatalog, Self.response(status: 200))))))

        let newLookup = try #require(ModelsDevPricingPipeline.lookup(
            providerID: "openai",
            modelID: "provider-a-new",
            cacheRoot: root))
        let fallbackLookup = try #require(ModelsDevPricingPipeline.lookup(
            providerID: "stale-a",
            modelID: "model-a",
            cacheRoot: root))

        #expect(newLookup.pricing.inputCostPerToken == 11 / 1_000_000.0)
        #expect(fallbackLookup.pricing.inputCostPerToken == 5 / 1_000_000.0)
    }

    @Test
    func historical_fallback_does_not_overwrite_a_refreshed_model_that_reuses_its_map_key() async throws {
        let root = try Self.cacheRoot()
        let old = Date(timeIntervalSince1970: 1)
        let cachedCatalog = try Self.catalog("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "rolling": { "id": "provider-a-old", "cost": { "input": 1, "output": 2 } }
            }
          },
          "anthropic": {
            "id": "anthropic",
            "models": {
              "provider-b-anchor": { "id": "provider-b-anchor", "cost": { "input": 3, "output": 4 } }
            }
          }
        }
        """)
        ModelsDevCache.save(catalog: cachedCatalog, fetchedAt: old, cacheRoot: root)

        let fetchedCatalog = Data("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "rolling": { "id": "provider-a-new", "cost": { "input": 99, "output": 100 } }
            }
          },
          "anthropic": {
            "id": "anthropic",
            "models": {
              "provider-b-anchor": { "id": "provider-b-anchor", "cost": { "input": 3, "output": 4 } }
            }
          }
        }
        """.utf8)
        await ModelsDevPricingPipeline.refreshIfNeeded(
            now: Date(timeIntervalSince1970: 1 + ModelsDevCache.ttlSeconds + 1),
            cacheRoot: root,
            client: ModelsDevClient(transport: MockTransport(
                result: .success((fetchedCatalog, Self.response(status: 200))))))

        let freshLookup = try #require(ModelsDevPricingPipeline.lookup(
            providerID: "openai",
            modelID: "provider-a-new",
            cacheRoot: root))
        let fallbackLookup = try #require(ModelsDevPricingPipeline.lookup(
            providerID: "openai",
            modelID: "provider-a-old",
            cacheRoot: root))

        #expect(freshLookup.pricing.inputCostPerToken == 99 / 1_000_000.0)
        #expect(fallbackLookup.pricing.inputCostPerToken == 1 / 1_000_000.0)
    }

    @Test
    func refresh_updates_cache_when_fetched_catalog_renames_model_key_but_keeps_id() async throws {
        let root = try Self.cacheRoot()
        let old = Date(timeIntervalSince1970: 1)
        try ModelsDevCache.save(catalog: Self.fixtureCatalog(), fetchedAt: old, cacheRoot: root)

        let renamedCatalog = Data("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "renamed-model-key": {
                "id": "gpt-4o-mini",
                "cost": { "input": 99, "output": 99 }
              },
              "shared-model": {
                "id": "shared-model",
                "cost": { "input": 99, "output": 99 }
              }
            }
          },
          "anthropic": {
            "id": "anthropic",
            "models": {
              "claude-sonnet-4-6": {
                "id": "claude-sonnet-4-6",
                "cost": { "input": 99, "output": 99 }
              },
              "shared-model": {
                "id": "shared-model",
                "cost": { "input": 99, "output": 99 }
              }
            }
          },
          "google-vertex-anthropic": {
            "id": "google-vertex-anthropic",
            "models": {
              "renamed-vertex-key": {
                "id": "claude-sonnet-4-6",
                "cost": { "input": 99, "output": 99 }
              }
            }
          }
        }
        """.utf8)
        await ModelsDevPricingPipeline.refreshIfNeeded(
            now: Date(timeIntervalSince1970: 1 + ModelsDevCache.ttlSeconds + 1),
            cacheRoot: root,
            client: ModelsDevClient(transport: MockTransport(
                result: .success((renamedCatalog, Self.response(status: 200))))))

        let lookup = try #require(ModelsDevPricingPipeline.lookup(
            providerID: "openai",
            modelID: "gpt-4o-mini",
            cacheRoot: root))

        #expect(lookup.normalizedModelID == "gpt-4o-mini")
        #expect(lookup.pricing.inputCostPerToken == 99 / 1_000_000.0)
    }

    @Test
    func refresh_preserves_cache_when_fetched_matching_model_is_not_priceable() async throws {
        let root = try Self.cacheRoot()
        let old = Date(timeIntervalSince1970: 1)
        try ModelsDevCache.save(catalog: Self.fixtureCatalog(), fetchedAt: old, cacheRoot: root)

        let partialCatalog = Data("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "gpt-4o-mini": {
                "id": "gpt-4o-mini",
                "cost": { "input": 99 }
              },
              "shared-model": {
                "id": "shared-model",
                "cost": { "input": 99, "output": 99 }
              }
            }
          },
          "anthropic": {
            "id": "anthropic",
            "models": {
              "claude-sonnet-4-6": {
                "id": "claude-sonnet-4-6",
                "cost": { "input": 99, "output": 99 }
              },
              "shared-model": {
                "id": "shared-model",
                "cost": { "input": 99, "output": 99 }
              }
            }
          },
          "google-vertex-anthropic": {
            "id": "google-vertex-anthropic",
            "models": {
              "claude-sonnet-4-6": {
                "id": "claude-sonnet-4-6",
                "cost": { "input": 99, "output": 99 }
              }
            }
          }
        }
        """.utf8)
        await ModelsDevPricingPipeline.refreshIfNeeded(
            now: Date(timeIntervalSince1970: 1 + ModelsDevCache.ttlSeconds + 1),
            cacheRoot: root,
            client: ModelsDevClient(transport: MockTransport(
                result: .success((partialCatalog, Self.response(status: 200))))))

        let lookup = try #require(ModelsDevPricingPipeline.lookup(
            providerID: "openai",
            modelID: "gpt-4o-mini",
            cacheRoot: root))
        let updatedLookup = try #require(ModelsDevPricingPipeline.lookup(
            providerID: "openai",
            modelID: "shared-model",
            cacheRoot: root))

        #expect(lookup.pricing.inputCostPerToken == 0.15 / 1_000_000.0)
        #expect(updatedLookup.pricing.inputCostPerToken == 99 / 1_000_000.0)
    }

    @Test
    func refresh_updates_cache_when_fetched_catalog_canonicalizes_alias_model_id() async throws {
        let root = try Self.cacheRoot()
        let old = Date(timeIntervalSince1970: 1)
        let cachedCatalog = try Self.catalog("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "gpt-4o-mini": {
                "id": "gpt-4o-mini",
                "cost": { "input": 0.15, "output": 0.6 }
              }
            }
          },
          "anthropic": {
            "id": "anthropic",
            "models": {
              "claude-sonnet-4-6": {
                "id": "claude-sonnet-4-6",
                "cost": { "input": 3, "output": 15 }
              }
            }
          },
          "google-vertex-anthropic": {
            "id": "google-vertex-anthropic",
            "models": {
              "snapshot-model@20250101": {
                "id": "snapshot-model@20250101",
                "cost": { "input": 3.1, "output": 15.1 }
              }
            }
          }
        }
        """)
        ModelsDevCache.save(catalog: cachedCatalog, fetchedAt: old, cacheRoot: root)

        let canonicalizedCatalog = Data("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "gpt-4o-mini": {
                "id": "gpt-4o-mini",
                "cost": { "input": 99, "output": 99 }
              },
              "shared-model": {
                "id": "shared-model",
                "cost": { "input": 99, "output": 99 }
              }
            }
          },
          "anthropic": {
            "id": "anthropic",
            "models": {
              "claude-sonnet-4-6": {
                "id": "claude-sonnet-4-6",
                "cost": { "input": 99, "output": 99 }
              },
              "shared-model": {
                "id": "shared-model",
                "cost": { "input": 99, "output": 99 }
              }
            }
          },
          "google-vertex-anthropic": {
            "id": "google-vertex-anthropic",
            "models": {
              "snapshot-model-20250101": {
                "id": "snapshot-model-20250101",
                "cost": { "input": 99, "output": 99 }
              }
            }
          }
        }
        """.utf8)
        await ModelsDevPricingPipeline.refreshIfNeeded(
            now: Date(timeIntervalSince1970: 1 + ModelsDevCache.ttlSeconds + 1),
            cacheRoot: root,
            client: ModelsDevClient(transport: MockTransport(
                result: .success((canonicalizedCatalog, Self.response(status: 200))))))

        let aliasLookup = try #require(ModelsDevPricingPipeline.lookup(
            providerID: "google-vertex-anthropic",
            modelID: "snapshot-model@20250101",
            cacheRoot: root))
        let canonicalLookup = try #require(ModelsDevPricingPipeline.lookup(
            providerID: "google-vertex-anthropic",
            modelID: "snapshot-model-20250101",
            cacheRoot: root))

        #expect(aliasLookup.pricing.inputCostPerToken == 99 / 1_000_000.0)
        #expect(canonicalLookup.pricing.inputCostPerToken == 99 / 1_000_000.0)
    }

    @Test
    func fallback_merge_treats_default_alias_as_the_canonical_base_model() throws {
        let cachedCatalog = try Self.catalog("""
        {
          "anthropic": {
            "id": "anthropic",
            "models": {
              "base-model@default": {
                "id": "base-model@default",
                "cost": { "input": 3, "output": 15 }
              }
            }
          }
        }
        """)
        let refreshedCatalog = try Self.catalog("""
        {
          "anthropic": {
            "id": "anthropic",
            "models": {
              "base-model": {
                "id": "base-model",
                "cost": { "input": 99, "output": 100 }
              }
            }
          }
        }
        """)

        let merged = refreshedCatalog.mergingFallbackPricing(from: cachedCatalog)
        let aliasLookup = try #require(merged.pricing(
            providerID: "anthropic",
            modelID: "base-model@default"))

        #expect(aliasLookup.pricing.inputCostPerToken == 99 / 1_000_000.0)
        #expect(merged.providers["anthropic"]?.models.count == 1)
    }

    @Test
    func fallback_merge_treats_provider_version_alias_as_the_canonical_base_model() throws {
        let cachedCatalog = try Self.catalog("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "openai/base-model-v1:0": {
                "id": "openai/base-model-v1:0",
                "cost": { "input": 3, "output": 15 }
              }
            }
          }
        }
        """)
        let refreshedCatalog = try Self.catalog("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "base-model": {
                "id": "base-model",
                "cost": { "input": 99, "output": 100 }
              }
            }
          }
        }
        """)

        let merged = refreshedCatalog.mergingFallbackPricing(from: cachedCatalog)
        let aliasLookup = try #require(merged.pricing(
            providerID: "openai",
            modelID: "openai/base-model-v1:0"))

        #expect(aliasLookup.pricing.inputCostPerToken == 99 / 1_000_000.0)
        #expect(merged.providers["openai"]?.models.count == 1)
    }

    @Test
    func refresh_keeps_historical_pinned_pricing_while_accepting_a_new_snapshot() async throws {
        let root = try Self.cacheRoot()
        let old = Date(timeIntervalSince1970: 1)
        let cachedCatalog = try Self.catalog("""
        {
          "google-vertex-anthropic": {
            "id": "google-vertex-anthropic",
            "models": {
              "snapshot-model@20250101": {
                "id": "snapshot-model@20250101",
                "cost": { "input": 3, "output": 15 }
              }
            }
          }
        }
        """)
        ModelsDevCache.save(catalog: cachedCatalog, fetchedAt: old, cacheRoot: root)

        let fetchedCatalog = Data("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "provider-a-anchor": {
                "id": "provider-a-anchor",
                "cost": { "input": 1, "output": 2 }
              }
            }
          },
          "anthropic": {
            "id": "anthropic",
            "models": {
              "provider-b-anchor": {
                "id": "provider-b-anchor",
                "cost": { "input": 3, "output": 4 }
              }
            }
          },
          "google-vertex-anthropic": {
            "id": "google-vertex-anthropic",
            "models": {
              "snapshot-model@20250201": {
                "id": "snapshot-model@20250201",
                "cost": { "input": 99, "output": 99 }
              }
            }
          }
        }
        """.utf8)
        await ModelsDevPricingPipeline.refreshIfNeeded(
            now: Date(timeIntervalSince1970: 1 + ModelsDevCache.ttlSeconds + 1),
            cacheRoot: root,
            client: ModelsDevClient(transport: MockTransport(
                result: .success((fetchedCatalog, Self.response(status: 200))))))

        let oldLookup = try #require(ModelsDevPricingPipeline.lookup(
            providerID: "google-vertex-anthropic",
            modelID: "snapshot-model@20250101",
            cacheRoot: root))
        let newLookup = try #require(ModelsDevPricingPipeline.lookup(
            providerID: "google-vertex-anthropic",
            modelID: "snapshot-model@20250201",
            cacheRoot: root))

        #expect(oldLookup.pricing.inputCostPerToken == 3 / 1_000_000.0)
        #expect(newLookup.pricing.inputCostPerToken == 99 / 1_000_000.0)
    }

    @Test
    func refresh_preserves_dated_snapshot_when_fetched_catalog_only_keeps_base_model() async throws {
        let root = try Self.cacheRoot()
        let old = Date(timeIntervalSince1970: 1)
        let cachedCatalog = try Self.catalog("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "historical-map-key": {
                "id": "snapshot-model-2025-01-01",
                "cost": { "input": 3, "output": 15 }
              }
            }
          },
          "anthropic": {
            "id": "anthropic",
            "models": {
              "provider-b-anchor": {
                "id": "provider-b-anchor",
                "cost": { "input": 3, "output": 4 }
              }
            }
          }
        }
        """)
        ModelsDevCache.save(catalog: cachedCatalog, fetchedAt: old, cacheRoot: root)

        let fetchedCatalog = Data("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "snapshot-model": {
                "id": "snapshot-model",
                "cost": { "input": 99, "output": 99 }
              }
            }
          },
          "anthropic": {
            "id": "anthropic",
            "models": {
              "provider-b-anchor": {
                "id": "provider-b-anchor",
                "cost": { "input": 3, "output": 4 }
              }
            }
          }
        }
        """.utf8)
        await ModelsDevPricingPipeline.refreshIfNeeded(
            now: Date(timeIntervalSince1970: 1 + ModelsDevCache.ttlSeconds + 1),
            cacheRoot: root,
            client: ModelsDevClient(transport: MockTransport(
                result: .success((fetchedCatalog, Self.response(status: 200))))))

        let snapshotLookup = try #require(ModelsDevPricingPipeline.lookup(
            providerID: "openai",
            modelID: "snapshot-model-2025-01-01",
            cacheRoot: root))
        let baseLookup = try #require(ModelsDevPricingPipeline.lookup(
            providerID: "openai",
            modelID: "snapshot-model",
            cacheRoot: root))

        #expect(snapshotLookup.pricing.inputCostPerToken == 3 / 1_000_000.0)
        #expect(baseLookup.pricing.inputCostPerToken == 99 / 1_000_000.0)
    }

    @Test
    func compact_snapshot_alias_prefers_snapshot_pricing_over_base_pricing() throws {
        let catalog = try Self.catalog("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "snapshot-model": {
                "id": "snapshot-model",
                "cost": { "input": 99, "output": 100 }
              },
              "snapshot-model-20250101": {
                "id": "snapshot-model-20250101",
                "cost": { "input": 3, "output": 15 }
              }
            }
          }
        }
        """)

        let lookup = try #require(catalog.pricing(
            providerID: "openai",
            modelID: "snapshot-model@20250101"))

        #expect(lookup.pricing.inputCostPerToken == 3 / 1_000_000.0)
        #expect(lookup.normalizedModelID == "snapshot-model-20250101")
    }

    @Test
    func refresh_ignores_unpriceable_models_in_old_cache_continuity_check() async throws {
        let root = try Self.cacheRoot()
        let old = Date(timeIntervalSince1970: 1)
        let cachedCatalog = try Self.catalog("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "gpt-4o-mini": {
                "id": "gpt-4o-mini",
                "cost": { "input": 0.15, "output": 0.6 }
              },
              "unpriced-model": {
                "id": "unpriced-model"
              }
            }
          }
        }
        """)
        ModelsDevCache.save(catalog: cachedCatalog, fetchedAt: old, cacheRoot: root)

        let fetchedCatalog = Data("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "gpt-4o-mini": {
                "id": "gpt-4o-mini",
                "cost": { "input": 99, "output": 99 }
              }
            }
          },
          "anthropic": {
            "id": "anthropic",
            "models": {
              "provider-b-anchor": {
                "id": "provider-b-anchor",
                "cost": { "input": 3, "output": 4 }
              }
            }
          }
        }
        """.utf8)
        await ModelsDevPricingPipeline.refreshIfNeeded(
            now: Date(timeIntervalSince1970: 1 + ModelsDevCache.ttlSeconds + 1),
            cacheRoot: root,
            client: ModelsDevClient(transport: MockTransport(
                result: .success((fetchedCatalog, Self.response(status: 200))))))

        let lookup = try #require(ModelsDevPricingPipeline.lookup(
            providerID: "openai",
            modelID: "gpt-4o-mini",
            cacheRoot: root))

        #expect(lookup.pricing.inputCostPerToken == 99 / 1_000_000.0)
    }

    @Test
    func fresh_cache_does_not_refresh() async throws {
        let root = try Self.cacheRoot()
        try ModelsDevCache.save(catalog: Self.fixtureCatalog(), fetchedAt: Date(), cacheRoot: root)
        let transport = TrackingTransport(result: .failure(MockError.failed))

        await ModelsDevPricingPipeline.refreshIfNeeded(
            now: Date(),
            cacheRoot: root,
            client: ModelsDevClient(transport: transport))

        #expect(transport.calls == 0)
    }

    @Test
    func corrupt_cache_is_ignored_safely() throws {
        let root = try Self.cacheRoot()
        let url = ModelsDevCache.cacheFileURL(cacheRoot: root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)

        let load = ModelsDevCache.load(cacheRoot: root)

        #expect(load.artifact == nil)
        #expect(load.isStale)
        #expect(load.error == .invalidJSON)
    }

    @Test
    func serves_decoded_catalog_from_memo_while_the_file_is_unchanged() throws {
        let root = try Self.cacheRoot()
        try ModelsDevCache.save(catalog: Self.fixtureCatalog(), fetchedAt: Date(), cacheRoot: root)
        let url = ModelsDevCache.cacheFileURL(cacheRoot: root)

        // Pin a whole-second modification date so the memo key (which compares modification dates) round-trips
        // deterministically through the filesystem.
        let pinnedDate = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: pinnedDate], ofItemAtPath: url.path)

        // Prime the in-memory memo with a successful decode.
        let primed = ModelsDevCache.load(cacheRoot: root)
        let cachedArtifact = try #require(primed.artifact)

        // Corrupt the file contents while preserving its size and modification date, so the on-disk identity
        // the memo keys on is unchanged. A re-decode would now fail; a memo hit returns the cached artifact.
        let size = try #require(
            try (FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber).intValue
        try Data(repeating: 0, count: size).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: pinnedDate], ofItemAtPath: url.path)

        let reloaded = ModelsDevCache.load(cacheRoot: root)

        #expect(reloaded.error == nil)
        #expect(reloaded.artifact == cachedArtifact)
    }

    @Test
    func saving_a_new_catalog_invalidates_the_memo() throws {
        let root = try Self.cacheRoot()
        try ModelsDevCache.save(catalog: Self.fixtureCatalog(), fetchedAt: Date(), cacheRoot: root)
        #expect(ModelsDevCache.load(cacheRoot: root).artifact?.catalog.providers["openai"] != nil)

        // Overwriting the cache must drop the memo so the next load reflects the freshly written catalog.
        ModelsDevCache.save(catalog: ModelsDevCatalog(providers: [:]), fetchedAt: Date(), cacheRoot: root)
        let reloaded = ModelsDevCache.load(cacheRoot: root)

        #expect(reloaded.error == nil)
        #expect(reloaded.artifact?.catalog.providers.isEmpty == true)
    }

    @Test
    func serves_a_failed_load_from_memo_while_the_file_is_unchanged() throws {
        let root = try Self.cacheRoot()
        let url = ModelsDevCache.cacheFileURL(cacheRoot: root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let validData = try Self.encodedArtifactData()

        // Write invalid JSON of the same size as a valid encoding, with a pinned modification date, then prime
        // the memo with the resulting failure.
        let pinnedDate = Date(timeIntervalSince1970: 1_700_000_000)
        try Data(repeating: 0x7B, count: validData.count).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: pinnedDate], ofItemAtPath: url.path)
        #expect(ModelsDevCache.load(cacheRoot: root).error == .invalidJSON)

        // Replace the bytes with a valid encoding of identical size + modification date. A re-read would now
        // succeed, so a returned failure proves the unchanged-identity file was not read and decoded again.
        try validData.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: pinnedDate], ofItemAtPath: url.path)
        let reloaded = ModelsDevCache.load(cacheRoot: root)

        #expect(reloaded.error == .invalidJSON)
        #expect(reloaded.artifact == nil)
    }

    @Test
    func client_fetches_with_mock_transport() async throws {
        let data = try Self.fixtureData()
        let client = ModelsDevClient(transport: MockTransport(result: .success((data, Self.response(status: 200)))))

        let catalog = try await client.fetchCatalog()

        #expect(catalog.providers["google-vertex-anthropic"]?.models["claude-sonnet-4-6"]?.cost?.input == 3.1)
    }

    @Test
    func client_reports_http_and_json_failures() async throws {
        let data = try Self.fixtureData()
        let httpClient = ModelsDevClient(transport: MockTransport(result: .success((data, Self.response(status: 500)))))
        let jsonClient = ModelsDevClient(transport: MockTransport(
            result: .success((Data("not json".utf8), Self.response(status: 200)))))

        await #expect(throws: ModelsDevClient.Error.httpStatus(500)) {
            _ = try await httpClient.fetchCatalog()
        }
        await #expect(throws: ModelsDevClient.Error.invalidJSON) {
            _ = try await jsonClient.fetchCatalog()
        }
    }

    private static func fixtureData() throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: "models-dev-subset",
            withExtension: "json",
            subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private static func fixtureCatalog() throws -> ModelsDevCatalog {
        try JSONDecoder().decode(ModelsDevCatalog.self, from: self.fixtureData())
    }

    /// A valid `ModelsDevCacheArtifact` encoding, written the same way `ModelsDevCache.save` writes the file.
    private static func encodedArtifactData() throws -> Data {
        let artifact = try ModelsDevCacheArtifact(
            version: ModelsDevCache.artifactVersion,
            fetchedAt: Date(timeIntervalSince1970: 0),
            catalog: self.fixtureCatalog())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(artifact)
    }

    private static func catalog(_ json: String) throws -> ModelsDevCatalog {
        try JSONDecoder().decode(ModelsDevCatalog.self, from: Data(json.utf8))
    }

    private static func cacheRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-modelsdev-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func response(status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://models.dev/api.json")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil)!
    }
}

private enum MockError: Error {
    case failed
}

private struct MockTransport: ModelsDevHTTPTransport {
    let result: Result<(Data, URLResponse), Error>

    func data(for _: URLRequest) async throws -> (Data, URLResponse) {
        try self.result.get()
    }
}

private final class TrackingTransport: ModelsDevHTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    let result: Result<(Data, URLResponse), Error>
    let delayNanoseconds: UInt64

    var calls: Int {
        self.lock.withLock { self.callCount }
    }

    init(result: Result<(Data, URLResponse), Error>, delayNanoseconds: UInt64 = 0) {
        self.result = result
        self.delayNanoseconds = delayNanoseconds
    }

    func data(for _: URLRequest) async throws -> (Data, URLResponse) {
        self.lock.withLock { self.callCount += 1 }
        if self.delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: self.delayNanoseconds)
        }
        return try self.result.get()
    }
}
