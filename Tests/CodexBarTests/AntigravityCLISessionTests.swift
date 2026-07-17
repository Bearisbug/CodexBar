#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Foundation
import Testing
@testable import CodexBarCore

private final class FakeAntigravityProcessHandle: AntigravityCLIProcessHandle, @unchecked Sendable {
    private let lock = NSLock()
    let pid: pid_t
    var descendants: [pid_t]
    private var running: Bool
    private let terminateRootStopsProcess: Bool
    private var assignedProcessGroup: pid_t?
    private var events: [String] = []
    private var drainOutputChunks: [Data] = []

    init(pid: pid_t, running: Bool = true, descendants: [pid_t] = [], terminateRootStopsProcess: Bool = true) {
        self.pid = pid
        self.running = running
        self.descendants = descendants
        self.terminateRootStopsProcess = terminateRootStopsProcess
    }

    var isRunning: Bool {
        self.lock.lock()
        let value = self.running
        self.events.append("isRunning:\(value)")
        self.lock.unlock()
        return value
    }

    var processGroup: pid_t? {
        self.lock.lock()
        let value = self.assignedProcessGroup
        self.lock.unlock()
        return value
    }

    func assignProcessGroup() -> pid_t? {
        self.lock.lock()
        self.assignedProcessGroup = self.pid
        self.events.append("assignProcessGroup")
        self.lock.unlock()
        return self.pid
    }

    func sendExit() throws {
        self.append("sendExit")
    }

    func closePTY() {
        self.append("closePTY")
    }

    func terminateRoot() {
        self.lock.lock()
        if self.terminateRootStopsProcess {
            self.running = false
        }
        self.events.append("terminateRoot")
        self.lock.unlock()
    }

    func killRoot() {
        self.lock.lock()
        self.running = false
        self.events.append("killRoot")
        self.lock.unlock()
    }

    func descendantPIDs() -> [pid_t] {
        self.lock.lock()
        let value = self.descendants
        self.events.append("descendantPIDs")
        self.lock.unlock()
        return value
    }

    func terminateTree(signal: Int32, knownDescendants _: [pid_t]) {
        self.lock.lock()
        if signal == SIGKILL {
            self.running = false
        }
        self.events.append("terminateTree:\(signal)")
        self.lock.unlock()
    }

    func killDescendants(_ descendants: [pid_t]) {
        self.append("killDescendants:\(descendants.map(String.init).joined(separator: ","))")
    }

    func drainOutput() -> Data {
        self.lock.lock()
        self.events.append("drainOutput")
        let output = self.drainOutputChunks.isEmpty ? Data() : self.drainOutputChunks.removeFirst()
        self.lock.unlock()
        return output
    }

    func enqueueDrainOutput(_ output: Data) {
        self.lock.lock()
        self.drainOutputChunks.append(output)
        self.lock.unlock()
    }

    func snapshotEvents() -> [String] {
        self.lock.lock()
        let value = self.events
        self.lock.unlock()
        return value
    }

    private func append(_ event: String) {
        self.lock.lock()
        self.events.append(event)
        self.lock.unlock()
    }
}

private final class FakeAntigravityProcessLauncher: AntigravityCLIProcessLaunching, @unchecked Sendable {
    private let lock = NSLock()
    private var nextPID: pid_t
    private var launchError: Error?
    private var launchedBinaries: [String] = []
    private var terminateRootStopsProcess = true
    private var handles: [FakeAntigravityProcessHandle] = []

    init(nextPID: pid_t = 1) {
        self.nextPID = nextPID
    }

    func launch(binary: String) throws -> any AntigravityCLIProcessHandle {
        self.lock.lock()
        defer { self.lock.unlock() }
        if let launchError {
            throw launchError
        }
        let handle = FakeAntigravityProcessHandle(
            pid: self.nextPID,
            descendants: [self.nextPID + 100],
            terminateRootStopsProcess: self.terminateRootStopsProcess)
        self.nextPID += 1
        self.launchedBinaries.append(binary)
        self.handles.append(handle)
        return handle
    }

    func setLaunchError(_ error: Error?) {
        self.lock.lock()
        self.launchError = error
        self.lock.unlock()
    }

    func setTerminateRootStopsProcess(_ value: Bool) {
        self.lock.lock()
        self.terminateRootStopsProcess = value
        self.lock.unlock()
    }

    func launchedBinarySnapshot() -> [String] {
        self.lock.lock()
        let value = self.launchedBinaries
        self.lock.unlock()
        return value
    }

    func handleSnapshot() -> [FakeAntigravityProcessHandle] {
        self.lock.lock()
        let value = self.handles
        self.lock.unlock()
        return value
    }
}

private final class FakeAntigravityIdentityProvider: AntigravityCLIProcessIdentityProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var identities: [pid_t: AntigravityCLIProcessIdentity] = [:]

    func setIdentity(pid: pid_t, executablePath: String, startEpoch: TimeInterval) {
        self.lock.lock()
        self.identities[pid] = AntigravityCLIProcessIdentity(executablePath: executablePath, startEpoch: startEpoch)
        self.lock.unlock()
    }

    func removeIdentity(pid: pid_t) {
        self.lock.lock()
        self.identities[pid] = nil
        self.lock.unlock()
    }

    func identity(for pid: pid_t) -> AntigravityCLIProcessIdentity? {
        self.lock.lock()
        let value = self.identities[pid]
        self.lock.unlock()
        return value
    }
}

private final class MemoryAntigravitySessionRecordStore: AntigravityCLISessionRecordStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [AntigravityCLISessionRecord]
    private let failSaves: Bool
    private var saves = 0
    private var removes = 0

    init(record: AntigravityCLISessionRecord? = nil, failSaves: Bool = false) {
        self.records = record.map { [$0] } ?? []
        self.failSaves = failSaves
    }

    func load() throws -> [AntigravityCLISessionRecord] {
        self.lock.lock()
        let value = self.records
        self.lock.unlock()
        return value
    }

    func save(_ record: AntigravityCLISessionRecord) throws {
        self.lock.lock()
        guard !self.failSaves else {
            self.lock.unlock()
            throw CocoaError(.fileWriteNoPermission)
        }
        self.records.removeAll { existing in
            if let existingOwnerPID = existing.ownerPID,
               let recordOwnerPID = record.ownerPID,
               let existingOwnerPath = existing.ownerExecutablePath,
               let recordOwnerPath = record.ownerExecutablePath,
               let existingOwnerStart = existing.ownerStartEpoch,
               let recordOwnerStart = record.ownerStartEpoch
            {
                return existingOwnerPID == recordOwnerPID &&
                    existingOwnerPath == recordOwnerPath &&
                    abs(existingOwnerStart - recordOwnerStart) < 0.001
            }
            return existing.pid == record.pid &&
                existing.executablePath == record.executablePath &&
                abs(existing.startEpoch - record.startEpoch) < 0.001
        }
        self.records.append(record)
        self.saves += 1
        self.lock.unlock()
    }

    func remove(_ record: AntigravityCLISessionRecord) throws {
        self.lock.lock()
        self.records.removeAll {
            $0.pid == record.pid &&
                $0.executablePath == record.executablePath &&
                abs($0.startEpoch - record.startEpoch) < 0.001
        }
        self.removes += 1
        self.lock.unlock()
    }

    func snapshot() -> AntigravityCLISessionRecord? {
        self.lock.lock()
        let value = self.records.first
        self.lock.unlock()
        return value
    }

    func snapshots() -> [AntigravityCLISessionRecord] {
        self.lock.lock()
        let value = self.records
        self.lock.unlock()
        return value
    }

    var saveCount: Int {
        self.lock.lock()
        let value = self.saves
        self.lock.unlock()
        return value
    }

    var removeCount: Int {
        self.lock.lock()
        let value = self.removes
        self.lock.unlock()
        return value
    }
}

