import AppKit
import CodexBarCore
import SwiftUI

/// Single shared service instance: the settings pane and the status item menu must
/// funnel through the same actor so switch/capture/import transactions stay mutually
/// exclusive (design doc §16).
@MainActor
enum ClaudeAccountServiceHolder {
    static let shared = ClaudeAccountService()
}

/// Native Claude multi-account management section in the Claude provider pane.
/// Design: `docs/claude-native-multi-account-clash.md` (PAGE_PREF_CLAUDE_ACCOUNTS).
@MainActor
struct ClaudeAccountsSectionView: View {
    private static let noProxySyncTag = ""

    @Bindable var settings: SettingsStore
    let refreshClaude: @MainActor () async -> Void

    @State private var accounts: [ClaudeManagedAccount] = []
    @State private var backedUpAccountIDs: Set<UUID> = []
    @State private var aliasDrafts: [UUID: String] = [:]
    @State private var clashSettings = ClashConnectionSettings()
    @State private var clashSocketPathDraft = ""
    @State private var clashGroupDraft = ""
    @State private var clashNodes: [String] = []
    @State private var clashCurrentNode: String?
    @State private var clashUnreachableDetail: String?
    @State private var notice: String?
    @State private var noticeIsError = false
    @State private var isBusy = false
    @State private var pendingRemoval: ClaudeManagedAccount?
    @State private var canImportFromCCSwitcher = false

    private var service: ClaudeAccountService {
        ClaudeAccountServiceHolder.shared
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Accounts")
                .font(.headline)

            if self.accounts.isEmpty {
                Text("No native Claude accounts yet. Capture the current sign-in or import from CCSwitcher.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(self.accounts) { account in
                        self.accountRow(account)
                    }
                }
            }

