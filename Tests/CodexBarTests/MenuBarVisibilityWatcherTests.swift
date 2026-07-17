import CoreGraphics
import Foundation
import Testing
@testable import CodexBar

struct MenuBarVisibilityWatcherTests {
    @Test
    func does_not_flag_intentionally_hidden_status_item() {
        let snapshot = StatusItemVisibilitySnapshot(
            isVisible: false,
            hasButton: true,
            hasWindow: false,
            hasScreen: false,
            buttonWidth: 0)

        #expect(!MenuBarVisibilityWatcher.isBlockedSnapshot(snapshot: snapshot))
    }

    @Test
    func flags_visible_item_without_attached_window() {
        let snapshot = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: false,
            hasScreen: false,
            buttonWidth: 18)

        #expect(MenuBarVisibilityWatcher.isBlockedSnapshot(snapshot: snapshot))
    }

    @Test
    func flags_visible_item_without_button() {
        let snapshot = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: false,
            hasWindow: false,
            hasScreen: false,
            buttonWidth: 0)

        #expect(MenuBarVisibilityWatcher.isBlockedSnapshot(snapshot: snapshot))
    }

    @Test
    func flags_visible_item_with_zero_width() {
        let snapshot = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: true,
            hasScreen: true,
            buttonWidth: 0)

        #expect(MenuBarVisibilityWatcher.isBlockedSnapshot(snapshot: snapshot))
    }

    @Test
    func allows_visible_item_attached_to_a_screen_with_width() {
        let snapshot = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: true,
            hasScreen: true,
            buttonWidth: 18)

        #expect(!MenuBarVisibilityWatcher.isBlockedSnapshot(snapshot: snapshot))
    }

    @Test
    func window_probe_matches_autosave_name_and_reports_display_bounds() {
        let snapshots = MenuBarStatusItemWindowProbe.snapshots(
            matching: ["codexbar-merged"],
            windowInfo: [[
                kCGWindowName as String: "codexbar-merged",
                kCGWindowOwnerName as String: "Control Center",
                kCGWindowIsOnscreen as String: true,
                kCGWindowBounds as String: [
                    "X": 1680,
                    "Y": 0,
                    "Width": 70,
                    "Height": 24,
                ],
            ]],
            displayBounds: [CGRect(x: 0, y: 0, width: 2056, height: 1329)])

        #expect(snapshots.count == 1)
        #expect(snapshots.first?.name == "codexbar-merged")
        #expect(snapshots.first?.ownerName == "Control Center")
        #expect(snapshots.first?.isOnscreen == true)
        #expect(snapshots.first?.isWithinDisplayBounds == true)
    }

    @Test
    func window_probe_detects_offscreen_status_item_by_bounds() {
        let snapshots = MenuBarStatusItemWindowProbe.snapshots(
            matching: ["codexbar-merged"],
            windowInfo: [[
                kCGWindowName as String: "codexbar-merged",
                kCGWindowOwnerName as String: "Control Center",
                kCGWindowIsOnscreen as String: true,
                kCGWindowBounds as String: [
                    "X": 2023,
                    "Y": 0,
                    "Width": 71,
                    "Height": 24,
                ],
            ]],
            displayBounds: [CGRect(x: 0, y: 0, width: 2056, height: 1329)])

        #expect(snapshots.count == 1)
        #expect(snapshots.first?.isOnscreen == true)
        #expect(snapshots.first?.isWithinDisplayBounds == false)
    }

    @Test
    func window_probe_identifies_Tahoe_Control_Center_blocked_proxy_geometry() {
        let snapshot = MenuBarStatusItemWindowSnapshot(
            name: "codexbar-merged",
            ownerName: "Control Center",
            bounds: CGRect(x: 0, y: -22, width: 76, height: 22),
            isOnscreen: true,
            displayBounds: nil)

        #expect(snapshot.isTahoeBlockedProxy)
    }

    @Test
    func window_probe_does_not_classify_generic_offscreen_manager_placement_as_Tahoe_proxy() {
        let snapshot = MenuBarStatusItemWindowSnapshot(
            name: "codexbar-merged",
            ownerName: "Control Center",
            bounds: CGRect(x: 2023, y: 0, width: 71, height: 24),
            isOnscreen: true,
            displayBounds: nil)

        #expect(!snapshot.isTahoeBlockedProxy)
    }

    @Test
    func window_probe_does_not_classify_stale_hidden_Control_Center_record_as_Tahoe_proxy() {
        let snapshot = MenuBarStatusItemWindowSnapshot(
            name: "codexbar-merged",
            ownerName: "Control Center",
            bounds: CGRect(x: 0, y: -22, width: 76, height: 22),
            isOnscreen: false,
            displayBounds: nil)

        #expect(!snapshot.isTahoeBlockedProxy)
    }

    @Test
    func allows_visible_item_attached_to_a_detached_screen() {
        let snapshot = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: true,
            hasScreen: true,
            isOnCurrentScreen: false,
            buttonWidth: 18)

        #expect(!MenuBarVisibilityWatcher.isBlockedSnapshot(snapshot: snapshot))
    }

    @Test
    func classifies_detached_live_item_as_displaced_but_not_blocked() {
        let snapshot = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: true,
            hasScreen: false,
            isOnCurrentScreen: false,
            buttonWidth: 18)

        #expect(!MenuBarVisibilityWatcher.isBlockedSnapshot(snapshot: snapshot))
        #expect(MenuBarVisibilityWatcher.isDisplacedSnapshot(snapshot: snapshot))
    }

    @Test
    func classifies_stale_screen_live_item_as_displaced_but_not_blocked() {
        let snapshot = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: true,
            hasScreen: true,
            isOnCurrentScreen: false,
            buttonWidth: 18)

        #expect(!MenuBarVisibilityWatcher.isBlockedSnapshot(snapshot: snapshot))
        #expect(MenuBarVisibilityWatcher.isDisplacedSnapshot(snapshot: snapshot))
    }

    @Test
    func guidance_shows_once_then_repeats_after_a_day() throws {
        let defaults = try #require(UserDefaults(suiteName: "MenuBarVisibilityWatcherTests"))
        defaults.removePersistentDomain(forName: "MenuBarVisibilityWatcherTests")
        let now = Date(timeIntervalSince1970: 1000)

        #expect(MenuBarVisibilityWatcher.shouldShowGuidance(defaults: defaults, now: now))

        MenuBarVisibilityWatcher.markGuidanceShown(defaults: defaults, now: now)

        #expect(!MenuBarVisibilityWatcher.shouldShowGuidance(
            defaults: defaults,
            now: now.addingTimeInterval(MenuBarVisibilityWatcher.guidanceRepeatInterval - 1)))
        #expect(MenuBarVisibilityWatcher.shouldShowGuidance(
            defaults: defaults,
            now: now.addingTimeInterval(MenuBarVisibilityWatcher.guidanceRepeatInterval)))
    }

    @Test
    func startup_recovery_triggers_for_blocked_visible_snapshot() {
        let launchedAt = Date(timeIntervalSince1970: 1000)
        let blocked = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: false,
            hasScreen: false,
            buttonWidth: 18)

        #expect(MenuBarVisibilityWatcher.shouldAttemptStartupRecovery(
            appLaunchedAt: launchedAt,
            now: launchedAt.addingTimeInterval(2),
            snapshots: [blocked]))
    }

    @Test
    func startup_recovery_retries_detached_Tahoe_proxy_corroborated_by_Control_Center_geometry() {
        let launchedAt = Date(timeIntervalSince1970: 1000)
        let detachedProxy = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: true,
            hasScreen: false,
            isOnCurrentScreen: false,
            buttonWidth: 76)
        let blockedWindow = MenuBarStatusItemWindowSnapshot(
            name: "codexbar-merged",
            ownerName: "Control Center",
            bounds: CGRect(x: 0, y: -22, width: 76, height: 22),
            isOnscreen: true,
            displayBounds: nil)

        #expect(!MenuBarVisibilityWatcher.isBlockedSnapshot(snapshot: detachedProxy))
        #expect(MenuBarVisibilityWatcher.shouldAttemptStartupRecovery(
            appLaunchedAt: launchedAt,
            now: launchedAt.addingTimeInterval(2),
            snapshots: [detachedProxy],
            windowSnapshots: [blockedWindow],
            detectTahoeBlockedStatusItem: true))
    }

    @Test
    func startup_recovery_retries_expected_hidden_Tahoe_item_with_enabled_default_and_no_window() {
        let launchedAt = Date(timeIntervalSince1970: 1000)
        let hidden = StatusItemVisibilitySnapshot(
            isVisible: false,
            hasButton: true,
            hasWindow: false,
            hasScreen: false,
            buttonWidth: 76)
        let evidence = StatusItemStartupVisibilityEvidence(
            autosaveName: "codexbar-merged",
            expectsVisibility: true,
            visibilityDefault: true,
            snapshot: hidden)

        #expect(MenuBarVisibilityWatcher.shouldAttemptStartupRecovery(
            appLaunchedAt: launchedAt,
            now: launchedAt.addingTimeInterval(2),
            snapshots: [hidden],
            evidence: [evidence],
            detectTahoeBlockedStatusItem: true))
    }

    @Test
    func startup_recovery_ignores_hidden_Tahoe_item_without_app_and_defaults_visibility_agreement() {
        let launchedAt = Date(timeIntervalSince1970: 1000)
        let hidden = StatusItemVisibilitySnapshot(
            isVisible: false,
            hasButton: true,
            hasWindow: false,
            hasScreen: false,
            buttonWidth: 76)
        let intentionallyHidden = StatusItemStartupVisibilityEvidence(
            autosaveName: "codexbar-merged",
            expectsVisibility: false,
            visibilityDefault: true,
            snapshot: hidden)
        let disabledByUser = StatusItemStartupVisibilityEvidence(
            autosaveName: "codexbar-merged",
            expectsVisibility: true,
            visibilityDefault: false,
            snapshot: hidden)
        let unknownDefault = StatusItemStartupVisibilityEvidence(
            autosaveName: "codexbar-merged",
            expectsVisibility: true,
            visibilityDefault: nil,
            snapshot: hidden)

        for evidence in [intentionallyHidden, disabledByUser, unknownDefault] {
            #expect(!MenuBarVisibilityWatcher.shouldAttemptStartupRecovery(
                appLaunchedAt: launchedAt,
                now: launchedAt.addingTimeInterval(2),
                snapshots: [hidden],
                evidence: [evidence],
                detectTahoeBlockedStatusItem: true))
        }
    }

    @Test
    func startup_recovery_ignores_hidden_item_when_matching_window_still_exists() {
        let launchedAt = Date(timeIntervalSince1970: 1000)
        let hidden = StatusItemVisibilitySnapshot(
            isVisible: false,
            hasButton: true,
            hasWindow: false,
            hasScreen: false,
            buttonWidth: 76)
        let evidence = StatusItemStartupVisibilityEvidence(
            autosaveName: "codexbar-merged",
            expectsVisibility: true,
            visibilityDefault: true,
            snapshot: hidden)
        let existingWindow = MenuBarStatusItemWindowSnapshot(
            name: "codexbar-merged",
            ownerName: "Control Center",
            bounds: CGRect(x: 1500, y: 0, width: 76, height: 24),
            isOnscreen: true,
            displayBounds: CGRect(x: 0, y: 0, width: 2056, height: 1329))

        #expect(!MenuBarVisibilityWatcher.shouldAttemptStartupRecovery(
            appLaunchedAt: launchedAt,
            now: launchedAt.addingTimeInterval(2),
            snapshots: [hidden],
            evidence: [evidence],
            windowSnapshots: [existingWindow],
            detectTahoeBlockedStatusItem: true))
    }

    @Test
    func startup_recovery_ignores_stale_hidden_matching_window_record() {
        let launchedAt = Date(timeIntervalSince1970: 1000)
        let hidden = StatusItemVisibilitySnapshot(
            isVisible: false,
            hasButton: true,
            hasWindow: false,
            hasScreen: false,
            buttonWidth: 76)
        let evidence = StatusItemStartupVisibilityEvidence(
            autosaveName: "codexbar-merged",
            expectsVisibility: true,
            visibilityDefault: true,
            snapshot: hidden)
        let staleWindow = MenuBarStatusItemWindowSnapshot(
            name: "codexbar-merged",
            ownerName: "Control Center",
            bounds: CGRect(x: 1500, y: 0, width: 76, height: 24),
            isOnscreen: false,
            displayBounds: CGRect(x: 0, y: 0, width: 2056, height: 1329))

        #expect(MenuBarVisibilityWatcher.shouldAttemptStartupRecovery(
            appLaunchedAt: launchedAt,
            now: launchedAt.addingTimeInterval(2),
            snapshots: [hidden],
            evidence: [evidence],
            windowSnapshots: [staleWindow],
            detectTahoeBlockedStatusItem: true))
    }

    @Test
    func startup_recovery_keeps_hidden_no_window_detection_Tahoe_only() {
        let launchedAt = Date(timeIntervalSince1970: 1000)
        let hidden = StatusItemVisibilitySnapshot(
            isVisible: false,
            hasButton: true,
            hasWindow: false,
            hasScreen: false,
            buttonWidth: 76)
        let evidence = StatusItemStartupVisibilityEvidence(
            autosaveName: "codexbar-merged",
            expectsVisibility: true,
            visibilityDefault: true,
            snapshot: hidden)

        #expect(!MenuBarVisibilityWatcher.shouldAttemptStartupRecovery(
            appLaunchedAt: launchedAt,
            now: launchedAt.addingTimeInterval(2),
            snapshots: [hidden],
            evidence: [evidence]))
    }

    @Test
    func startup_recovery_ignores_detached_live_item_without_Tahoe_proxy_corroboration() {
        let launchedAt = Date(timeIntervalSince1970: 1000)
        let managed = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: true,
            hasScreen: false,
            isOnCurrentScreen: false,
            buttonWidth: 18)

        #expect(!MenuBarVisibilityWatcher.shouldAttemptStartupRecovery(
            appLaunchedAt: launchedAt,
            now: launchedAt.addingTimeInterval(2),
            snapshots: [managed],
            detectTahoeBlockedStatusItem: true))
    }

    @Test
    func startup_recovery_ignores_live_item_attached_to_a_stale_screen() {
        let launchedAt = Date(timeIntervalSince1970: 1000)
        let managed = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: true,
            hasScreen: true,
            isOnCurrentScreen: false,
            buttonWidth: 18)

        #expect(!MenuBarVisibilityWatcher.shouldAttemptStartupRecovery(
            appLaunchedAt: launchedAt,
            now: launchedAt.addingTimeInterval(2),
            snapshots: [managed]))
    }

    @Test
    func startup_recovery_triggers_when_one_split_status_item_is_blocked() {
        let launchedAt = Date(timeIntervalSince1970: 1000)
        let healthy = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: true,
            hasScreen: true,
            buttonWidth: 18)
        let blocked = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: false,
            hasScreen: false,
            buttonWidth: 18)

        #expect(MenuBarVisibilityWatcher.shouldAttemptStartupRecovery(
            appLaunchedAt: launchedAt,
            now: launchedAt.addingTimeInterval(2),
            snapshots: [healthy, blocked]))
    }

    @Test
    func startup_recovery_ignores_stale_checks() {
        let launchedAt = Date(timeIntervalSince1970: 1000)
        let blocked = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: false,
            hasScreen: false,
            buttonWidth: 18)

        #expect(!MenuBarVisibilityWatcher.shouldAttemptStartupRecovery(
            appLaunchedAt: launchedAt,
            now: launchedAt.addingTimeInterval(MenuBarVisibilityWatcher.startupFreshnessInterval + 1),
            snapshots: [blocked]))
    }

    @Test
    func startup_recovery_ignores_healthy_visible_snapshot() {
        let launchedAt = Date(timeIntervalSince1970: 1000)
        let healthy = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: true,
            hasScreen: true,
            buttonWidth: 18)

        #expect(!MenuBarVisibilityWatcher.shouldAttemptStartupRecovery(
            appLaunchedAt: launchedAt,
            now: launchedAt.addingTimeInterval(2),
            snapshots: [healthy]))
    }

    @Test
    func screen_change_placement_refresh_ignores_display_removal_with_healthy_status_item() {
        let healthy = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: true,
            hasScreen: true,
            buttonWidth: 18)

        #expect(!MenuBarVisibilityWatcher.shouldRefreshScreenChangePlacement(
            previousScreenCount: 2,
            currentScreenCount: 1,
            snapshots: [healthy]))
    }

    @Test
    func screen_change_placement_refresh_ignores_display_removal_when_no_status_item_is_visible() {
        let hidden = StatusItemVisibilitySnapshot(
            isVisible: false,
            hasButton: true,
            hasWindow: true,
            hasScreen: true,
            buttonWidth: 18)

        #expect(!MenuBarVisibilityWatcher.shouldRefreshScreenChangePlacement(
            previousScreenCount: 2,
            currentScreenCount: 1,
            snapshots: [hidden]))
    }

    @Test
    func screen_change_recovery_triggers_for_blocked_status_item_without_display_count_change() {
        let blocked = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: false,
            hasScreen: false,
            buttonWidth: 18)

        #expect(MenuBarVisibilityWatcher.shouldAttemptScreenChangeRecovery(snapshots: [blocked]))
    }

    @Test
    func screen_change_placement_refresh_triggers_for_detached_live_item_after_display_removal() {
        let displaced = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: true,
            hasScreen: false,
            isOnCurrentScreen: false,
            buttonWidth: 18)

        #expect(MenuBarVisibilityWatcher.shouldRefreshScreenChangePlacement(
            previousScreenCount: 2,
            currentScreenCount: 1,
            snapshots: [displaced]))
    }

    @Test
    func screen_change_placement_refresh_triggers_for_stale_screen_live_item_after_display_removal() {
        let displaced = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: true,
            hasScreen: true,
            isOnCurrentScreen: false,
            buttonWidth: 18)

        #expect(MenuBarVisibilityWatcher.shouldRefreshScreenChangePlacement(
            previousScreenCount: 2,
            currentScreenCount: 1,
            snapshots: [displaced]))
    }

    @Test
    func screen_change_placement_refresh_ignores_healthy_item_when_display_count_does_not_shrink() {
        let healthy = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: true,
            hasScreen: true,
            buttonWidth: 18)

        #expect(!MenuBarVisibilityWatcher.shouldRefreshScreenChangePlacement(
            previousScreenCount: 1,
            currentScreenCount: 2,
            snapshots: [healthy]))
    }

    @Test
    func screen_change_placement_refresh_triggers_for_displaced_live_item_when_display_count_is_unchanged() {
        let displaced = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: true,
            hasScreen: true,
            isOnCurrentScreen: false,
            buttonWidth: 18)

        #expect(MenuBarVisibilityWatcher.shouldRefreshScreenChangePlacement(
            previousScreenCount: 2,
            currentScreenCount: 2,
            snapshots: [displaced]))
    }

    @Test
    func manager_parked_item_with_live_window_is_not_blocked() {
        // A menu bar manager parks items off the active screen with the window intact.
        // hasAnyBlockedVisibleSnapshot must return false so verifyScreenChangeRecoveryIfNeeded
        // does not trigger repeated recreation that corrupts Control Center.
        let managed = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: true,
            hasScreen: false,
            isOnCurrentScreen: false,
            buttonWidth: 18)

        #expect(!MenuBarVisibilityWatcher.hasAnyBlockedVisibleSnapshot([managed]))
        #expect(MenuBarVisibilityWatcher.hasAnyDisplacedVisibleSnapshot([managed]))
    }

    @Test
    func manager_parked_item_with_live_window_on_stale_screen_is_not_blocked() {
        let managed = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: true,
            hasScreen: true,
            isOnCurrentScreen: false,
            buttonWidth: 18)

        #expect(!MenuBarVisibilityWatcher.hasAnyBlockedVisibleSnapshot([managed]))
        #expect(MenuBarVisibilityWatcher.hasAnyDisplacedVisibleSnapshot([managed]))
    }

    @Test
    func item_without_window_is_blocked_regardless_of_screen_state() {
        // A missing window cannot be caused by a manager parking the item; it signals
        // a genuine system block and must trigger recovery.
        let blocked = StatusItemVisibilitySnapshot(
            isVisible: true,
            hasButton: true,
            hasWindow: false,
            hasScreen: false,
            isOnCurrentScreen: false,
            buttonWidth: 18)

        #expect(MenuBarVisibilityWatcher.hasAnyBlockedVisibleSnapshot([blocked]))
        #expect(!MenuBarVisibilityWatcher.hasAnyDisplacedVisibleSnapshot([blocked]))
    }
}