private final class MemoryAntigravitySessionLaunchLock: AntigravityCLISessionLaunchLocking, @unchecked Sendable {
    private let lock = NSLock()

    func withLock<T>(_ operation: () throws -> T) throws -> T {
        self.lock.lock()
        defer { self.lock.unlock() }
        return try operation()
    }
}

private struct FailingAntigravitySessionLaunchLock: AntigravityCLISessionLaunchLocking {
    func withLock<T>(_: () throws -> T) throws -> T {
        throw CocoaError(.fileWriteNoPermission)
    }
}

private final class AntigravitySessionTerminationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [(pid: pid_t, group: pid_t?, signal: Int32, descendants: [pid_t])] = []

    func append(pid: pid_t, group: pid_t?, signal: Int32, descendants: [pid_t]) {
        self.lock.lock()
        self.events.append((pid: pid, group: group, signal: signal, descendants: descendants))
        self.lock.unlock()
    }

    func snapshot() -> [(pid: pid_t, group: pid_t?, signal: Int32, descendants: [pid_t])] {
        self.lock.lock()
        let value = self.events
        self.lock.unlock()
        return value
    }
}

private final class AntigravityRegistryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var shouldRegister = true
    private var registered: [pid_t] = []
    private var unregistered: [pid_t] = []
    private var groups: [pid_t: pid_t?] = [:]

    func setShouldRegister(_ value: Bool) {
        self.lock.lock()
        self.shouldRegister = value
        self.lock.unlock()
    }

    func register(pid: pid_t, _: String) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard self.shouldRegister else { return false }
        self.registered.append(pid)
        return true
    }

    func update(pid: pid_t, group: pid_t?) {
        self.lock.lock()
        self.groups[pid] = group
        self.lock.unlock()
    }

    func unregister(pid: pid_t) {
        self.lock.lock()
        self.unregistered.append(pid)
        self.lock.unlock()
    }

    func registeredSnapshot() -> [pid_t] {
        self.lock.lock()
        let value = self.registered
        self.lock.unlock()
        return value
    }

    func unregisteredSnapshot() -> [pid_t] {
        self.lock.lock()
        let value = self.unregistered
        self.lock.unlock()
        return value
    }
}

private final class AntigravityLaunchReservationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var beginCount = 0
    private var endCount = 0

    func begin() -> Bool {
        self.lock.lock()
        self.beginCount += 1
        self.lock.unlock()
        return true
    }

    func end() {
        self.lock.lock()
        self.endCount += 1
        self.lock.unlock()
    }

    func counts() -> (begin: Int, end: Int) {
        self.lock.lock()
        let counts = (begin: self.beginCount, end: self.endCount)
        self.lock.unlock()
        return counts
    }
}

