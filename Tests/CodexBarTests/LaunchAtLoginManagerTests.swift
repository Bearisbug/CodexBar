import ServiceManagement
import Testing
@testable import CodexBar

@MainActor
struct LaunchAtLoginManagerTests {
    @Test
    func set_enabled_skips_registration_when_service_is_already_enabled() {
        var registerCalls = 0
        var unregisterCalls = 0

        LaunchAtLoginManager.setEnabled(
            true,
            status: { .enabled },
            register: { registerCalls += 1 },
            unregister: { unregisterCalls += 1 })

        #expect(registerCalls == 0)
        #expect(unregisterCalls == 0)
    }

    @Test
    func set_enabled_registers_when_service_is_not_registered() {
        var registerCalls = 0
        var unregisterCalls = 0

        LaunchAtLoginManager.setEnabled(
            true,
            status: { .notRegistered },
            register: { registerCalls += 1 },
            unregister: { unregisterCalls += 1 })

        #expect(registerCalls == 1)
        #expect(unregisterCalls == 0)
    }

    @Test
    func set_enabled_skips_registration_when_service_requires_approval() {
        var registerCalls = 0
        var unregisterCalls = 0

        LaunchAtLoginManager.setEnabled(
            true,
            status: { .requiresApproval },
            register: { registerCalls += 1 },
            unregister: { unregisterCalls += 1 })

        #expect(registerCalls == 0)
        #expect(unregisterCalls == 0)
    }

    @Test
    func set_enabled_registers_when_service_is_not_found() {
        var registerCalls = 0
        var unregisterCalls = 0

        LaunchAtLoginManager.setEnabled(
            true,
            status: { .notFound },
            register: { registerCalls += 1 },
            unregister: { unregisterCalls += 1 })

        #expect(registerCalls == 1)
        #expect(unregisterCalls == 0)
    }

    @Test
    func set_disabled_unregisters_when_service_is_enabled() {
        var registerCalls = 0
        var unregisterCalls = 0

        LaunchAtLoginManager.setEnabled(
            false,
            status: { .enabled },
            register: { registerCalls += 1 },
            unregister: { unregisterCalls += 1 })

        #expect(registerCalls == 0)
        #expect(unregisterCalls == 1)
    }

    @Test
    func set_disabled_unregisters_when_service_requires_approval() {
        var registerCalls = 0
        var unregisterCalls = 0

        LaunchAtLoginManager.setEnabled(
            false,
            status: { .requiresApproval },
            register: { registerCalls += 1 },
            unregister: { unregisterCalls += 1 })

        #expect(registerCalls == 0)
        #expect(unregisterCalls == 1)
    }

    @Test
    func set_disabled_skips_unregister_when_service_is_not_registered() {
        var registerCalls = 0
        var unregisterCalls = 0

        LaunchAtLoginManager.setEnabled(
            false,
            status: { .notRegistered },
            register: { registerCalls += 1 },
            unregister: { unregisterCalls += 1 })

        #expect(registerCalls == 0)
        #expect(unregisterCalls == 0)
    }

    @Test
    func set_disabled_skips_unregister_when_service_is_not_found() {
        var registerCalls = 0
        var unregisterCalls = 0

        LaunchAtLoginManager.setEnabled(
            false,
            status: { .notFound },
            register: { registerCalls += 1 },
            unregister: { unregisterCalls += 1 })

        #expect(registerCalls == 0)
        #expect(unregisterCalls == 0)
    }
}
