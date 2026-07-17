import CodexBarCore
import Testing

struct ProviderLabelMetadataCharacterizationTests {
    // MARK: - Label non-empty constraints

    @Test
    func displayName_is_non_empty_for_all_providers() {
        for descriptor in ProviderDescriptorRegistry.all {
            #expect(
                !descriptor.metadata.displayName.isEmpty,
                "Provider \(descriptor.id.rawValue) has empty displayName.")
        }
    }

    @Test
    func sessionLabel_is_non_empty_for_all_providers() {
        for descriptor in ProviderDescriptorRegistry.all {
            #expect(
                !descriptor.metadata.sessionLabel.isEmpty,
                "Provider \(descriptor.id.rawValue) has empty sessionLabel.")
        }
    }

    // MARK: - Known empty weeklyLabel exceptions

    @Test
    func weeklyLabel_empty_providers_are_explicitly_characterized() {
        // Allowlist of providers known to have empty weeklyLabel on current main.
        // If a new provider is added with empty weeklyLabel, this test fails and
        // requires a deliberate decision to add it here — preventing silent regressions.
        let knownEmptyWeeklyLabelProviders: Set<UsageProvider> = [.mistral]
        for descriptor in ProviderDescriptorRegistry.all where descriptor.metadata.weeklyLabel.isEmpty {
            #expect(
                knownEmptyWeeklyLabelProviders.contains(descriptor.id),
                "Provider \(descriptor.id.rawValue) has empty weeklyLabel and is not in the known exception list.")
        }
    }

    // MARK: - Invariant: supportsOpus implies opusLabel

    @Test
    func supportsOpus_providers_declare_non_empty_opusLabel() {
        for descriptor in ProviderDescriptorRegistry.all where descriptor.metadata.supportsOpus {
            #expect(
                descriptor.metadata.opusLabel != nil && !descriptor.metadata.opusLabel!.isEmpty,
                "Provider \(descriptor.id.rawValue) has supportsOpus=true but opusLabel is nil or empty.")
        }
    }

    // MARK: - opusLabel structural constraint

    @Test
    func opusLabel_is_nil_or_non_empty() {
        for descriptor in ProviderDescriptorRegistry.all {
            if let opusLabel = descriptor.metadata.opusLabel {
                #expect(
                    !opusLabel.isEmpty,
                    "Provider \(descriptor.id.rawValue) has empty opusLabel string instead of nil.")
            }
        }
    }
}