private final class AntigravityManualSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<Void, Error>] = []

    func sleep(_: UInt64) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.lock.lock()
            self.continuations.append(continuation)
            self.lock.unlock()
        }
    }

    func resumeAll() {
        self.lock.lock()
        let continuations = self.continuations
        self.continuations.removeAll()
        self.lock.unlock()

        for continuation in continuations {
            continuation.resume()
        }
    }

    func waitForSleeps(_ expectedCount: Int) async {
        for _ in 0..<200 {
            if self.pendingSleepCount >= expectedCount { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        Issue.record("Timed out waiting for \(expectedCount) sleep continuation(s)")
    }

    private var pendingSleepCount: Int {
        self.lock.lock()
        let count = self.continuations.count
        self.lock.unlock()
        return count
    }
}

struct AntigravityCLISessionTests {
    @Test
    func reuses_alive_process_for_same_binary() async throws {
        let fixture = self.makeFixture()
        fixture.identity.setIdentity(pid: 10, executablePath: "/bin/agy", startEpoch: 100)

        let firstPID = try await fixture.session.beginProbe(binary: "/bin/agy")
        await fixture.session.finishProbe(success: true, resetAfterFetch: false)
        let secondPID = try await fixture.session.beginProbe(binary: "/bin/agy")
        await fixture.session.finishProbe(success: true, resetAfterFetch: false)

        #expect(firstPID == 10)
        #expect(secondPID == 10)
        #expect(fixture.launcher.launchedBinarySnapshot() == ["/bin/agy"])
        #expect(fixture.launchReservations.counts().begin == 1)
        #expect(fixture.launchReservations.counts().end == 1)
    }

    @Test
    func relaunches_when_binary_changes() async throws {
        let fixture = self.makeFixture()
        fixture.identity.setIdentity(pid: 10, executablePath: "/bin/agy", startEpoch: 100)
        fixture.identity.setIdentity(pid: 11, executablePath: "/new/agy", startEpoch: 101)

        _ = try await fixture.session.beginProbe(binary: "/bin/agy")
        await fixture.session.finishProbe(success: true, resetAfterFetch: false)
        let secondPID = try await fixture.session.beginProbe(binary: "/new/agy")
        await fixture.session.finishProbe(success: true, resetAfterFetch: false)

        #expect(secondPID == 11)
        #expect(fixture.launcher.launchedBinarySnapshot() == ["/bin/agy", "/new/agy"])
        #expect(fixture.registry.unregisteredSnapshot() == [10])
    }

    @Test
    func replacement_launch_waits_for_in_progress_teardown() async throws {
        let fixture = self.makeFixture(
            manualSleep: true,
            terminationGracePeriod: 1,
            terminateRootStopsProcess: false)
        fixture.identity.setIdentity(pid: 10, executablePath: "/old/agy", startEpoch: 100)
        fixture.identity.setIdentity(pid: 11, executablePath: "/new/agy", startEpoch: 101)

        _ = try await fixture.session.beginProbe(binary: "/old/agy")
        await fixture.session.finishProbe(success: true, resetAfterFetch: false)

        let firstReplacement = Task {
            try await fixture.session.beginProbe(binary: "/new/agy")
        }
        // Two sleeps register here: the lingering idle-timer sleep (armed by the prior finishProbe;
        // the fake sleeper does not honor cancellation) and the teardown grace-period sleep. Wait for
        // both before resuming — waiting for only one lets resumeAll() fire before the grace sleep
        // parks, stranding it so teardown never completes and the suite hangs to the 120s timeout.
        await fixture.sleeper?.waitForSleeps(2)

        let secondReplacement = Task {
            try await fixture.session.beginProbe(binary: "/new/agy")
        }
        await Task.yield()
        #expect(fixture.launcher.launchedBinarySnapshot() == ["/old/agy"])

        fixture.launcher.handleSnapshot().first?.killRoot()
        fixture.sleeper?.resumeAll()
        let firstPID = try await firstReplacement.value
        let secondPID = try await secondReplacement.value
        await fixture.session.finishProbe(success: true, resetAfterFetch: false)
        await fixture.session.finishProbe(success: true, resetAfterFetch: false)

        #expect(firstPID == 11)
        #expect(secondPID == 11)
        #expect(fixture.launcher.launchedBinarySnapshot() == ["/old/agy", "/new/agy"])
    }

    @Test
    func replacement_waits_for_active_probe_before_relaunching() async throws {
        let fixture = self.makeFixture()
        fixture.identity.setIdentity(pid: 10, executablePath: "/old/agy", startEpoch: 100)
        fixture.identity.setIdentity(pid: 11, executablePath: "/new/agy", startEpoch: 101)

        let firstPID = try await fixture.session.beginProbe(binary: "/old/agy")
        let replacement = Task {
            try await fixture.session.beginProbe(binary: "/new/agy")
        }
        await Task.yield()
        await Task.yield()

        #expect(firstPID == 10)
        #expect(fixture.launcher.launchedBinarySnapshot() == ["/old/agy"])
        #expect(fixture.registry.unregisteredSnapshot().isEmpty)

        await fixture.session.finishProbe(success: true, resetAfterFetch: false)
        let secondPID = try await replacement.value
        await fixture.session.finishProbe(success: true, resetAfterFetch: false)

        #expect(secondPID == 11)
        #expect(fixture.launcher.launchedBinarySnapshot() == ["/old/agy", "/new/agy"])
        #expect(fixture.registry.unregisteredSnapshot() == [10])
    }

    @Test
    func queued_replacement_hard_stops_a_signed_out_process() async throws {
        let fixture = self.makeFixture()
        fixture.identity.setIdentity(pid: 10, executablePath: "/old/agy", startEpoch: 100)
        fixture.identity.setIdentity(pid: 11, executablePath: "/new/agy", startEpoch: 101)

        _ = try await fixture.session.beginProbe(binary: "/old/agy")
        let replacement = Task {
            try await fixture.session.beginProbe(binary: "/new/agy")
        }
        for _ in 0..<100 where await fixture.session.activeProbeCountForTesting < 2 {
            await Task.yield()
        }
        #expect(await fixture.session.activeProbeCountForTesting == 2)

        await fixture.session.finishProbe(success: false, resetAfterFetch: true, forceTerminate: true)
        let replacementPID = try await replacement.value
        let oldEvents = try #require(fixture.launcher.handleSnapshot().first).snapshotEvents()
        #expect(await fixture.session.lastStopReasonForTesting == "authentication required")
        await fixture.session.finishProbe(success: true, resetAfterFetch: true)

        #expect(replacementPID == 11)
        #expect(!oldEvents.contains("sendExit"))
        #expect(oldEvents.contains("terminateRoot"))
    }

    @Test
    func replacement_ignores_queued_starters_while_waiting_for_active_probe() async throws {
        let fixture = self.makeFixture()
        fixture.identity.setIdentity(pid: 10, executablePath: "/old/agy", startEpoch: 100)
        fixture.identity.setIdentity(pid: 11, executablePath: "/new/agy", startEpoch: 101)

        _ = try await fixture.session.beginProbe(binary: "/old/agy")
        let firstReplacement = Task {
            try await fixture.session.beginProbe(binary: "/new/agy")
        }
        let secondReplacement = Task {
            try await fixture.session.beginProbe(binary: "/new/agy")
        }
        await Task.yield()
        await Task.yield()

        #expect(fixture.launcher.launchedBinarySnapshot() == ["/old/agy"])

        await fixture.session.finishProbe(success: true, resetAfterFetch: false)
        let didLaunchReplacement = await self.waitForLaunches(fixture.launcher, count: 2)
        #expect(didLaunchReplacement)
        if !didLaunchReplacement {
            await fixture.session.finishProbe(success: true, resetAfterFetch: false)
        }

        let firstPID = try await firstReplacement.value
        let secondPID = try await secondReplacement.value
        await fixture.session.finishProbe(success: true, resetAfterFetch: false)
        await fixture.session.finishProbe(success: true, resetAfterFetch: false)

        #expect(firstPID == 11)
        #expect(secondPID == 11)
        #expect(fixture.launcher.launchedBinarySnapshot() == ["/old/agy", "/new/agy"])
    }

    @Test
    func relaunches_when_existing_process_is_dead() async throws {
        let fixture = self.makeFixture()
        fixture.identity.setIdentity(pid: 10, executablePath: "/bin/agy", startEpoch: 100)
        fixture.identity.setIdentity(pid: 11, executablePath: "/bin/agy", startEpoch: 101)

        _ = try await fixture.session.beginProbe(binary: "/bin/agy")
        await fixture.session.finishProbe(success: true, resetAfterFetch: false)
        fixture.launcher.handleSnapshot().first?.terminateRoot()
        let secondPID = try await fixture.session.beginProbe(binary: "/bin/agy")
        await fixture.session.finishProbe(success: true, resetAfterFetch: false)

        #expect(secondPID == 11)
        #expect(fixture.launcher.launchedBinarySnapshot() == ["/bin/agy", "/bin/agy"])
    }

    @Test
    func pty_launcher_creates_dedicated_process_group_before_returning() throws {
        let launcher = AntigravityPTYProcessLauncher()
        let handle = try launcher.launch(binary: "/bin/cat")
        defer {
            handle.killRoot()
            handle.terminateTree(signal: SIGKILL, knownDescendants: [])
            handle.closePTY()
        }

        #expect(handle.processGroup == handle.pid)
        #expect(getpgid(handle.pid) == handle.pid)
    }

    @Test
    func pty_launcher_resets_termination_signals_for_child_process() {
        var signals = AntigravityPTYProcessLauncher.defaultSignalsForSpawn()

        #expect(sigismember(&signals, SIGINT) == 1)
        #expect(sigismember(&signals, SIGTERM) == 1)
        #expect(sigismember(&signals, SIGHUP) == 1)
    }

    @Test
    func pty_launcher_retries_transient_text_busy_spawn_errors() {
        var attempts = 0

        let result = AntigravityPTYProcessLauncher.spawnWithTextBusyRetry(retryDelay: 0) {
            attempts += 1
            return attempts < 3 ? ETXTBSY : 0
        }

        #expect(result == 0)
        #expect(attempts == 3)
    }

    @Test
    func pty_launcher_does_not_retry_other_spawn_errors() {
        var attempts = 0

        let result = AntigravityPTYProcessLauncher.spawnWithTextBusyRetry(retryDelay: 0) {
            attempts += 1
            return EACCES
        }

        #expect(result == EACCES)
        #expect(attempts == 1)
    }

    @Test
    func pty_launcher_uses_home_and_closes_unrelated_descriptors() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("antigravity-spawn-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let inheritedSourceFD = open("/dev/null", O_RDONLY)
        guard inheritedSourceFD >= 0 else {
            Issue.record("Failed to open descriptor fixture")
            return
        }
        defer { close(inheritedSourceFD) }
        let inheritedFD = fcntl(inheritedSourceFD, F_DUPFD, 200)
        guard inheritedFD >= 200 else {
            Issue.record("Failed to duplicate descriptor fixture")
            return
        }
        defer { close(inheritedFD) }

        let outputURL = tempDirectory.appendingPathComponent("result.txt")
        let script = """
        pwd > \(outputURL.path)
        if [ -e /dev/fd/\(inheritedFD) ] || [ -e /proc/self/fd/\(inheritedFD) ]; then
          echo inherited >> \(outputURL.path)
        else
          echo closed >> \(outputURL.path)
        fi
        """

        let handle = try AntigravityPTYProcessLauncher().launch(
            binary: "/bin/sh",
            arguments: ["-c", script])
        defer {
            handle.killRoot()
            handle.terminateTree(signal: SIGKILL, knownDescendants: [])
            handle.closePTY()
        }

        for _ in 0..<200 {
            if FileManager.default.fileExists(atPath: outputURL.path),
               let output = try? String(contentsOf: outputURL, encoding: .utf8)
            {
                let lines = output
                    .split(separator: "\n")
                    .map(String.init)
                if lines.count >= 2, output.hasSuffix("\n") { break }
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        let lines = try String(contentsOf: outputURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        #expect(lines == [NSHomeDirectory(), "closed"])
    }

    @Test
    func spawned_PTY_drain_is_bounded_per_call() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("antigravity-drain-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }
        try Data(repeating: 1, count: 8192 * 65).write(to: temp)
        let primaryFD = open(temp.path, O_RDONLY)
        guard primaryFD >= 0 else {
            Issue.record("Failed to open temporary drain input")
            return
        }
        let secondaryFD = open("/dev/null", O_RDONLY)
        guard secondaryFD >= 0 else {
            close(primaryFD)
            Issue.record("Failed to open /dev/null")
            return
        }
        let handle = AntigravitySpawnedPTYProcessHandle(
            pid: getpid(),
            processGroup: getpgrp(),
            primaryFD: primaryFD,
            primaryHandle: FileHandle(fileDescriptor: primaryFD, closeOnDealloc: true),
            secondaryHandle: FileHandle(fileDescriptor: secondaryFD, closeOnDealloc: true))
        defer { handle.closePTY() }

        let output = handle.drainOutput()

        #expect(lseek(primaryFD, 0, SEEK_CUR) == off_t(8192 * 64))
        #expect(output.count == 8192 * 64)
    }

    @Test
    func session_keeps_one_rolling_PTY_buffer_across_concurrent_probes() async throws {
        let fixture = self.makeFixture()
        fixture.identity.setIdentity(pid: 10, executablePath: "/bin/agy", startEpoch: 100)

        _ = try await fixture.session.beginProbe(binary: "/bin/agy")
        _ = try await fixture.session.beginProbe(binary: "/bin/agy")
        let handle = try #require(fixture.launcher.handleSnapshot().first)
        handle.enqueueDrainOutput(Data([0xE2, 0x96]))
        let first = await fixture.session.drainOutput()
        handle.enqueueDrainOutput(Data([0x84]) + Data("Select login method:".utf8))
        let second = await fixture.session.drainOutput()
        let third = await fixture.session.drainOutput()

        #expect(first == Data([0xE2, 0x96]))
        #expect(AntigravityCLIHTTPSFetchStrategy.containsAuthenticationPrompt(second))
        #expect(third == second)

        await fixture.session.finishProbe(success: false, resetAfterFetch: true, forceTerminate: true)
        await fixture.session.finishProbe(success: false, resetAfterFetch: false)
    }

    @Test
    func authentication_prompt_matcher_tolerates_prompt_casing_and_spacing() {
        #expect(AntigravityCLIHTTPSFetchStrategy.containsAuthenticationPrompt(
            Data("select  LOGIN\nmethod :".utf8)))
        #expect(AntigravityCLIHTTPSFetchStrategy.containsAuthenticationPrompt(
            Data("Select login method:".utf8)))
        #expect(!AntigravityCLIHTTPSFetchStrategy.containsAuthenticationPrompt(
            Data("You are currently not signed in".utf8)))
    }

    @Test
    func session_returns_complete_new_output_before_retaining_only_its_tail() async throws {
        let fixture = self.makeFixture()
        fixture.identity.setIdentity(pid: 10, executablePath: "/bin/agy", startEpoch: 100)

        _ = try await fixture.session.beginProbe(binary: "/bin/agy")
        let handle = try #require(fixture.launcher.handleSnapshot().first)
        let prompt = Data("Select login method:".utf8)
        let oversizedRedraw = prompt + Data(repeating: 0x20, count: 8192)
        handle.enqueueDrainOutput(oversizedRedraw)

        let searchableOutput = await fixture.session.drainOutput()
        let retainedTail = await fixture.session.drainOutput()

        #expect(searchableOutput == oversizedRedraw)
        #expect(AntigravityCLIHTTPSFetchStrategy.containsAuthenticationPrompt(searchableOutput))
        #expect(AntigravityCLIHTTPSFetchStrategy.containsAuthenticationPrompt(retainedTail))

        await fixture.session.finishProbe(success: false, resetAfterFetch: true, forceTerminate: true)
    }

    @Test
    func registration_failure_tears_down_launched_process() async {
        let fixture = self.makeFixture()
        fixture.registry.setShouldRegister(false)

        await #expect(throws: AntigravityCLISession.SessionError.self) {
            _ = try await fixture.session.beginProbe(binary: "/bin/agy")
        }

        let handle = fixture.launcher.handleSnapshot().first
        #expect(handle?.isRunning == false)
        #expect(handle?.snapshotEvents().contains("sendExit") == false)
        #expect(handle?.snapshotEvents().contains("closePTY") == true)
        #expect(handle?.snapshotEvents().contains("terminateRoot") == true)
        #expect(fixture.registry.registeredSnapshot().isEmpty)
    }

    @Test
    func launch_remains_usable_when_coordination_lock_is_unavailable() async throws {
        let fixture = self.makeFixture(launchLock: FailingAntigravitySessionLaunchLock())
        fixture.identity.setIdentity(pid: 10, executablePath: "/bin/agy", startEpoch: 100)

        let pid = try await fixture.session.beginProbe(binary: "/bin/agy")
        await fixture.session.finishProbe(success: true, resetAfterFetch: true)

        #expect(pid == 10)
        #expect(fixture.store.snapshot() == nil)
    }

    @Test
    func launch_remains_usable_when_ownership_record_cannot_be_saved() async throws {
        let store = MemoryAntigravitySessionRecordStore(failSaves: true)
        let fixture = self.makeFixture(store: store)
        fixture.identity.setIdentity(pid: 10, executablePath: "/bin/agy", startEpoch: 100)

        let pid = try await fixture.session.beginProbe(binary: "/bin/agy")
        await fixture.session.finishProbe(success: true, resetAfterFetch: true)

        #expect(pid == 10)
        #expect(store.snapshot() == nil)
    }

    @Test
    func idle_window_tears_down_warm_process() async throws {
        let fixture = self.makeFixture(idleWindow: 0.05, manualSleep: true)
        fixture.identity.setIdentity(pid: 10, executablePath: "/bin/agy", startEpoch: 100)

        _ = try await fixture.session.beginProbe(binary: "/bin/agy")
        await fixture.session.finishProbe(success: true, resetAfterFetch: false)
        await fixture.sleeper?.waitForSleeps(1)
        fixture.sleeper?.resumeAll()
        await self.waitUntilStopped(fixture.session)

        #expect(await fixture.session.isRunning == false)
        #expect(fixture.registry.unregisteredSnapshot() == [10])
        #expect(fixture.store.snapshot() == nil)
    }

    @Test
    func host_idle_window_extends_the_default_session_lifetime() async throws {
        let fixture = self.makeFixture(idleWindow: 180)
        fixture.identity.setIdentity(pid: 10, executablePath: "/bin/agy", startEpoch: 100)

        _ = try await fixture.session.beginProbe(binary: "/bin/agy", idleWindow: 360)
        await fixture.session.finishProbe(success: true, resetAfterFetch: false)

        #expect(await fixture.session.idleWindowForTesting == 360)
    }

    @Test
    func active_probe_prevents_idle_teardown_until_finish() async throws {
        let fixture = self.makeFixture(idleWindow: 0.05, manualSleep: true)
        fixture.identity.setIdentity(pid: 10, executablePath: "/bin/agy", startEpoch: 100)

        _ = try await fixture.session.beginProbe(binary: "/bin/agy")
        await fixture.session.finishProbe(success: true, resetAfterFetch: false)
        _ = try await fixture.session.beginProbe(binary: "/bin/agy")
        await fixture.sleeper?.waitForSleeps(1)
        fixture.sleeper?.resumeAll()
        await Task.yield()

        #expect(await fixture.session.isRunning)
        await fixture.session.finishProbe(success: true, resetAfterFetch: false)
        await fixture.sleeper?.waitForSleeps(1)
        fixture.sleeper?.resumeAll()
        await self.waitUntilStopped(fixture.session)
        #expect(await fixture.session.isRunning == false)
    }

    @Test
    func manual_reset_waits_for_active_probe_to_finish() async throws {
        let fixture = self.makeFixture()
        fixture.identity.setIdentity(pid: 10, executablePath: "/bin/agy", startEpoch: 100)

        _ = try await fixture.session.beginProbe(binary: "/bin/agy")
        await fixture.session.reset()
        #expect(await fixture.session.isRunning)
        await fixture.session.finishProbe(success: true, resetAfterFetch: false)

        #expect(await fixture.session.isRunning == false)
        #expect(fixture.registry.unregisteredSnapshot() == [10])
    }

    @Test
    func reset_reaps_persisted_stale_session_when_no_in_memory_process_exists() async {
        let store = MemoryAntigravitySessionRecordStore(record: AntigravityCLISessionRecord(
            pid: 777,
            requestedBinaryPath: "/bin/agy",
            executablePath: "/bin/agy",
            startEpoch: 42,
            processGroup: 777))
        let fixture = self.makeFixture(store: store)
        fixture.identity.setIdentity(pid: 777, executablePath: "/bin/agy", startEpoch: 42)

        await fixture.session.reset()

        let terminations = fixture.terminations.snapshot()
        #expect(terminations.map(\.signal) == [SIGTERM, SIGKILL])
        #expect(terminations.allSatisfy { $0.pid == 777 && $0.group == 777 })
        #expect(fixture.store.snapshot() == nil)
    }

    @Test
    func reset_preserves_persisted_session_owned_by_another_live_process() async {
        let store = MemoryAntigravitySessionRecordStore(record: AntigravityCLISessionRecord(
            pid: 777,
            requestedBinaryPath: "/bin/agy",
            executablePath: "/bin/agy",
            startEpoch: 42,
            processGroup: 777,
            ownerPID: 900,
            ownerExecutablePath: "/Applications/CodexBar.app/Contents/MacOS/CodexBar",
            ownerStartEpoch: 10))
        let fixture = self.makeFixture(store: store, currentProcessID: 901)
        fixture.identity.setIdentity(pid: 777, executablePath: "/bin/agy", startEpoch: 42)
        fixture.identity.setIdentity(
            pid: 900,
            executablePath: "/Applications/CodexBar.app/Contents/MacOS/CodexBar",
            startEpoch: 10)

        await fixture.session.reset()

        #expect(fixture.terminations.snapshot().isEmpty)
        #expect(fixture.store.snapshot() != nil)
    }

    @Test
    func launch_tracks_an_independent_session_while_another_process_is_live() async throws {
        let protectedRecord = AntigravityCLISessionRecord(
            pid: 777,
            requestedBinaryPath: "/bin/agy",
            executablePath: "/bin/agy",
            startEpoch: 42,
            processGroup: 777,
            ownerPID: 900,
            ownerExecutablePath: "/Applications/CodexBar.app/Contents/MacOS/CodexBar",
            ownerStartEpoch: 10)
        let store = MemoryAntigravitySessionRecordStore(record: protectedRecord)
        let fixture = self.makeFixture(store: store, currentProcessID: 901)
        fixture.identity.setIdentity(pid: 777, executablePath: "/bin/agy", startEpoch: 42)
        fixture.identity.setIdentity(
            pid: 900,
            executablePath: "/Applications/CodexBar.app/Contents/MacOS/CodexBar",
            startEpoch: 10)
        fixture.identity.setIdentity(pid: 10, executablePath: "/bin/agy", startEpoch: 100)
        fixture.identity.setIdentity(pid: 901, executablePath: "/app/codexbar", startEpoch: 20)

        _ = try await fixture.session.beginProbe(binary: "/bin/agy")

        #expect(fixture.launcher.launchedBinarySnapshot() == ["/bin/agy"])
        #expect(fixture.terminations.snapshot().isEmpty)
        #expect(fixture.store.saveCount == 1)
        #expect(Set(fixture.store.snapshots().map(\.pid)) == [10, 777])

        await fixture.session.finishProbe(success: true, resetAfterFetch: true)
        #expect(fixture.store.snapshot() == protectedRecord)
    }

    @Test
    func different_binary_tracks_an_independent_session_while_another_process_is_live() async throws {
        let protectedRecord = AntigravityCLISessionRecord(
            pid: 777,
            requestedBinaryPath: "/bin/agy",
            executablePath: "/bin/agy",
            startEpoch: 42,
            processGroup: 777,
            ownerPID: 900,
            ownerExecutablePath: "/Applications/CodexBar.app/Contents/MacOS/CodexBar",
            ownerStartEpoch: 10)
        let store = MemoryAntigravitySessionRecordStore(record: protectedRecord)
        let fixture = self.makeFixture(store: store, currentProcessID: 901)
        fixture.identity.setIdentity(pid: 777, executablePath: "/bin/agy", startEpoch: 42)
        fixture.identity.setIdentity(
            pid: 900,
            executablePath: "/Applications/CodexBar.app/Contents/MacOS/CodexBar",
            startEpoch: 10)
        fixture.identity.setIdentity(pid: 10, executablePath: "/new/agy", startEpoch: 100)
        fixture.identity.setIdentity(pid: 901, executablePath: "/app/codexbar", startEpoch: 20)

        _ = try await fixture.session.beginProbe(binary: "/new/agy")

        #expect(fixture.launcher.launchedBinarySnapshot() == ["/new/agy"])
        #expect(fixture.store.saveCount == 1)
        #expect(Set(fixture.store.snapshots().map(\.pid)) == [10, 777])

        await fixture.session.finishProbe(success: true, resetAfterFetch: true)
        #expect(fixture.store.snapshot() == protectedRecord)
    }

    @Test
    func concurrent_hosts_atomically_track_independent_sessions() async {
        let store = MemoryAntigravitySessionRecordStore()
        let launchLock = MemoryAntigravitySessionLaunchLock()
        let identity = FakeAntigravityIdentityProvider()
        let firstLauncher = FakeAntigravityProcessLauncher(nextPID: 10)
        let secondLauncher = FakeAntigravityProcessLauncher(nextPID: 20)
        identity.setIdentity(pid: 10, executablePath: "/bin/agy", startEpoch: 100)
        identity.setIdentity(pid: 20, executablePath: "/bin/agy", startEpoch: 200)
        identity.setIdentity(pid: 900, executablePath: "/app/CodexBar", startEpoch: 1)
        identity.setIdentity(pid: 901, executablePath: "/app/codexbar", startEpoch: 2)
        let first = self.makeFixture(
            launcher: firstLauncher,
            identity: identity,
            store: store,
            launchLock: launchLock,
            currentProcessID: 900)
        let second = self.makeFixture(
            launcher: secondLauncher,
            identity: identity,
            store: store,
            launchLock: launchLock,
            currentProcessID: 901)

        async let firstStarted = Self.beginPersistentSession(first.session)
        async let secondStarted = Self.beginPersistentSession(second.session)
        let results = await [firstStarted, secondStarted]

        #expect(!results.contains(false))
        #expect(firstLauncher.launchedBinarySnapshot().count + secondLauncher.launchedBinarySnapshot().count == 2)
        #expect(Set(store.snapshots().map(\.pid)) == [10, 20])

        await first.session.reset()
        await second.session.reset()
        #expect(store.snapshots().isEmpty)
    }
}

