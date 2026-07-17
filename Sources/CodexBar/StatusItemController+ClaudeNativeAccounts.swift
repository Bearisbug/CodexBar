import AppKit
import CodexBarCore

/// Native Claude account rows in the Claude status item menu.
/// Design: `docs/claude-native-multi-account-clash.md` (PAGE_MENU_CLAUDE, REQ-006).
extension StatusItemController {
    func addClaudeNativeAccountItemsIfNeeded(to menu: NSMenu, provider: UsageProvider) {
        guard provider == .claude else { return }
        // ADR-005: while the claude-swap adapter is enabled it owns Claude multi-account UI.
        guard !self.settings.claudeSwapEnabled else { return }
        guard let set = try? FileClaudeManagedAccountStore().load(), set.accounts.count >= 2 else { return }

        let backups = KeychainClaudeCredentialBackupStore()
        menu.addItem(.sectionHeader(title: "Claude Accounts"))
        for account in set.accounts {
            let title = self.claudeNativeAccountTitle(account, hasBackup: backups.load(accountID: account.id) != nil)
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            if account.isActive {
                item.state = .on
            } else if backups.load(accountID: account.id) != nil {
                item.action = #selector(self.claudeNativeAccountItemClicked(_:))
                item.target = self
                item.representedObject = account.id.uuidString
            }
            menu.addItem(item)
        }
        menu.addItem(.separator())
    }

    private func claudeNativeAccountTitle(_ account: ClaudeManagedAccount, hasBackup: Bool) -> String {
        var title = account.customLabel?.isEmpty == false
            ? account.displayTitle
            : PersonalInfoRedactor.redactEmail(account.email, isEnabled: self.settings.hidePersonalInfo)
        if title.isEmpty {
            title = "Account"
        }
        if !hasBackup {
            title += " (needs capture)"
        }
        return title
    }

    @objc private func claudeNativeAccountItemClicked(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let accountID = UUID(uuidString: idString)
        else {
            return
        }
        Task { @MainActor in
            do {
                try await ClaudeAccountServiceHolder.shared.switchTo(accountID: accountID)
                await ProviderInteractionContext.$current.withValue(.userInitiated) {
                    await self.store.refreshProvider(.claude, allowDisabled: true)
                }
                self.invalidateMenus(refreshOpenMenus: false)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Claude account switch failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }
}
