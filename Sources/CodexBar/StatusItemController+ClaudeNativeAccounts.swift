import AppKit
import CodexBarCore

/// Segmented native Claude account switcher in the Claude menu (design v1.8):
/// one button per account (alias, active highlighted), click switches accounts.
/// Design: `docs/claude-native-multi-account-clash.md` (PAGE_MENU_CLAUDE, REQ-006).
final class ClaudeNativeAccountSwitcherView: NSView {
    struct Segment {
        let accountID: UUID
        let title: String
        let isActive: Bool
        let canSwitch: Bool
    }

    private let segments: [Segment]
    private let onSelect: (UUID) -> Void
    private var buttons: [NSButton] = []
    private let preferredSize: NSSize
    private let rowSpacing: CGFloat = 4
    private let rowHeight: CGFloat = 26
    private let selectedBackground = NSColor.controlAccentColor.cgColor
    private let unselectedBackground = NSColor.clear.cgColor
    private let selectedTextColor = NSColor.white
    private let unselectedTextColor = NSColor.secondaryLabelColor

    init(
        segments: [Segment],
        width: CGFloat,
        onSelect: @escaping (UUID) -> Void)
    {
        self.segments = segments
        self.onSelect = onSelect
        let useTwoRows = segments.count > 3
        let rows = useTwoRows ? 2 : 1
        let height = self.rowHeight * CGFloat(rows) + (useTwoRows ? self.rowSpacing : 0)
        self.preferredSize = NSSize(width: width, height: height)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        self.wantsLayer = true
        self.buildButtons(useTwoRows: useTwoRows)
        self.updateButtonStyles()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        self.preferredSize
    }

    override var fittingSize: NSSize {
        self.preferredSize
    }

    private func buildButtons(useTwoRows: Bool) {
        let perRow = useTwoRows ? Int(ceil(Double(self.segments.count) / 2.0)) : self.segments.count
        let rows: [[Segment]] = {
            if !useTwoRows { return [self.segments] }
            let first = Array(self.segments.prefix(perRow))
            let second = Array(self.segments.dropFirst(perRow))
            return [first, second]
        }()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = self.rowSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false

        var globalIndex = 0
        for rowSegments in rows {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.distribution = .fillEqually
            row.spacing = self.rowSpacing
            row.translatesAutoresizingMaskIntoConstraints = false

            for segment in rowSegments {
                let button = PaddedToggleButton(
                    title: segment.title,
                    target: self,
                    action: #selector(self.handleSelect))
                button.tag = globalIndex
                button.toolTip = segment.canSwitch || segment.isActive
                    ? segment.title
                    : "\(segment.title) — capture this account before switching"
                button.isBordered = false
                button.setButtonType(.toggle)
                button.controlSize = .small
                button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                button.cell?.lineBreakMode = segment.title.contains("@") ? .byTruncatingMiddle : .byTruncatingTail
                button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                button.wantsLayer = true
                button.layer?.cornerRadius = 6
                // The active segment stays enabled: a disabled NSButton dims its title,
                // washing out the accent highlight (handleSelect ignores active clicks).
                button.isEnabled = segment.isActive || segment.canSwitch
                row.addArrangedSubview(button)
                self.buttons.append(button)
                globalIndex += 1
            }

            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        self.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: self.topAnchor),
            stack.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            stack.heightAnchor.constraint(equalToConstant: self.rowHeight * CGFloat(rows.count) +
                (rows.count > 1 ? self.rowSpacing : 0)),
        ])
    }

    private func updateButtonStyles() {
        for (index, button) in self.buttons.enumerated() {
            let segment = self.segments[index]
            button.state = segment.isActive ? .on : .off
            button.layer?.backgroundColor = segment.isActive ? self.selectedBackground : self.unselectedBackground
            button.contentTintColor = segment.isActive ? self.selectedTextColor : self.unselectedTextColor
            button.alphaValue = segment.canSwitch || segment.isActive ? 1.0 : 0.5
        }
    }

    @objc private func handleSelect(_ sender: NSButton) {
        guard self.segments.indices.contains(sender.tag) else { return }
        let segment = self.segments[sender.tag]
        guard segment.canSwitch, !segment.isActive else {
            self.updateButtonStyles()
            return
        }
        self.onSelect(segment.accountID)
    }

    #if DEBUG
    func _test_buttonTitles() -> [String] {
        self.buttons.map(\.title)
    }

    func _test_activeTitle() -> String? {
        self.segments.first(where: \.isActive)?.title
    }

    func _test_buttonEnabledFlags() -> [Bool] {
        self.buttons.map(\.isEnabled)
    }
    #endif
}

extension StatusItemController {
    #if DEBUG
    /// Test seam: menu building is synchronous, so tests inject an account set
    /// instead of seeding the real Application Support store.
    nonisolated(unsafe) static var claudeNativeAccountSetOverrideForTesting: ClaudeManagedAccountSet?
    #endif

    func addClaudeNativeAccountSwitcherIfNeeded(
        to menu: NSMenu,
        provider: UsageProvider,
        width: CGFloat,
        captureMenu: NSMenu? = nil)
    {
        guard provider == .claude else { return }
        // ADR-005: while the claude-swap adapter is enabled it owns Claude multi-account UI.
        guard !self.settings.claudeSwapEnabled else { return }
        guard let set = self.claudeNativeAccountSet(), set.accounts.count >= 2 else { return }

        let backups = KeychainClaudeCredentialBackupStore()
        let segments = set.accounts.map { account in
            ClaudeNativeAccountSwitcherView.Segment(
                accountID: account.id,
                title: self.claudeNativeAccountTitle(account),
                isActive: account.isActive,
                canSwitch: backups.load(accountID: account.id) != nil)
        }
        // Rows may be built into a detached scratch menu; interaction closures must
        // capture the live menu they will end up serving.
        let interactionMenu = captureMenu ?? menu
        let view = ClaudeNativeAccountSwitcherView(
            segments: segments,
            width: width,
            onSelect: { [weak self, weak interactionMenu] accountID in
                guard let self else { return }
                self.advanceMenuInteraction(for: interactionMenu)
                self.switchClaudeNativeAccount(accountID: accountID, menu: interactionMenu)
            })
        let item = NSMenuItem()
        item.view = view
        item.isEnabled = false
        menu.addItem(item)
        menu.addItem(.separator())
    }

    private func claudeNativeAccountSet() -> ClaudeManagedAccountSet? {
        #if DEBUG
        if let override = Self.claudeNativeAccountSetOverrideForTesting {
            return override
        }
        #endif
        return try? FileClaudeManagedAccountStore().load()
    }

    private func claudeNativeAccountTitle(_ account: ClaudeManagedAccount) -> String {
        var title = account.customLabel?.isEmpty == false
            ? account.displayTitle
            : PersonalInfoRedactor.redactEmail(account.email, isEnabled: self.settings.hidePersonalInfo)
        if title.isEmpty {
            title = "Account"
        }
        return title
    }

    private func switchClaudeNativeAccount(accountID: UUID, menu: NSMenu?) {
        Task { @MainActor [weak self, weak menu] in
            guard let self else { return }
            do {
                try await ClaudeAccountServiceHolder.shared.switchTo(accountID: accountID)
                await ProviderInteractionContext.$current.withValue(.userInitiated) {
                    await self.store.refreshProvider(.claude, allowDisabled: true)
                }
                if let menu {
                    self.deferSwitcherMenuRebuildIfStillVisible(menu, provider: .claude)
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