extension AntigravityCLISessionTests {
    @Test
    func warm_reuse_reaps_a_crashed_peer_session() async throws {
        let store = MemoryAntigravitySessionRecordStore()
        let launchLock = MemoryAntigravitySessionLaunchLock()
        let identity = FakeAntigravityIdentityProvider()
        let firstLauncher = FakeAntigravityProcessLauncher(nextPID: 10)
        let secondLauncher = FakeAntigravityProcessLauncher(nextPID: 20)
        identity.setIdentity(pid: 10, executablePath: "/bin/agy", startEpoch: 100)
        identity.setIdentity(pid: 20, executablePath: "/bin/agy", startEpoch: 200)
        identity.setIdentity(pid: 900, executablePath: "/app/CodexBar", startEpoch: 1)
        identity.setIdentity(pid: 901, executablePath: "/app/codexbar", startEpoch: 2)
        let first = self.makeFixture(
            launcher: firstLauncher,
            identity: identity,
            store: store,
            launchLock: launchLock,
            currentProcessID: 900)
        let second = self.makeFixture(
            launcher: secondLauncher,
            identity: identity,
            store: store,
            launchLock: launchLock,
            currentProcessID: 901)
        #expect(await Self.beginPersistentSession(first.session))
        #expect(await Self.beginPersistentSession(second.session))

        identity.removeIdentity(pid: 901)
        _ = try await first.session.beginProbe(binary: "/bin/agy")
        await first.session.finishProbe(success: true, resetAfterFetch: false)

        #expect(first.terminations.snapshot().map(\.pid) == [20, 20])
        #expect(store.snapshots().map(\.pid) == [10])

        await first.session.reset()
        await second.session.reset()
    }

