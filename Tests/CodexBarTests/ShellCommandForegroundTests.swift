import Darwin
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct ShellCommandForegroundTests {
    @Test
    func shell_probe_requests_a_detached_session() {
        let flags = ShellCommandLocator.test_shellSpawnFlags

        #expect(flags & Int16(POSIX_SPAWN_SETSID) != 0)
        #expect(flags & Int16(POSIX_SPAWN_CLOEXEC_DEFAULT) != 0)
        #expect(flags & Int16(POSIX_SPAWN_SETPGROUP) == 0)
    }
}
