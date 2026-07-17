import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct CodexAccountsSectionStateTests {
    @Test
    func system_badge_shows_for_merged_live_row() {
        let accountID = UUID()
        let mergedLiveAccount = CodexVisibleAccount(
            id: "merged@example.com",
            email: "merged@example.com",
            storedAccountID: accountID,
            selectionSource: .liveSystem,
            isActive: true,
            isLive: true,
            canReauthenticate: true,
            canRemove: true)
        let state = CodexAccountsSectionState(
            visibleAccounts: [mergedLiveAccount],
            activeVisibleAccountID: mergedLiveAccount.id,
            liveVisibleAccountID: mergedLiveAccount.id,
            hasUnreadableManagedAccountStore: false,
            isAuthenticatingManagedAccount: false,
            authenticatingManagedAccountID: nil,
            isRemovingManagedAccount: false,
            isAuthenticatingLiveAccount: false,
            isPromotingSystemAccount: false,
            notice: nil)

        #expect(state.showsLiveBadge(for: mergedLiveAccount))
    }

    @Test
    func system_promotion_availability_uses_live_visible_account_and_stored_account_id() {
        let managedAccountID = UUID()
        let liveAccount = CodexVisibleAccount(
            id: "live@example.com",
            email: "live@example.com",
            storedAccountID: nil,
            selectionSource: .liveSystem,
            isActive: false,
            isLive: true,
            canReauthenticate: true,
            canRemove: false)
        let managedAccount = CodexVisibleAccount(
            id: "managed:\(managedAccountID.uuidString.lowercased())",
            email: "managed@example.com",
            storedAccountID: managedAccountID,
            selectionSource: .managedAccount(id: managedAccountID),
            isActive: true,
            isLive: false,
            canReauthenticate: true,
            canRemove: true)
        let state = CodexAccountsSectionState(
            visibleAccounts: [liveAccount, managedAccount],
            activeVisibleAccountID: managedAccount.id,
            liveVisibleAccountID: liveAccount.id,
            hasUnreadableManagedAccountStore: false,
            isAuthenticatingManagedAccount: false,
            authenticatingManagedAccountID: nil,
            isRemovingManagedAccount: false,
            isAuthenticatingLiveAccount: false,
            isPromotingSystemAccount: false,
            notice: nil)

        #expect(state.canPromoteToSystem(liveAccount) == false)
        #expect(state.canPromoteToSystem(managedAccount))
    }

    @Test
    func system_promotion_controls_disable_while_conflicting_work_is_running() {
        let managedAccountID = UUID()
        let liveAccount = CodexVisibleAccount(
            id: "live@example.com",
            email: "live@example.com",
            storedAccountID: nil,
            selectionSource: .liveSystem,
            isActive: false,
            isLive: true,
            canReauthenticate: true,
            canRemove: false)
        let managedAccount = CodexVisibleAccount(
            id: "managed:\(managedAccountID.uuidString.lowercased())",
            email: "managed@example.com",
            storedAccountID: managedAccountID,
            selectionSource: .managedAccount(id: managedAccountID),
            isActive: true,
            isLive: false,
            canReauthenticate: true,
            canRemove: true)
        let state = CodexAccountsSectionState(
            visibleAccounts: [liveAccount, managedAccount],
            activeVisibleAccountID: managedAccount.id,
            liveVisibleAccountID: liveAccount.id,
            hasUnreadableManagedAccountStore: false,
            isAuthenticatingManagedAccount: false,
            authenticatingManagedAccountID: nil,
            isRemovingManagedAccount: true,
            isAuthenticatingLiveAccount: false,
            isPromotingSystemAccount: false,
            notice: nil)

        #expect(state.isSystemSelectionDisabled)
        #expect(state.canPromoteToSystem(managedAccount) == false)
    }

    @Test
    func system_display_does_not_fall_back_when_no_live_account_exists() {
        let managedAccountID = UUID()
        let managedAccount = CodexVisibleAccount(
            id: "managed:\(managedAccountID.uuidString.lowercased())",
            email: "managed@example.com",
            storedAccountID: managedAccountID,
            selectionSource: .managedAccount(id: managedAccountID),
            isActive: true,
            isLive: false,
            canReauthenticate: true,
            canRemove: true)
        let state = CodexAccountsSectionState(
            visibleAccounts: [managedAccount],
            activeVisibleAccountID: managedAccount.id,
            liveVisibleAccountID: nil,
            hasUnreadableManagedAccountStore: false,
            isAuthenticatingManagedAccount: false,
            authenticatingManagedAccountID: nil,
            isRemovingManagedAccount: false,
            isAuthenticatingLiveAccount: false,
            isPromotingSystemAccount: false,
            notice: nil)

        #expect(state.systemVisibleAccount == nil)
        #expect(state.showsSystemPicker)
        #expect(state.systemDisplayName == "No system account")
    }

    @Test
    func remove_in_flight_blocks_add_reauth_and_remove_actions() {
        let managedAccountID = UUID()
        let managedAccount = CodexVisibleAccount(
            id: "managed:\(managedAccountID.uuidString.lowercased())",
            email: "managed@example.com",
            storedAccountID: managedAccountID,
            selectionSource: .managedAccount(id: managedAccountID),
            isActive: true,
            isLive: false,
            canReauthenticate: true,
            canRemove: true)
        let state = CodexAccountsSectionState(
            visibleAccounts: [managedAccount],
            activeVisibleAccountID: managedAccount.id,
            liveVisibleAccountID: nil,
            hasUnreadableManagedAccountStore: false,
            isAuthenticatingManagedAccount: false,
            authenticatingManagedAccountID: nil,
            isRemovingManagedAccount: true,
            isAuthenticatingLiveAccount: false,
            isPromotingSystemAccount: false,
            notice: nil)

        #expect(state.canAddAccount == false)
        #expect(state.canReauthenticate(managedAccount) == false)
        #expect(state.canRemove(managedAccount) == false)
    }

    @Test
    func promotion_in_flight_blocks_add_reauth_and_remove_actions() {
        let managedAccountID = UUID()
        let managedAccount = CodexVisibleAccount(
            id: "managed:\(managedAccountID.uuidString.lowercased())",
            email: "managed@example.com",
            storedAccountID: managedAccountID,
            selectionSource: .managedAccount(id: managedAccountID),
            isActive: true,
            isLive: false,
            canReauthenticate: true,
            canRemove: true)
        let state = CodexAccountsSectionState(
            visibleAccounts: [managedAccount],
            activeVisibleAccountID: managedAccount.id,
            liveVisibleAccountID: nil,
            hasUnreadableManagedAccountStore: false,
            isAuthenticatingManagedAccount: false,
            authenticatingManagedAccountID: nil,
            isRemovingManagedAccount: false,
            isAuthenticatingLiveAccount: false,
            isPromotingSystemAccount: true,
            notice: nil)

        #expect(state.canAddAccount == false)
        #expect(state.canReauthenticate(managedAccount) == false)
        #expect(state.canRemove(managedAccount) == false)
    }
}
