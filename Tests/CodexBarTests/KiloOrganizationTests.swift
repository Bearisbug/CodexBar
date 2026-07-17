import Foundation
import Testing
@testable import CodexBarCore

struct KiloOrganizationTests {
    @Test
    func decodes_from_canonical_Kilo_profile_payload() throws {
        let json = #"""
        { "id": "org_123", "name": "Acme Corp", "role": "owner" }
        """#
        let data = Data(json.utf8)
        let org = try JSONDecoder().decode(KiloOrganization.self, from: data)
        #expect(org.id == "org_123")
        #expect(org.name == "Acme Corp")
        #expect(org.role == "owner")
    }

    @Test
    func decodes_when_role_missing() throws {
        let json = #"""
        { "id": "org_xyz", "name": "No Role Org" }
        """#
        let data = Data(json.utf8)
        let org = try JSONDecoder().decode(KiloOrganization.self, from: data)
        #expect(org.role == nil)
    }

    @Test
    func equality_covers_all_stored_fields() {
        let a = KiloOrganization(id: "org_1", name: "A", role: "member")
        let b = KiloOrganization(id: "org_1", name: "A", role: "member")
        let differentRole = KiloOrganization(id: "org_1", name: "A", role: "owner")
        #expect(a == b)
        #expect(a != differentRole)
    }
}

struct KiloUsageScopeTests {
    @Test
    func personal_scope_identifier_is_stable() {
        let scope: KiloUsageScope = .personal
        #expect(scope.scopeIdentifier == "personal")
    }

    @Test
    func organization_scope_identifier_prefixes_id() {
        let scope: KiloUsageScope = .organization(id: "org_42", name: "Acme")
        #expect(scope.scopeIdentifier == "org:org_42")
    }

    @Test
    func organizationID_is_nil_for_personal() {
        #expect(KiloUsageScope.personal.organizationID == nil)
    }

    @Test
    func organizationID_returns_id_for_organization() {
        let scope: KiloUsageScope = .organization(id: "org_42", name: "Acme")
        #expect(scope.organizationID == "org_42")
    }

    @Test
    func displayName_falls_back_to_Personal_for_personal() {
        #expect(KiloUsageScope.personal.displayName == "Personal")
    }

    @Test
    func displayName_uses_org_name_for_organization() {
        let scope: KiloUsageScope = .organization(id: "org_42", name: "Acme")
        #expect(scope.displayName == "Acme")
    }
}