            HStack(spacing: 8) {
                Button("Add current account") {
                    Task { await self.captureCurrentAccount() }
                }
                .disabled(self.isBusy)
                if self.canImportFromCCSwitcher {
                    Button("Import from CCSwitcher…") {
                        Task { await self.importFromCCSwitcher() }
                    }
                    .disabled(self.isBusy)
                }
                if self.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let notice = self.notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(self.noticeIsError ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .textSelection(.enabled)
            }

            Divider()

            self.clashConnectionSection
        }
        .task {
            await self.reloadAll()
        }
        .alert(
            "Remove Claude account?",
            isPresented: Binding(
                get: { self.pendingRemoval != nil },
                set: { if !$0 { self.pendingRemoval = nil } }),
            actions: {
                Button("Remove", role: .destructive) {
                    if let account = self.pendingRemoval {
                        Task { await self.removeAccount(account) }
                    }
                    self.pendingRemoval = nil
                }
                Button(L("cancel"), role: .cancel) { self.pendingRemoval = nil }
            },
            message: {
                if let account = self.pendingRemoval {
                    Text("\(account.displayTitle) and its credential backup will be removed from CodexBar. "
                        + "CCSwitcher data is not touched.")
                }
            })
    }

    // MARK: - Rows

    private func accountRow(_ account: ClaudeManagedAccount) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(account.isActive ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                TextField(
                    "Alias",
                    text: Binding(
                        get: { self.aliasDrafts[account.id] ?? (account.customLabel ?? "") },
                        set: { self.aliasDrafts[account.id] = $0 }),
                    prompt: Text(self.redactedEmail(account)))
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .onSubmit {
                        Task { await self.commitAlias(account) }
                    }
                Text(self.redactedEmail(account))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 130, alignment: .leading)

            if let plan = account.subscriptionType, !plan.isEmpty {
                Text(plan.capitalized)
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }

            if !self.backedUpAccountIDs.contains(account.id) {
                Text("needs capture")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            Spacer()

            self.clashNodePicker(account)

            Button("Switch") {
                Task { await self.switchTo(account) }
            }
            .controlSize(.small)
            .disabled(account.isActive || self.isBusy || !self.backedUpAccountIDs.contains(account.id))

            Button {
                self.pendingRemoval = account
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(self.isBusy)
        }
    }

    @ViewBuilder
    private func clashNodePicker(_ account: ClaudeManagedAccount) -> some View {
        // Keep a vanished bound node selectable so Clash downtime does not silently drop bindings.
        let extraNode: [String] = if let node = account.clashNode, !self.clashNodes.contains(node) {
            [node]
        } else {
            []
        }
        Picker(
            "",
            selection: Binding(
                get: { account.clashNode ?? Self.noProxySyncTag },
                set: { newValue in
                    Task { await self.setClashBinding(account, node: newValue) }
                })) {
            Text("No proxy sync").tag(Self.noProxySyncTag)
            ForEach(extraNode + self.clashNodes, id: \.self) { node in
                Text(node).tag(node)
            }
        }
        .labelsHidden()
        .controlSize(.small)
        .frame(width: 150)
        .disabled(self.isBusy || (self.clashNodes.isEmpty && account.clashNode == nil))
    }

    private var clashConnectionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Clash Verge connection")
                .font(.subheadline)
            HStack(spacing: 8) {
                TextField("Socket path", text: self.$clashSocketPathDraft)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(minWidth: 220)
                    .onSubmit { Task { await self.commitClashSettings() } }
                TextField("Group", text: self.$clashGroupDraft)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(width: 110)
                    .onSubmit { Task { await self.commitClashSettings() } }
                Button {
                    Task { await self.commitClashSettings() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Save connection settings and refresh the node list")
            }
            Text(self.clashStatusText)
                .font(.caption)
                .foregroundStyle(self.clashUnreachableDetail == nil ? AnyShapeStyle(.secondary)
                    : AnyShapeStyle(.orange))
        }
    }

    private var clashStatusText: String {
        if let detail = self.clashUnreachableDetail {
            return "Clash unreachable — bound accounts cannot switch. (\(detail))"
        }
        let now = self.clashCurrentNode ?? "unknown"
        return "Clash \(self.clashSettings.defaultGroup): \(now) · \(self.clashNodes.count) nodes"
    }

    private func redactedEmail(_ account: ClaudeManagedAccount) -> String {
        PersonalInfoRedactor.redactEmail(account.email, isEnabled: self.settings.hidePersonalInfo)
    }

    // MARK: - Actions

    private func reloadAll() async {
        self.canImportFromCCSwitcher = ClaudeAccountService.ccSwitcherDataLooksPresent()
        await self.reloadAccounts()
        await self.refreshClashStatus()
    }

    private func reloadAccounts() async {
        do {
            let set = try await self.service.currentSet()
            self.accounts = set.accounts
            self.clashSettings = set.clash
            self.clashSocketPathDraft = set.clash.socketPath
            self.clashGroupDraft = set.clash.defaultGroup
            var backedUp: Set<UUID> = []
            for account in set.accounts where await self.service.hasBackup(accountID: account.id) {
                backedUp.insert(account.id)
            }
            self.backedUpAccountIDs = backedUp
        } catch {
            self.showNotice("Could not load accounts: \(error.localizedDescription)", isError: true)
        }
    }

    private func refreshClashStatus() async {
        let client = ClashVergeClient(socketPath: self.clashSettings.socketPath)
        do {
            let status = try await client.groupStatus(group: self.clashSettings.defaultGroup)
            self.clashNodes = status.all
            self.clashCurrentNode = status.now
            self.clashUnreachableDetail = nil
        } catch {
            self.clashNodes = []
            self.clashCurrentNode = nil
            self.clashUnreachableDetail = error.localizedDescription
        }
    }

    private func captureCurrentAccount() async {
        await self.runBusy {
            let account = try await self.service.captureCurrentAccount()
            self.showNotice("Captured \(account.displayTitle).", isError: false)
        }
    }

    private func importFromCCSwitcher() async {
        await self.runBusy {
            let summary = try await self.service.importFromCCSwitcher()
            var text = "Imported \(summary.imported) · skipped \(summary.skipped)"
            if summary.missingBackup > 0 {
                text += " · \(summary.missingBackup) without backup (capture them after signing in)"
            }
            if summary.keychainDenied {
                text += " · keychain access denied, credentials not imported — retry and click Allow"
            }
            self.showNotice(text, isError: summary.keychainDenied)
        }
    }

    private func switchTo(_ account: ClaudeManagedAccount) async {
        await self.runBusy {
            try await self.service.switchTo(accountID: account.id)
            self.showNotice("Switched to \(account.displayTitle).", isError: false)
            await self.refreshClaude()
        }
        await self.refreshClashStatus()
    }

    private func removeAccount(_ account: ClaudeManagedAccount) async {
        await self.runBusy {
            try await self.service.removeAccount(accountID: account.id)
            self.aliasDrafts.removeValue(forKey: account.id)
        }
    }

    private func commitAlias(_ account: ClaudeManagedAccount) async {
        guard let draft = self.aliasDrafts[account.id] else { return }
        do {
            try await self.service.setCustomLabel(accountID: account.id, label: draft)
            await self.reloadAccounts()
        } catch {
            self.showNotice(error.localizedDescription, isError: true)
        }
    }

    private func setClashBinding(_ account: ClaudeManagedAccount, node: String) async {
        do {
            if node == Self.noProxySyncTag {
                try await self.service.setClashBinding(accountID: account.id, group: nil, node: nil)
            } else {
                try await self.service.setClashBinding(
                    accountID: account.id,
                    group: self.clashSettings.defaultGroup,
                    node: node)
            }
            await self.reloadAccounts()
        } catch {
            self.showNotice(error.localizedDescription, isError: true)
        }
    }

    private func commitClashSettings() async {
        let socketPath = self.clashSocketPathDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let group = self.clashGroupDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let settings = ClashConnectionSettings(
            socketPath: socketPath.isEmpty ? ClashConnectionSettings.defaultSocketPath : socketPath,
            defaultGroup: group.isEmpty ? ClashConnectionSettings.defaultGroupName : group)
        do {
            try await self.service.updateClashSettings(settings)
            self.clashSettings = settings
            await self.refreshClashStatus()
        } catch {
            self.showNotice(error.localizedDescription, isError: true)
        }
    }

    private func runBusy(_ operation: () async throws -> Void) async {
        self.isBusy = true
        defer { self.isBusy = false }
        self.notice = nil
        do {
            try await operation()
        } catch {
            self.showNotice(error.localizedDescription, isError: true)
        }
        await self.reloadAccounts()
    }

    private func showNotice(_ text: String, isError: Bool) {
        self.notice = text
        self.noticeIsError = isError
    }
}
