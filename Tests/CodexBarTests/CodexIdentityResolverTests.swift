import CodexBarCore
import Testing

struct CodexIdentityResolverTests {
    @Test
    func resolver_prefers_provider_account_over_email() {
        let identity = CodexIdentityResolver.resolve(
            accountId: "account-123",
            email: "Person@example.com")

        #expect(identity == .providerAccount(id: "account-123"))
    }

    @Test
    func resolver_falls_back_to_normalized_email_when_provider_account_missing() {
        let identity = CodexIdentityResolver.resolve(
            accountId: nil,
            email: " Person@example.com ")

        #expect(identity == .emailOnly(normalizedEmail: "person@example.com"))
    }

    @Test
    func resolver_returns_unresolved_when_account_data_missing() {
        let identity = CodexIdentityResolver.resolve(accountId: nil, email: nil)

        #expect(identity == .unresolved)
    }

    @Test
    func provider_account_does_not_equal_email_fallback_even_when_email_matches() {
        let providerAccount = CodexIdentityResolver.resolve(
            accountId: "account-123",
            email: "person@example.com")
        let emailOnly = CodexIdentityResolver.resolve(
            accountId: nil,
            email: "person@example.com")

        #expect(providerAccount == .providerAccount(id: "account-123"))
        #expect(emailOnly == .emailOnly(normalizedEmail: "person@example.com"))
        #expect(providerAccount != emailOnly)
    }
}