    @Test
    func file_store_migrates_legacy_record_and_preserves_independent_owners() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexBarAntigravitySessionTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("agy-session.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let legacy = AntigravityCLISessionRecord(
            pid: 10,
            requestedBinaryPath: "/bin/agy",
            executablePath: "/bin/agy",
            startEpoch: 100,
            processGroup: 10,
            ownerPID: 900,
            ownerExecutablePath: "/app/CodexBar",
            ownerStartEpoch: 1)
        try JSONEncoder().encode(legacy).write(to: fileURL)
        let store = AntigravityFileCLISessionRecordStore(fileURL: fileURL)
        #expect(try store.load() == [legacy])

        let second = AntigravityCLISessionRecord(
            pid: 20,
            requestedBinaryPath: "/bin/agy",
            executablePath: "/bin/agy",
            startEpoch: 200,
            processGroup: 20,
            ownerPID: 901,
            ownerExecutablePath: "/app/codexbar",
            ownerStartEpoch: 2)
        try store.save(second)
        #expect(try Set(store.load().map(\.pid)) == [10, 20])

        try store.remove(legacy)
        #expect(try store.load() == [second])

        try Data("{".utf8).write(to: fileURL)
        try store.save(legacy)
        #expect(try store.load() == [legacy])
    }

    @Test
    func session_reaps_stale_owner_before_launch() async throws {
        let protectedRecord = AntigravityCLISessionRecord(
            pid: 777,
            requestedBinaryPath: "/bin/agy",
            executablePath: "/bin/agy",
            startEpoch: 42,
            processGroup: 777,
            ownerPID: 900,
            ownerExecutablePath: "/Applications/CodexBar.app/Contents/MacOS/CodexBar",
            ownerStartEpoch: 10)
        let store = MemoryAntigravitySessionRecordStore(record: protectedRecord)
        let fixture = self.makeFixture(store: store, currentProcessID: 901)
        fixture.identity.setIdentity(pid: 777, executablePath: "/bin/agy", startEpoch: 42)
        fixture.identity.setIdentity(
            pid: 900,
            executablePath: "/Applications/CodexBar.app/Contents/MacOS/CodexBar",
            startEpoch: 10)
        fixture.identity.setIdentity(
            pid: 901,
            executablePath: "/Applications/CodexBar.app/Contents/MacOS/CodexBar",
            startEpoch: 20)
        fixture.identity.setIdentity(pid: 10, executablePath: "/bin/agy", startEpoch: 100)

        fixture.identity.removeIdentity(pid: 900)
        let secondPID = try await fixture.session.beginProbe(binary: "/bin/agy")
        let record = fixture.store.snapshot()
        await fixture.session.finishProbe(success: true, resetAfterFetch: true)
        #expect(secondPID == 10)
        #expect(fixture.launcher.launchedBinarySnapshot() == ["/bin/agy"])
        #expect(fixture.terminations.snapshot().map(\.pid) == [777, 777])
        #expect(fixture.store.saveCount == 1)
        #expect(record?.pid == 10)
        #expect(record?.ownerPID == 901)
    }

    @Test
    func reset_rechecks_protected_persisted_session_after_owner_exits() async {
        let store = MemoryAntigravitySessionRecordStore(record: AntigravityCLISessionRecord(
            pid: 777,
            requestedBinaryPath: "/bin/agy",
            executablePath: "/bin/agy",
            startEpoch: 42,
            processGroup: 777,
            ownerPID: 900,
            ownerExecutablePath: "/Applications/CodexBar.app/Contents/MacOS/CodexBar",
            ownerStartEpoch: 10))
        let fixture = self.makeFixture(store: store, currentProcessID: 901)
        fixture.identity.setIdentity(pid: 777, executablePath: "/bin/agy", startEpoch: 42)
        fixture.identity.setIdentity(
            pid: 900,
            executablePath: "/Applications/CodexBar.app/Contents/MacOS/CodexBar",
            startEpoch: 10)

        await fixture.session.reset()
        fixture.identity.removeIdentity(pid: 900)
        await fixture.session.reset()

        let terminations = fixture.terminations.snapshot()
        #expect(terminations.map(\.signal) == [SIGTERM, SIGKILL])
        #expect(terminations.allSatisfy { $0.pid == 777 && $0.group == 777 })
        #expect(fixture.store.snapshot() == nil)
    }

    @Test
    func teardown_preserves_record_written_by_another_live_session() async throws {
        let fixture = self.makeFixture()
        fixture.identity.setIdentity(pid: 10, executablePath: "/bin/agy", startEpoch: 100)

        _ = try await fixture.session.beginProbe(binary: "/bin/agy")
        let otherRecord = AntigravityCLISessionRecord(
            pid: 777,
            requestedBinaryPath: "/other/agy",
            executablePath: "/other/agy",
            startEpoch: 42,
            processGroup: 777)
        try fixture.store.save(otherRecord)
        await fixture.session.finishProbe(success: true, resetAfterFetch: true)

        #expect(fixture.store.snapshot() == otherRecord)
    }

    @Test
    func force_killed_process_is_polled_again_so_the_child_can_be_reaped() async throws {
        let fixture = self.makeFixture(terminateRootStopsProcess: false)
        fixture.identity.setIdentity(pid: 10, executablePath: "/bin/agy", startEpoch: 100)
        fixture.identity.setIdentity(pid: 900, executablePath: "/app/CodexBar", startEpoch: 1)

        _ = try await fixture.session.beginProbe(binary: "/bin/agy")
        await fixture.session.finishProbe(success: true, resetAfterFetch: true)

        let events = fixture.launcher.handleSnapshot().first?.snapshotEvents() ?? []
        guard let killIndex = events.firstIndex(of: "terminateTree:\(SIGKILL)") else {
            Issue.record("Expected SIGKILL during teardown")
            return
        }
        #expect(events.dropFirst(killIndex + 1).contains("isRunning:false"))
    }

    @Test
    func one_shot_CLI_reset_tears_down_after_fetch() async throws {
        let fixture = self.makeFixture()
        fixture.identity.setIdentity(pid: 10, executablePath: "/bin/agy", startEpoch: 100)

        _ = try await fixture.session.beginProbe(binary: "/bin/agy")
        await fixture.session.finishProbe(success: true, resetAfterFetch: true)

        #expect(await fixture.session.isRunning == false)
        #expect(fixture.registry.unregisteredSnapshot() == [10])
    }

    @Test
    func one_shot_CLI_reset_is_deferred_until_all_active_probes_finish() async throws {
        let fixture = self.makeFixture()
        fixture.identity.setIdentity(pid: 10, executablePath: "/bin/agy", startEpoch: 100)

        _ = try await fixture.session.beginProbe(binary: "/bin/agy")
        _ = try await fixture.session.beginProbe(binary: "/bin/agy")

        await fixture.session.finishProbe(success: true, resetAfterFetch: true)
        #expect(await fixture.session.isRunning)

        await fixture.session.finishProbe(success: true, resetAfterFetch: false)

        #expect(await fixture.session.isRunning == false)
        #expect(fixture.registry.unregisteredSnapshot() == [10])
    }

    @Test
    func authentication_reset_never_writes_interactive_exit_input() async throws {
        let fixture = self.makeFixture()
        fixture.identity.setIdentity(pid: 10, executablePath: "/bin/agy", startEpoch: 100)

        _ = try await fixture.session.beginProbe(binary: "/bin/agy")
        await fixture.session.finishProbe(success: false, resetAfterFetch: true, forceTerminate: true)

        let events = try #require(fixture.launcher.handleSnapshot().first).snapshotEvents()
        #expect(!events.contains("sendExit"))
        #expect(events.contains("closePTY"))
        #expect(events.contains("terminateRoot"))
        #expect(await fixture.session.isRunning == false)
    }

    @Test
    func failed_reset_never_writes_interactive_exit_input() async throws {
        let fixture = self.makeFixture()
        fixture.identity.setIdentity(pid: 10, executablePath: "/bin/agy", startEpoch: 100)

        _ = try await fixture.session.beginProbe(binary: "/bin/agy")
        await fixture.session.finishProbe(success: false, resetAfterFetch: true)

        let events = try #require(fixture.launcher.handleSnapshot().first).snapshotEvents()
        #expect(!events.contains("sendExit"))
        #expect(events.contains("terminateRoot"))
        #expect(await fixture.session.isRunning == false)
    }

    @Test
    func concurrent_success_preserves_a_failed_probes_deferred_hard_reset() async throws {
        let fixture = self.makeFixture()
        fixture.identity.setIdentity(pid: 10, executablePath: "/bin/agy", startEpoch: 100)

        _ = try await fixture.session.beginProbe(binary: "/bin/agy")
        _ = try await fixture.session.beginProbe(binary: "/bin/agy")
        await fixture.session.finishProbe(success: false, resetAfterFetch: true)
        #expect(await fixture.session.isRunning)

        await fixture.session.finishProbe(success: true, resetAfterFetch: false)

        let events = try #require(fixture.launcher.handleSnapshot().first).snapshotEvents()
        #expect(!events.contains("sendExit"))
        #expect(events.contains("terminateRoot"))
        #expect(await fixture.session.isRunning == false)
    }

    @Test
    func idle_timeout_hard_stops_a_previously_failed_process() async throws {
        let fixture = self.makeFixture(idleWindow: 0.05, manualSleep: true)
        fixture.identity.setIdentity(pid: 10, executablePath: "/bin/agy", startEpoch: 100)

        _ = try await fixture.session.beginProbe(binary: "/bin/agy")
        await fixture.session.finishProbe(success: false, resetAfterFetch: false)
        await fixture.sleeper?.waitForSleeps(1)
        fixture.sleeper?.resumeAll()
        await self.waitUntilStopped(fixture.session)

        let events = try #require(fixture.launcher.handleSnapshot().first).snapshotEvents()
        #expect(!events.contains("sendExit"))
        #expect(events.contains("terminateRoot"))
    }

    @Test
    func repeated_probe_failures_relaunch_session() async throws {
        let fixture = self.makeFixture(failureRelaunchThreshold: 2)
        fixture.identity.setIdentity(pid: 10, executablePath: "/bin/agy", startEpoch: 100)
        fixture.identity.setIdentity(pid: 11, executablePath: "/bin/agy", startEpoch: 101)

        _ = try await fixture.session.beginProbe(binary: "/bin/agy")
        await fixture.session.finishProbe(success: false, resetAfterFetch: false)
        _ = try await fixture.session.beginProbe(binary: "/bin/agy")
        await fixture.session.finishProbe(success: false, resetAfterFetch: false)
        let relaunchedPID = try await fixture.session.beginProbe(binary: "/bin/agy")
        await fixture.session.finishProbe(success: true, resetAfterFetch: false)

        #expect(relaunchedPID == 11)
        #expect(fixture.launcher.launchedBinarySnapshot() == ["/bin/agy", "/bin/agy"])
        #expect(await fixture.session.failureCountForTesting == 0)
    }

    @Test
    func session_reset_reasons_distinguish_authentication_from_unhealthy_probes() {
        #expect(AntigravityCLISession.resetCause(
            authenticationRequired: true,
            resetAfterFetch: true,
            shouldForceStopUnhealthy: true).message == "authentication required")
        #expect(AntigravityCLISession.resetCause(
            authenticationRequired: false,
            resetAfterFetch: true,
            shouldForceStopUnhealthy: true).message == "unhealthy CLI HTTPS session")
        #expect(AntigravityCLISession.resetCause(
            authenticationRequired: false,
            resetAfterFetch: true,
            shouldForceStopUnhealthy: false).message == "one-shot CLI fetch")
        #expect(AntigravityCLISession.resetCause(
            authenticationRequired: false,
            resetAfterFetch: false,
            shouldForceStopUnhealthy: false).message == "deferred reset")
    }

    @Test
    func deferred_unhealthy_reset_preserves_its_cause_after_a_concurrent_success() async throws {
        let fixture = self.makeFixture(failureRelaunchThreshold: 1)
        fixture.identity.setIdentity(pid: 10, executablePath: "/bin/agy", startEpoch: 100)

        _ = try await fixture.session.beginProbe(binary: "/bin/agy")
        _ = try await fixture.session.beginProbe(binary: "/bin/agy")
        await fixture.session.finishProbe(success: false, resetAfterFetch: false)
        await fixture.session.finishProbe(success: true, resetAfterFetch: false)

        #expect(await fixture.session.lastStopReasonForTesting == "unhealthy CLI HTTPS session")
    }

    @Test
    func deferred_authentication_reset_preserves_its_cause_after_a_concurrent_success() async throws {
        let fixture = self.makeFixture()
        fixture.identity.setIdentity(pid: 10, executablePath: "/bin/agy", startEpoch: 100)

        _ = try await fixture.session.beginProbe(binary: "/bin/agy")
        _ = try await fixture.session.beginProbe(binary: "/bin/agy")
        await fixture.session.finishProbe(success: false, resetAfterFetch: true, forceTerminate: true)
        await fixture.session.finishProbe(success: true, resetAfterFetch: false)

        #expect(await fixture.session.lastStopReasonForTesting == "authentication required")
    }

    @Test
    func success_resets_failure_counter() async throws {
        let fixture = self.makeFixture(failureRelaunchThreshold: 2)
        fixture.identity.setIdentity(pid: 10, executablePath: "/bin/agy", startEpoch: 100)

        _ = try await fixture.session.beginProbe(binary: "/bin/agy")
        await fixture.session.finishProbe(success: false, resetAfterFetch: false)
        _ = try await fixture.session.beginProbe(binary: "/bin/agy")
        await fixture.session.finishProbe(success: true, resetAfterFetch: false)
        _ = try await fixture.session.beginProbe(binary: "/bin/agy")
        await fixture.session.finishProbe(success: false, resetAfterFetch: false)

        #expect(fixture.launcher.launchedBinarySnapshot() == ["/bin/agy"])
        #expect(await fixture.session.failureCountForTesting == 1)
    }

    @Test
    func matching_persisted_stale_process_is_reaped_when_resolved_binary_changed() async throws {
        let store = MemoryAntigravitySessionRecordStore(record: AntigravityCLISessionRecord(
            pid: 777,
            requestedBinaryPath: "/old/agy",
            executablePath: "/old/agy",
            startEpoch: 42,
            processGroup: 777))
        let fixture = self.makeFixture(store: store)
        fixture.identity.setIdentity(pid: 777, executablePath: "/old/agy", startEpoch: 42)
        fixture.identity.setIdentity(pid: 10, executablePath: "/new/agy", startEpoch: 100)

        _ = try await fixture.session.beginProbe(binary: "/new/agy")
        await fixture.session.finishProbe(success: true, resetAfterFetch: false)

        let terminations = fixture.terminations.snapshot()
        #expect(terminations.map(\.signal) == [SIGTERM, SIGKILL])
        #expect(terminations.allSatisfy { $0.pid == 777 && $0.group == 777 })
    }

    @Test
    func matching_persisted_stale_process_is_reaped_before_launch() async throws {
        let store = MemoryAntigravitySessionRecordStore(record: AntigravityCLISessionRecord(
            pid: 777,
            requestedBinaryPath: "/bin/agy",
            executablePath: "/bin/agy",
            startEpoch: 42,
            processGroup: 777))
        let fixture = self.makeFixture(store: store)
        fixture.identity.setIdentity(pid: 777, executablePath: "/bin/agy", startEpoch: 42)
        fixture.identity.setIdentity(pid: 10, executablePath: "/bin/agy", startEpoch: 100)

        _ = try await fixture.session.beginProbe(binary: "/bin/agy")
        await fixture.session.finishProbe(success: true, resetAfterFetch: false)

        let terminations = fixture.terminations.snapshot()
        #expect(terminations.map(\.signal) == [SIGTERM, SIGKILL])
        #expect(terminations.allSatisfy { $0.pid == 777 && $0.group == 777 })
    }

    @Test
    func non_matching_persisted_process_is_not_reaped() async throws {
        let store = MemoryAntigravitySessionRecordStore(record: AntigravityCLISessionRecord(
            pid: 777,
            requestedBinaryPath: "/bin/agy",
            executablePath: "/bin/agy",
            startEpoch: 42,
            processGroup: 777))
        let fixture = self.makeFixture(store: store)
        fixture.identity.setIdentity(pid: 777, executablePath: "/usr/bin/other", startEpoch: 42)
        fixture.identity.setIdentity(pid: 10, executablePath: "/bin/agy", startEpoch: 100)

        _ = try await fixture.session.beginProbe(binary: "/bin/agy")
        await fixture.session.finishProbe(success: true, resetAfterFetch: false)

        #expect(fixture.terminations.snapshot().isEmpty)
    }

    private func waitForLaunches(_ launcher: FakeAntigravityProcessLauncher, count: Int) async -> Bool {
        for _ in 0..<200 {
            if launcher.launchedBinarySnapshot().count >= count { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }

    private func waitUntilStopped(_ session: AntigravityCLISession) async {
        for _ in 0..<200 {
            let running = await session.isRunning
            if !running { return }
            await Task.yield()
        }
        Issue.record("Timed out waiting for Antigravity CLI session to stop")
    }

    private static func beginPersistentSession(_ session: AntigravityCLISession) async -> Bool {
        do {
            _ = try await session.beginProbe(binary: "/bin/agy")
            await session.finishProbe(success: true, resetAfterFetch: false)
            return true
        } catch {
            return false
        }
    }

    private struct Fixture {
        let session: AntigravityCLISession
        let launcher: FakeAntigravityProcessLauncher
        let identity: FakeAntigravityIdentityProvider
        let store: MemoryAntigravitySessionRecordStore
        let terminations: AntigravitySessionTerminationRecorder
        let registry: AntigravityRegistryRecorder
        let launchReservations: AntigravityLaunchReservationRecorder
        let sleeper: AntigravityManualSleeper?
    }

    private func makeFixture(
        launcher suppliedLauncher: FakeAntigravityProcessLauncher? = nil,
        identity suppliedIdentity: FakeAntigravityIdentityProvider? = nil,
        store: MemoryAntigravitySessionRecordStore = MemoryAntigravitySessionRecordStore(),
        launchLock: any AntigravityCLISessionLaunchLocking = MemoryAntigravitySessionLaunchLock(),
        idleWindow: TimeInterval = 3600,
        failureRelaunchThreshold: Int = 2,
        manualSleep: Bool = false,
        terminationGracePeriod: TimeInterval = 0,
        terminateRootStopsProcess: Bool = true,
        currentProcessID: pid_t = 900) -> Fixture
    {
        let launcher = suppliedLauncher ?? FakeAntigravityProcessLauncher(nextPID: 10)
        launcher.setTerminateRootStopsProcess(terminateRootStopsProcess)
        let identity = suppliedIdentity ?? FakeAntigravityIdentityProvider()
        let terminations = AntigravitySessionTerminationRecorder()
        let registry = AntigravityRegistryRecorder()
        let launchReservations = AntigravityLaunchReservationRecorder()
        let sleeper = manualSleep ? AntigravityManualSleeper() : nil
        let session = AntigravityCLISession(dependencies: AntigravityCLISession.Dependencies(
            launcher: launcher,
            identityProvider: identity,
            recordStore: store,
            launchLock: launchLock,
            beginAppShutdownTrackedLaunch: { launchReservations.begin() },
            endAppShutdownTrackedLaunch: { launchReservations.end() },
            registerForAppShutdown: { pid, binary in registry.register(pid: pid, binary) },
            updateAppShutdownProcessGroup: { pid, group in registry.update(pid: pid, group: group) },
            unregisterForAppShutdown: { pid in registry.unregister(pid: pid) },
            descendantPIDs: { pid in [pid + 1, pid + 2] },
            terminateProcessTree: { pid, group, signal, descendants in
                terminations.append(pid: pid, group: group, signal: signal, descendants: descendants)
            },
            currentProcessID: { currentProcessID },
            now: Date.init,
            sleep: { nanoseconds in
                if let sleeper {
                    try await sleeper.sleep(nanoseconds)
                } else {
                    try await Task.sleep(nanoseconds: nanoseconds)
                }
            },
            idleWindow: idleWindow,
            failureRelaunchThreshold: failureRelaunchThreshold,
            terminationGracePeriod: terminationGracePeriod))
        return Fixture(
            session: session,
            launcher: launcher,
            identity: identity,
            store: store,
            terminations: terminations,
            registry: registry,
            launchReservations: launchReservations,
            sleeper: sleeper)
    }
}
