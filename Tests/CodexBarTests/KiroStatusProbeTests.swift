// swiftlint:disable file_length
import Foundation
import Testing
@testable import CodexBarCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

private func waitForFile(_ url: URL) async throws {
    for _ in 0..<100 where !FileManager.default.fileExists(atPath: url.path) {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(FileManager.default.fileExists(atPath: url.path))
}

@Suite(.serialized)
struct KiroStatusProbeTests {
    @Test
    func fetch_returns_usage_when_account_probe_times_out() async throws {
        let cliURL = try self.makeCLI(
            """
            #!/bin/sh
            if [ "$1" = "whoami" ]; then
              sleep 5
              printf 'Logged in with Google\\nEmail: person@example.com\\n'
              exit 0
            fi

            if [ "$1" = "chat" ] && [ "$3" = "/usage" ]; then
              printf 'Estimated Usage | resets on 2026-06-01 | KIRO FREE\\n'
              printf 'Credits (12.50 of 50 covered in plan)\\n'
              printf '████████████████████ 25%%\\n'
              exit 0
            fi

            if [ "$1" = "chat" ] && [ "$3" = "/context" ]; then
              exit 0
            fi

            exit 1
            """)
        defer { try? FileManager.default.removeItem(at: cliURL.deletingLastPathComponent()) }

        let probe = KiroStatusProbe(cliBinaryResolver: { cliURL.path }, accountProbeTimeout: 0.2)
        let snapshot = try await probe.fetch()

        #expect(snapshot.planName == "KIRO FREE")
        #expect(snapshot.creditsUsed == 12.50)
        #expect(snapshot.accountEmail == nil)
        #expect(snapshot.authMethod == nil)
    }

    @Test
    func pipe_and_PTY_share_the_account_deadline() async throws {
        let cliURL = try self.makeCLI(
            """
            #!/bin/sh
            if [ "$1" = "whoami" ]; then
              if [ ! -t 1 ]; then
                sleep 5
                exit 1
              fi
              sleep 0.45
              printf 'Logged in with Google\nEmail: person@example.com\n'
              exit 0
            fi
            if [ "$1" = "chat" ] && [ "$3" = "/usage" ]; then
              printf 'Estimated Usage | resets on 2026-06-01 | KIRO FREE\n'
              printf 'Credits (12.50 of 50 covered in plan)\n'
              printf '████████████████████ 25%%\n'
              exit 0
            fi
            if [ "$1" = "chat" ] && [ "$3" = "/context" ]; then
              exit 0
            fi
            exit 1
            """)
        defer { try? FileManager.default.removeItem(at: cliURL.deletingLastPathComponent()) }

        let snapshot = try await KiroStatusProbe(
            cliBinaryResolver: { cliURL.path },
            accountProbeTimeout: 0.8,
            pipeTimeoutCap: 0.4).fetch()

        #expect(snapshot.planName == "KIRO FREE")
        #expect(snapshot.accountEmail == nil)
        #expect(snapshot.authMethod == nil)
    }

    @Test
    func accepted_pipe_output_cannot_overrun_the_usage_deadline() async throws {
        let pipePIDFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-kiro-deadline-\(UUID().uuidString).pid")
        let ptyMarker = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-kiro-deadline-\(UUID().uuidString).pty")
        let cliURL = try self.makeCLI(
            """
            #!/bin/sh
            if [ "$1" = "whoami" ]; then
              printf 'Logged in with Google\nEmail: person@example.com\n'
              exit 0
            fi
            if [ "$1" = "chat" ] && [ "$3" = "/usage" ]; then
              if [ ! -t 1 ]; then
                printf '%s\n' "$$" > '\(pipePIDFile.path)'
                printf 'Estimated Usage | resets on 2026-06-01 | KIRO FREE\n'
                printf 'Credits (12.50 of 50 covered in plan)\n'
                printf '████████████████████ 25%%\n'
                trap '' TERM
                while true; do sleep 1; done
              fi
              : > '\(ptyMarker.path)'
              printf 'Estimated Usage | resets on 2026-06-01 | KIRO FREE\n'
              printf 'Credits (12.50 of 50 covered in plan)\n'
              printf '████████████████████ 25%%\n'
              exit 0
            fi
            if [ "$1" = "chat" ] && [ "$3" = "/context" ]; then
              exit 0
            fi
            exit 1
            """)
        defer {
            if let text = try? String(contentsOf: pipePIDFile, encoding: .utf8),
               let pipePID = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
            {
                _ = kill(pipePID, SIGKILL)
            }
            try? FileManager.default.removeItem(at: pipePIDFile)
            try? FileManager.default.removeItem(at: ptyMarker)
            try? FileManager.default.removeItem(at: cliURL.deletingLastPathComponent())
        }

        let clock = ContinuousClock()
        let startedAt = clock.now
        let probe = KiroStatusProbe(
            cliBinaryResolver: { cliURL.path },
            usageProbeTimeout: 0.8,
            pipeTimeoutCap: 0.4)

        do {
            _ = try await probe.fetch()
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case KiroStatusProbeError.timeout = error else { return false }
                return true
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }

        #expect(startedAt.duration(to: clock.now) < .seconds(2))
        #expect(!FileManager.default.fileExists(atPath: ptyMarker.path))
        let pipePIDText = try String(contentsOf: pipePIDFile, encoding: .utf8)
        let pipePID = try #require(pid_t(pipePIDText.trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(kill(pipePID, 0) == -1)
    }

    @Test
    func fetch_preserves_account_info_when_account_probe_succeeds() async throws {
        let cliURL = try self.makeCLI(
            """
            #!/bin/sh
            if [ "$1" = "whoami" ]; then
              printf 'Logged in with Google\\nEmail: person@example.com\\n'
              exit 0
            fi

            if [ "$1" = "chat" ] && [ "$3" = "/usage" ]; then
              printf 'Estimated Usage | resets on 2026-06-01 | KIRO FREE\\n'
              printf 'Credits (12.50 of 50 covered in plan)\\n'
              printf '████████████████████ 25%%\\n'
              exit 0
            fi

            if [ "$1" = "chat" ] && [ "$3" = "/context" ]; then
              exit 0
            fi

            exit 1
            """)
        defer { try? FileManager.default.removeItem(at: cliURL.deletingLastPathComponent()) }

        let probe = KiroStatusProbe(cliBinaryResolver: { cliURL.path })
        let snapshot = try await probe.fetch()

        #expect(snapshot.accountEmail == "person@example.com")
        #expect(snapshot.authMethod == "Google")
    }
}

extension KiroStatusProbeTests {
    @Test
    func fetch_supports_kiro_cli_that_only_completes_through_pipes() async throws {
        let cliURL = try self.makeCLI(
            """
            #!/bin/sh
            if [ -t 1 ]; then
              sleep 30
              exit 1
            fi

            if [ "$1" = "whoami" ]; then
              printf 'Logged in with Google\nEmail: person@example.com\n'
              exit 0
            fi

            if [ "$1" = "chat" ] && [ "$3" = "/usage" ]; then
              printf 'Estimated Usage | resets on 2026-06-01 | KIRO FREE\n'
              printf 'Credits (12.50 of 50 covered in plan)\n'
              printf '████████████████████ 25%%\n'
              exit 0
            fi

            if [ "$1" = "chat" ] && [ "$3" = "/context" ]; then
              exit 0
            fi

            exit 1
            """)
        defer { try? FileManager.default.removeItem(at: cliURL.deletingLastPathComponent()) }

        let probe = KiroStatusProbe(cliBinaryResolver: { cliURL.path })
        let snapshot = try await probe.fetch()

        #expect(snapshot.planName == "KIRO FREE")
        #expect(snapshot.creditsUsed == 12.50)
        #expect(snapshot.accountEmail == "person@example.com")
    }

    @Test
    func slow_pipe_remains_viable_after_PTY_fallback_starts() async throws {
        let cliURL = try self.makeCLI(
            """
            #!/bin/sh
            if [ -t 1 ]; then
              exit 97
            fi
            if [ "$1" = "whoami" ]; then
              printf 'Logged in with Google\nEmail: person@example.com\n'
              exit 0
            fi
            if [ "$1" = "chat" ] && [ "$3" = "/usage" ]; then
              sleep 1
              printf 'Estimated Usage | resets on 2026-06-01 | KIRO FREE\n'
              printf 'Credits (12.50 of 50 covered in plan)\n'
              printf '████████████████████ 25%%\n'
              exit 0
            fi
            if [ "$1" = "chat" ] && [ "$3" = "/context" ]; then
              exit 0
            fi
            exit 1
            """)
        defer { try? FileManager.default.removeItem(at: cliURL.deletingLastPathComponent()) }

        let snapshot = try await KiroStatusProbe(
            cliBinaryResolver: { cliURL.path },
            usageProbeTimeout: 2,
            pipeTimeoutCap: 0.2).fetch()

        #expect(snapshot.planName == "KIRO FREE")
    }

    @Test
    func fetch_falls_back_to_PTY_for_older_kiro_cli() async throws {
        let cliURL = try self.makeCLI(
            """
            #!/bin/sh
            if [ ! -t 1 ]; then
              sleep 30
              exit 1
            fi

            if [ "$1" = "whoami" ]; then
              printf 'Logged in with Google\nEmail: person@example.com\n'
              exit 0
            fi

            if [ "$1" = "chat" ] && [ "$3" = "/usage" ]; then
              printf 'Estimated Usage | resets on 2026-06-01 | KIRO FREE\n'
              printf 'Credits (12.50 of 50 covered in plan)\n'
              printf '████████████████████ 25%%\n'
              exit 0
            fi

            if [ "$1" = "chat" ] && [ "$3" = "/context" ]; then
              exit 0
            fi

            exit 1
            """)
        defer { try? FileManager.default.removeItem(at: cliURL.deletingLastPathComponent()) }

        let probe = KiroStatusProbe(
            cliBinaryResolver: { cliURL.path },
            pipeTimeoutCap: 0.2)
        let snapshot = try await probe.fetch()

        #expect(snapshot.planName == "KIRO FREE")
        #expect(snapshot.creditsUsed == 12.50)
        #expect(snapshot.accountEmail == "person@example.com")
    }

    @Test
    func fetch_falls_back_to_PTY_after_incomplete_pipe_output() async throws {
        let cliURL = try self.makeCLI(
            """
            #!/bin/sh
            if [ ! -t 1 ]; then
              if [ "$1" = "whoami" ]; then
                printf 'Logged in with Google\nEmail: person@example.com\n'
                exit 0
              fi
              if [ "$1" = "chat" ] && [ "$3" = "/usage" ]; then
                printf 'Plan: loading...\n'
                exit 0
              fi
              if [ "$1" = "chat" ] && [ "$3" = "/context" ]; then
                exit 0
              fi
            fi

            if [ "$1" = "whoami" ]; then
              printf 'Logged in with Google\nEmail: person@example.com\n'
              exit 0
            fi
            if [ "$1" = "chat" ] && [ "$3" = "/usage" ]; then
              printf 'Estimated Usage | resets on 2026-06-01 | KIRO FREE\n'
              printf 'Credits (12.50 of 50 covered in plan)\n'
              printf '████████████████████ 25%%\n'
              exit 0
            fi
            if [ "$1" = "chat" ] && [ "$3" = "/context" ]; then
              exit 0
            fi
            exit 1
            """)
        defer { try? FileManager.default.removeItem(at: cliURL.deletingLastPathComponent()) }

        let snapshot = try await KiroStatusProbe(cliBinaryResolver: { cliURL.path }).fetch()

        #expect(snapshot.planName == "KIRO FREE")
        #expect(snapshot.creditsUsed == 12.50)
    }

    @Test
    func pipe_cleanup_finishes_before_PTY_fallback_starts() async throws {
        let childPIDFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-kiro-pipe-child-\(UUID().uuidString).pid")
        let ptyMarker = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-kiro-pty-fallback-\(UUID().uuidString).started")
        let cliURL = try self.makeCLI(
            """
            #!/bin/sh
            if [ "$1" = "whoami" ]; then
              printf 'Logged in with Google\nEmail: person@example.com\n'
              exit 0
            fi
            if [ "$1" = "chat" ] && [ "$3" = "/usage" ]; then
              if [ ! -t 1 ]; then
                (trap '' TERM; while true; do sleep 1; done) &
                child=$!
                printf '%s\n' "$child" > '\(childPIDFile.path)'
                printf 'Plan: loading...\n'
                exit 0
              fi
              if test -s '\(childPIDFile.path)' && kill -0 "$(cat '\(childPIDFile.path)')" 2>/dev/null; then
                printf 'pipe child still running\n' >&2
                exit 97
              fi
              : > '\(ptyMarker.path)'
              printf 'Estimated Usage | resets on 2026-06-01 | KIRO FREE\n'
              printf 'Credits (12.50 of 50 covered in plan)\n'
              printf '████████████████████ 25%%\n'
              exit 0
            fi
            if [ "$1" = "chat" ] && [ "$3" = "/context" ]; then
              exit 0
            fi
            exit 1
            """)
        defer {
            if let text = try? String(contentsOf: childPIDFile, encoding: .utf8),
               let childPID = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
            {
                _ = kill(childPID, SIGKILL)
            }
            try? FileManager.default.removeItem(at: childPIDFile)
            try? FileManager.default.removeItem(at: ptyMarker)
            try? FileManager.default.removeItem(at: cliURL.deletingLastPathComponent())
        }

        let snapshot = try await KiroStatusProbe(cliBinaryResolver: { cliURL.path }).fetch()

        #expect(snapshot.planName == "KIRO FREE")
        #expect(FileManager.default.fileExists(atPath: ptyMarker.path))
        let childPIDText = try String(contentsOf: childPIDFile, encoding: .utf8)
        let childPID = try #require(pid_t(childPIDText.trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(kill(childPID, 0) == -1)
    }

    @Test
    func shutdown_registry_terminates_an_active_pipe_probe() async throws {
        let pipePIDFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-kiro-shutdown-\(UUID().uuidString).pid")
        let cliURL = try self.makeCLI(
            """
            #!/bin/sh
            if [ "$1" = "whoami" ]; then
              printf 'Logged in with Google\nEmail: person@example.com\n'
              exit 0
            fi
            if [ "$1" = "chat" ] && [ "$3" = "/usage" ]; then
              if [ -t 1 ]; then
                exit 97
              fi
              printf '%s\n' "$$" > '\(pipePIDFile.path)'
              printf 'Plan: loading...\n'
              trap '' TERM
              while true; do sleep 1; done
            fi
            if [ "$1" = "chat" ] && [ "$3" = "/context" ]; then
              exit 0
            fi
            exit 1
            """)

        let registry = KiroTestProcessRegistry()
        let task = Task {
            try await KiroStatusProbe(
                cliBinaryResolver: { cliURL.path },
                pipeProcessRegistry: registry.dependencies).fetch()
        }
        defer {
            task.cancel()
            if let text = try? String(contentsOf: pipePIDFile, encoding: .utf8),
               let pipePID = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
            {
                _ = kill(pipePID, SIGKILL)
            }
            try? FileManager.default.removeItem(at: pipePIDFile)
            try? FileManager.default.removeItem(at: cliURL.deletingLastPathComponent())
        }

        try await waitForFile(pipePIDFile)
        let pipePIDText = try String(contentsOf: pipePIDFile, encoding: .utf8)
        let pipePID = try #require(pid_t(pipePIDText.trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(registry.isRegistered(pipePID))

        let clock = ContinuousClock()
        let shutdownStartedAt = clock.now
        registry.terminate(pipePID)
        await #expect(throws: (any Error).self) {
            _ = try await task.value
        }

        #expect(shutdownStartedAt.duration(to: clock.now) < .seconds(2))
        #expect(!registry.isRegistered(pipePID))
        #expect(registry.didUnregister(pipePID))
        #expect(kill(pipePID, 0) == -1)
    }

    @Test
    func fetch_combines_pipe_stdout_with_stderr_warnings() async throws {
        let cliURL = try self.makeCLI(
            """
            #!/bin/sh
            if [ -t 1 ]; then
              exit 91
            fi
            if [ "$1" = "whoami" ]; then
              printf 'Logged in with Google\nEmail: person@example.com\n'
              printf 'warning: cached session\n' >&2
              exit 0
            fi
            if [ "$1" = "chat" ] && [ "$3" = "/usage" ]; then
              printf 'Estimated Usage | resets on 2026-06-01 | KIRO FREE\n'
              printf 'Credits (12.50 of 50 covered in plan)\n'
              printf '████████████████████ 25%%\n'
              printf 'warning: telemetry unavailable\n' >&2
              exit 0
            fi
            if [ "$1" = "chat" ] && [ "$3" = "/context" ]; then
              exit 0
            fi
            exit 1
            """)
        defer { try? FileManager.default.removeItem(at: cliURL.deletingLastPathComponent()) }

        let snapshot = try await KiroStatusProbe(cliBinaryResolver: { cliURL.path }).fetch()

        #expect(snapshot.planName == "KIRO FREE")
        #expect(snapshot.accountEmail == "person@example.com")
        #expect(snapshot.authMethod == "Google")
    }

    @Test
    func fetch_falls_back_to_PTY_after_pipe_requires_a_terminal() async throws {
        let cliURL = try self.makeCLI(
            """
            #!/bin/sh
            if [ ! -t 1 ]; then
              printf 'terminal required\n' >&2
              exit 2
            fi
            if [ "$1" = "whoami" ]; then
              printf 'Logged in with Google\nEmail: person@example.com\n'
              exit 0
            fi
            if [ "$1" = "chat" ] && [ "$3" = "/usage" ]; then
              printf 'Estimated Usage | resets on 2026-06-01 | KIRO FREE\n'
              printf 'Credits (12.50 of 50 covered in plan)\n'
              printf '████████████████████ 25%%\n'
              exit 0
            fi
            if [ "$1" = "chat" ] && [ "$3" = "/context" ]; then
              printf 'Context window: 7.5%% used (estimated)\n'
              printf '█ Context files 2.5%% (estimated)\n'
              exit 0
            fi
            exit 1
            """)
        defer { try? FileManager.default.removeItem(at: cliURL.deletingLastPathComponent()) }

        let snapshot = try await KiroStatusProbe(cliBinaryResolver: { cliURL.path }).fetch()

        #expect(snapshot.planName == "KIRO FREE")
        #expect(snapshot.accountEmail == "person@example.com")
        #expect(snapshot.contextUsage?.totalPercentUsed == 7.5)
        #expect(snapshot.contextUsage?.contextFilesPercent == 2.5)
    }

    @Test
    func pipe_auth_failure_on_stderr_remains_authoritative() async throws {
        let cliURL = try self.makeCLI(
            """
            #!/bin/sh
            if [ ! -t 1 ]; then
              printf 'Opening browser...\n'
              printf 'Not logged in\n' >&2
              exit 1
            fi
            if [ "$1" = "whoami" ]; then
              printf 'Logged in with Google\nEmail: person@example.com\n'
              exit 0
            fi
            if [ "$1" = "chat" ] && [ "$3" = "/usage" ]; then
              printf 'Estimated Usage | resets on 2026-06-01 | KIRO FREE\n'
              printf 'Credits (12.50 of 50 covered in plan)\n'
              printf '████████████████████ 25%%\n'
              exit 0
            fi
            if [ "$1" = "chat" ] && [ "$3" = "/context" ]; then
              exit 0
            fi
            exit 1
            """)
        defer { try? FileManager.default.removeItem(at: cliURL.deletingLastPathComponent()) }

        do {
            _ = try await KiroStatusProbe(cliBinaryResolver: { cliURL.path }).fetch()
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case KiroStatusProbeError.notLoggedIn = error else { return false }
                return true
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func fetch_rejects_account_markers_from_failed_whoami() async throws {
        let cliURL = try self.makeCLI(
            """
            #!/bin/sh
            if [ "$1" = "whoami" ]; then
              printf 'Logged in with Google\nEmail: person@example.com\n'
              exit 23
            fi

            if [ "$1" = "chat" ] && [ "$3" = "/usage" ]; then
              printf 'Estimated Usage | resets on 2026-06-01 | KIRO FREE\n'
              printf 'Credits (12.50 of 50 covered in plan)\n'
              printf '████████████████████ 25%%\n'
              exit 0
            fi

            if [ "$1" = "chat" ] && [ "$3" = "/context" ]; then
              exit 0
            fi

            exit 1
            """)
        defer { try? FileManager.default.removeItem(at: cliURL.deletingLastPathComponent()) }

        let snapshot = try await KiroStatusProbe(cliBinaryResolver: { cliURL.path }).fetch()

        #expect(snapshot.accountEmail == nil)
        #expect(snapshot.authMethod == nil)
    }

    @Test
    func fetch_rejects_valid_looking_usage_from_failed_command() async throws {
        let cliURL = try self.makeCLI(
            """
            #!/bin/sh
            if [ -t 1 ]; then
              if [ "$1" = "whoami" ]; then
                printf 'Logged in with Google\nEmail: person@example.com\n'
                exit 0
              fi
              if [ "$1" = "chat" ] && [ "$3" = "/usage" ]; then
                printf 'Estimated Usage | resets on 2026-06-01 | KIRO FREE\n'
                printf 'Credits (12.50 of 50 covered in plan)\n'
                printf '████████████████████ 25%%\n'
                exit 0
              fi
            fi

            if [ "$1" = "whoami" ]; then
              printf 'Logged in with Google\nEmail: person@example.com\n'
              exit 0
            fi

            if [ "$1" = "chat" ] && [ "$3" = "/usage" ]; then
              printf 'Estimated Usage | resets on 2026-06-01 | KIRO FREE\n'
              printf 'Credits (12.50 of 50 covered in plan)\n'
              printf '████████████████████ 25%%\n'
              exit 23
            fi

            if [ "$1" = "chat" ] && [ "$3" = "/context" ]; then
              exit 0
            fi

            exit 1
            """)
        defer { try? FileManager.default.removeItem(at: cliURL.deletingLastPathComponent()) }

        let probe = KiroStatusProbe(cliBinaryResolver: { cliURL.path })
        do {
            _ = try await probe.fetch()
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case KiroStatusProbeError.cliFailed = error else { return false }
                return true
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func fetch_preserves_not_logged_in_when_usage_fails_without_auth_detail() async throws {
        let cliURL = try self.makeCLI(
            """
            #!/bin/sh
            if [ "$1" = "whoami" ]; then
              printf 'Not logged in\\n'
              exit 1
            fi

            if [ "$1" = "chat" ] && [ "$3" = "/usage" ]; then
              exit 1
            fi

            if [ "$1" = "chat" ] && [ "$3" = "/context" ]; then
              exit 0
            fi

            exit 1
            """)
        defer { try? FileManager.default.removeItem(at: cliURL.deletingLastPathComponent()) }

        let probe = KiroStatusProbe(cliBinaryResolver: { cliURL.path })
        do {
            _ = try await probe.fetch()
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case KiroStatusProbeError.notLoggedIn = error else { return false }
                return true
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func fetch_preserves_not_logged_in_when_whoami_idles_after_login_marker() async throws {
        let cliURL = try self.makeCLI(
            """
            #!/bin/sh
            if [ "$1" = "whoami" ]; then
              printf 'Not logged in\n'
              sleep 5
              exit 1
            fi

            if [ "$1" = "chat" ] && [ "$3" = "/usage" ]; then
              exit 1
            fi

            if [ "$1" = "chat" ] && [ "$3" = "/context" ]; then
              exit 0
            fi

            exit 1
            """)
        defer { try? FileManager.default.removeItem(at: cliURL.deletingLastPathComponent()) }

        let probe = KiroStatusProbe(cliBinaryResolver: { cliURL.path }, accountProbeTimeout: 2)
        do {
            _ = try await probe.fetch()
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case KiroStatusProbeError.notLoggedIn = error else { return false }
                return true
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func fetch_preserves_not_logged_in_when_usage_output_cannot_be_parsed() async throws {
        let cliURL = try self.makeCLI(
            """
            #!/bin/sh
            if [ "$1" = "whoami" ]; then
              printf 'Not logged in\\n'
              exit 1
            fi

            if [ "$1" = "chat" ] && [ "$3" = "/usage" ]; then
              exit 0
            fi

            if [ "$1" = "chat" ] && [ "$3" = "/context" ]; then
              exit 0
            fi

            exit 1
            """)
        defer { try? FileManager.default.removeItem(at: cliURL.deletingLastPathComponent()) }

        let probe = KiroStatusProbe(cliBinaryResolver: { cliURL.path })
        do {
            _ = try await probe.fetch()
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case KiroStatusProbeError.notLoggedIn = error else { return false }
                return true
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func fetch_cancellation_during_context_probe_is_preserved() async throws {
        let contextStarted = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-kiro-context-\(UUID().uuidString).started")
        let cliURL = try self.makeCLI(
            """
            #!/bin/sh
            if [ "$1" = "whoami" ]; then
              printf 'Logged in with Google\nEmail: person@example.com\n'
              exit 0
            fi

            if [ "$1" = "chat" ] && [ "$3" = "/usage" ]; then
              printf 'Estimated Usage | resets on 2026-06-01 | KIRO FREE\n'
              printf 'Credits (12.50 of 50 covered in plan)\n'
              printf '████████████████████ 25%%\n'
              exit 0
            fi

            if [ "$1" = "chat" ] && [ "$3" = "/context" ]; then
              : > '\(contextStarted.path)'
              trap '' TERM
              while true; do sleep 1; done
            fi

            exit 1
            """)
        defer {
            try? FileManager.default.removeItem(at: cliURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: contextStarted)
        }

        let probe = KiroStatusProbe(cliBinaryResolver: { cliURL.path })
        let task = Task { try await probe.fetch() }
        defer { task.cancel() }

        try await waitForFile(contextStarted)

        let cancelledAt = Date()
        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(Date().timeIntervalSince(cancelledAt) < 4)
    }

    @Test
    func cancellation_during_pipe_cleanup_wins_over_an_expired_context_deadline() async throws {
        let cleanupStarted = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-kiro-cleanup-\(UUID().uuidString).started")
        let unblockCleanup = DispatchSemaphore(value: 0)
        let registry = KiroTestProcessRegistry(
            blockOnUnregister: 3,
            blockStartedURL: cleanupStarted,
            unblock: unblockCleanup)
        let cliURL = try self.makeCLI(
            """
            #!/bin/sh
            if [ "$1" = "whoami" ]; then
              printf 'Logged in with Google\nEmail: person@example.com\n'
              exit 0
            fi
            if [ "$1" = "chat" ] && [ "$3" = "/usage" ]; then
              printf 'Estimated Usage | resets on 2026-06-01 | KIRO FREE\n'
              printf 'Credits (12.50 of 50 covered in plan)\n'
              printf '████████████████████ 25%%\n'
              exit 0
            fi
            if [ "$1" = "chat" ] && [ "$3" = "/context" ]; then
              exit 0
            fi
            exit 1
            """)
        defer {
            unblockCleanup.signal()
            try? FileManager.default.removeItem(at: cleanupStarted)
            try? FileManager.default.removeItem(at: cliURL.deletingLastPathComponent())
        }

        let probe = KiroStatusProbe(
            cliBinaryResolver: { cliURL.path },
            contextProbeTimeout: 0.2,
            pipeProcessRegistry: registry.dependencies)
        let task = Task { try await probe.fetch() }
        defer { task.cancel() }

        try await waitForFile(cleanupStarted)
        task.cancel()
        try await Task.sleep(for: .milliseconds(250))
        unblockCleanup.signal()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test
    func fetch_cancellation_while_waiting_for_account_probe_is_preserved() async throws {
        let accountStarted = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-kiro-account-\(UUID().uuidString).started")
        let cliURL = try self.makeCLI(
            """
            #!/bin/sh
            if [ "$1" = "whoami" ]; then
              : > '\(accountStarted.path)'
              trap '' TERM
              while true; do sleep 1; done
            fi

            if [ "$1" = "chat" ] && [ "$3" = "/usage" ]; then
              printf 'Estimated Usage | resets on 2026-06-01 | KIRO FREE\\n'
              printf 'Credits (12.50 of 50 covered in plan)\\n'
              printf '████████████████████ 25%%\\n'
              exit 0
            fi

            if [ "$1" = "chat" ] && [ "$3" = "/context" ]; then
              exit 0
            fi

            exit 1
            """)
        defer {
            try? FileManager.default.removeItem(at: cliURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: accountStarted)
        }

        let probe = KiroStatusProbe(cliBinaryResolver: { cliURL.path })
        let task = Task { try await probe.fetch() }
        defer { task.cancel() }

        try await waitForFile(accountStarted)

        let cancelledAt = Date()
        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(Date().timeIntervalSince(cancelledAt) < 4)
    }

    @Test
    func fetch_returns_promptly_when_usage_helper_spawns_a_detached_child() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-kiro-pipe-\(UUID().uuidString)", isDirectory: true)
        let childPIDFile = root.appendingPathComponent("child.pid")
        let cliURL = root.appendingPathComponent("kiro-cli")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        defer {
            if let text = try? String(contentsOf: childPIDFile, encoding: .utf8),
               let childPID = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
            {
                _ = kill(childPID, SIGKILL)
            }
        }

        let script = """
        #!/bin/bash
        set -e
        if [ "$1" = "whoami" ]; then
          printf 'Logged in with Google\\nEmail: person@example.com\\n'
          exit 0
        fi

        if [ "$1" = "chat" ] && [ "$3" = "/usage" ]; then
          /usr/bin/python3 -c '
        import os
        import subprocess
        import sys

        ready_read, ready_write = os.pipe()
        child = subprocess.Popen(
            [
                sys.executable,
                "-c",
                "import os,signal,sys,time; "
                "signal.signal(signal.SIGHUP, signal.SIG_IGN); "
                "signal.signal(signal.SIGTERM, signal.SIG_IGN); "
                "handle=open(sys.argv[1], \\\"w\\\"); handle.write(str(os.getpid())); handle.close(); "
                "os.write(int(sys.argv[2]), b\\\"1\\\"); os.close(int(sys.argv[2])); time.sleep(30)",
                os.environ["CODEXBAR_TEST_CHILD_PID_FILE"],
                str(ready_write),
            ],
            start_new_session=True,
            pass_fds=(ready_write,),
        )
        os.close(ready_write)
        if os.read(ready_read, 1) != b"1":
            raise RuntimeError("detached helper exited before signaling readiness")
        os.close(ready_read)
        '
          test -s "$CODEXBAR_TEST_CHILD_PID_FILE"
          printf 'Estimated Usage | resets on 2026-06-01 | KIRO FREE\\n'
          printf 'Credits (12.50 of 50 covered in plan)\\n'
          printf '████████████████████ 25%%\\n'
          exit 0
        fi

        if [ "$1" = "chat" ] && [ "$3" = "/context" ]; then
          printf 'Context window: 40%% used\\n'; exit 0
        fi

        exit 1
        """
        try script.write(to: cliURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cliURL.path)

        let previousPIDFile = ProcessInfo.processInfo.environment["CODEXBAR_TEST_CHILD_PID_FILE"]
        setenv("CODEXBAR_TEST_CHILD_PID_FILE", childPIDFile.path, 1)
        defer {
            if let previousPIDFile {
                setenv("CODEXBAR_TEST_CHILD_PID_FILE", previousPIDFile, 1)
            } else {
                unsetenv("CODEXBAR_TEST_CHILD_PID_FILE")
            }
        }

        let probe = KiroStatusProbe(cliBinaryResolver: { cliURL.path })
        let start = Date()
        let snapshot = try await probe.fetch()
        let elapsed = Date().timeIntervalSince(start)

        let childPIDText = try String(contentsOf: childPIDFile, encoding: .utf8)
        let childPID = try #require(pid_t(childPIDText.trimmingCharacters(in: .whitespacesAndNewlines)))
        for _ in 0..<50 where kill(childPID, 0) == 0 {
            try await Task.sleep(for: .milliseconds(20))
        }

        // Keep the optional context probe parseable so this timing check covers detached-child cleanup.
        #expect(snapshot.planName == "KIRO FREE")
        #expect(snapshot.creditsUsed == 12.50 && snapshot.contextUsage?.totalPercentUsed == 40)
        #expect(elapsed < 8, "Kiro usage capture should return promptly even with a detached child, took \(elapsed)s")
        #expect(kill(childPID, 0) == -1)
    }

    @Test
    func tty_runner_hard_stops_a_process_that_ignores_SIGTERM() throws {
        let cliURL = try self.makeCLI(
            """
            #!/bin/sh
            trap '' TERM
            printf 'partial output\\n'
            while true; do sleep 1; done
            """)
        defer { try? FileManager.default.removeItem(at: cliURL.deletingLastPathComponent()) }

        let start = Date()
        let result = try TTYCommandRunner().run(
            binary: cliURL.path,
            send: "",
            options: .init(timeout: 2, idleTimeout: 0.1))
        let elapsed = Date().timeIntervalSince(start)

        #expect(result.completion == .idleTimeout)
        #expect(result.text.contains("partial output"))
        #expect(elapsed < 3, "Ignored SIGTERM should escalate to SIGKILL, took \(elapsed)s")
    }

    @Test
    func tty_runner_kills_a_pipe_holder_that_escapes_the_process_group() async throws {
        let childPIDFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-kiro-escaped-\(UUID().uuidString).pid")
        let cliURL = try self.makeCLI(
            """
            #!/usr/bin/python3
            import subprocess
            import sys
            import time

            child = subprocess.Popen(
                [
                    sys.executable,
                    "-c",
                    "import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(30)",
                ],
                start_new_session=True,
            )
            with open(sys.argv[1], "w") as handle:
                handle.write(str(child.pid))
            print("partial output", flush=True)
            time.sleep(30)
            """)
        defer {
            try? FileManager.default.removeItem(at: cliURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: childPIDFile)
        }

        let result = try TTYCommandRunner().run(
            binary: cliURL.path,
            send: "",
            options: .init(
                timeout: 2,
                idleTimeout: 0.1,
                extraArgs: [childPIDFile.path]))

        #expect(result.completion == .idleTimeout)
        #expect(result.text.contains("partial output"))

        let childPIDText = try String(contentsOf: childPIDFile, encoding: .utf8)
        let childPID = try #require(pid_t(childPIDText.trimmingCharacters(in: .whitespacesAndNewlines)))
        defer { _ = kill(childPID, SIGKILL) }

        let cleanupDeadline = Date().addingTimeInterval(1)
        while kill(childPID, 0) == 0, Date() < cleanupDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(kill(childPID, 0) == -1)
    }

    @Test
    func tty_runner_cleans_a_same_group_helper_after_normal_exit() async throws {
        let childPIDFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-kiro-normal-exit-\(UUID().uuidString).pid")
        let cliURL = try self.makeCLI(
            """
            #!/usr/bin/python3
            import os
            import signal
            import sys
            import time

            child = os.fork()
            if child == 0:
                os.close(1)
                os.close(2)
                signal.signal(signal.SIGTERM, signal.SIG_IGN)
                with open(sys.argv[1], "w") as handle:
                    handle.write(str(os.getpid()))
                time.sleep(30)
                os._exit(0)

            while not os.path.exists(sys.argv[1]):
                time.sleep(0.01)
            print("parent complete", flush=True)
            os._exit(0)
            """)
        defer {
            try? FileManager.default.removeItem(at: cliURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: childPIDFile)
        }

        let result = try TTYCommandRunner().run(
            binary: cliURL.path,
            send: "",
            options: .init(timeout: 2, extraArgs: [childPIDFile.path]))

        #expect(result.completion == .processExited(status: 0))
        #expect(result.text.contains("parent complete"))

        let childPIDText = try String(contentsOf: childPIDFile, encoding: .utf8)
        let childPID = try #require(pid_t(childPIDText.trimmingCharacters(in: .whitespacesAndNewlines)))
        defer { _ = kill(childPID, SIGKILL) }

        let cleanupDeadline = Date().addingTimeInterval(1)
        while kill(childPID, 0) == 0, Date() < cleanupDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(kill(childPID, 0) == -1)
    }

    @Test
    func tty_runner_preserves_completed_no_output_failure_status() throws {
        let cliURL = try self.makeCLI(
            """
            #!/bin/sh
            exit 23
            """)
        defer { try? FileManager.default.removeItem(at: cliURL.deletingLastPathComponent()) }

        let result = try TTYCommandRunner().run(
            binary: cliURL.path,
            send: "",
            options: .init(timeout: 2, returnOnEmptyProcessExit: true))

        #expect(result.text.isEmpty)
        #expect(result.completion == .processExited(status: 23))
    }

    @Test
    func tty_runner_cancellation_terminates_the_process() async throws {
        let pidFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-kiro-cancel-\(UUID().uuidString).pid")
        let cliURL = try self.makeCLI(
            """
            #!/bin/sh
            printf '%s\\n' "$$" > "$1"
            trap '' TERM
            while true; do sleep 1; done
            """)
        defer {
            try? FileManager.default.removeItem(at: cliURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: pidFile)
        }

        let task = Task {
            try TTYCommandRunner().run(
                binary: cliURL.path,
                send: "",
                options: .init(timeout: 20, extraArgs: [pidFile.path]))
        }
        defer { task.cancel() }

        var capturedProcessID: pid_t?
        for _ in 0..<100 {
            if let text = try? String(contentsOf: pidFile, encoding: .utf8) {
                capturedProcessID = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let processID = try #require(capturedProcessID)
        defer { _ = kill(processID, SIGKILL) }

        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(kill(processID, 0) == -1)
    }
}

extension KiroStatusProbeTests {
    // MARK: - Happy Path Parsing

    @Test
    func parses_basic_usage_output() throws {
        let output = """
        | KIRO FREE                                          |
        ████████████████████████████████████████████████████ 25%
        (12.50 of 50 covered in plan), resets on 01/15
        """

        let probe = KiroStatusProbe()
        let snapshot = try probe.parse(output: output)

        #expect(snapshot.planName == "KIRO FREE")
        #expect(snapshot.displayPlanName == "Kiro Free")
        #expect(snapshot.creditsPercent == 25)
        #expect(snapshot.creditsUsed == 12.50)
        #expect(snapshot.creditsTotal == 50)
        #expect(snapshot.bonusCreditsUsed == nil)
        #expect(snapshot.bonusCreditsTotal == nil)
        #expect(snapshot.bonusExpiryDays == nil)
        #expect(snapshot.resetsAt != nil)
    }

    private func makeCLI(_ script: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-kiro-cli-\(UUID().uuidString)", isDirectory: true)
        let cliURL = root.appendingPathComponent("kiro-cli")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try script.write(to: cliURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cliURL.path)
        return cliURL
    }

    @Test
    func parses_output_with_bonus_credits() throws {
        let output = """
        | KIRO PRO                                           |
        ████████████████████████████████████████████████████ 80%
        (40.00 of 50 covered in plan), resets on 02/01
        Bonus credits: 5.00/10 credits used, expires in 7 days
        """

        let probe = KiroStatusProbe()
        let snapshot = try probe.parse(output: output)

        #expect(snapshot.planName == "KIRO PRO")
        #expect(snapshot.displayPlanName == "Kiro Pro")
        #expect(snapshot.creditsPercent == 80)
        #expect(snapshot.creditsUsed == 40.00)
        #expect(snapshot.creditsTotal == 50)
        #expect(snapshot.bonusCreditsUsed == 5.00)
        #expect(snapshot.bonusCreditsTotal == 10)
        #expect(snapshot.bonusExpiryDays == 7)
    }

    @Test
    func parses_output_without_percent_fallbacks_to_credits_ratio() throws {
        let output = """
        | KIRO FREE                                          |
        (12.50 of 50 covered in plan), resets on 01/15
        """

        let probe = KiroStatusProbe()
        let snapshot = try probe.parse(output: output)

        #expect(snapshot.creditsPercent == 25)
    }

    @Test
    func parses_bonus_credits_without_expiry() throws {
        let output = """
        | KIRO FREE                                          |
        ████████████████████████████████████████████████████ 60%
        (30.00 of 50 covered in plan), resets on 04/01
        Bonus credits: 2.00/5 credits used
        """

        let probe = KiroStatusProbe()
        let snapshot = try probe.parse(output: output)

        #expect(snapshot.bonusCreditsUsed == 2.0)
        #expect(snapshot.bonusCreditsTotal == 5.0)
        #expect(snapshot.bonusExpiryDays == nil)
    }

    @Test
    func parses_output_with_ANSI_codes() throws {
        let output = """
        \u{001B}[32m| KIRO FREE                                          |\u{001B}[0m
        \u{001B}[38;5;11m████████████████████████████████████████████████████\u{001B}[0m 50%
        (25.00 of 50 covered in plan), resets on 03/15
        """

        let probe = KiroStatusProbe()
        let snapshot = try probe.parse(output: output)

        #expect(snapshot.planName == "KIRO FREE")
        #expect(snapshot.creditsPercent == 50)
        #expect(snapshot.creditsUsed == 25.00)
        #expect(snapshot.creditsTotal == 50)
    }

    @Test
    func parses_output_with_single_day() throws {
        let output = """
        | KIRO FREE                                          |
        ████████████████████████████████████████████████████ 10%
        (5.00 of 50 covered in plan)
        Bonus credits: 2.00/5 credits used, expires in 1 day
        """

        let probe = KiroStatusProbe()
        let snapshot = try probe.parse(output: output)

        #expect(snapshot.bonusExpiryDays == 1)
    }

    @Test
    func rejects_output_missing_usage_markers() throws {
        let output = """
        | KIRO FREE                                          |
        """

        let probe = KiroStatusProbe()
        #expect(throws: KiroStatusProbeError.self) {
            try probe.parse(output: output)
        }
    }

    // MARK: - New Format (kiro-cli 1.24+, Q Developer)

    @Test
    func parses_Q_developer_managed_plan() throws {
        let output = """
        Plan: Q Developer Pro
        Your plan is managed by admin

        Tip: to see context window usage, run /context
        """

        let probe = KiroStatusProbe()
        let snapshot = try probe.parse(output: output)

        #expect(snapshot.planName == "Q Developer Pro")
        #expect(snapshot.creditsPercent == 0)
        #expect(snapshot.creditsUsed == 0)
        #expect(snapshot.creditsTotal == 0)
        #expect(snapshot.bonusCreditsUsed == nil)
        #expect(snapshot.resetsAt == nil)
    }

    @Test
    func parses_Q_developer_free_plan() throws {
        let output = """
        Plan: Q Developer Free
        Your plan is managed by admin
        """

        let probe = KiroStatusProbe()
        let snapshot = try probe.parse(output: output)

        #expect(snapshot.planName == "Q Developer Free")
        #expect(snapshot.creditsPercent == 0)
    }

    @Test
    func parses_new_format_with_ANSI_codes() throws {
        let output = """
        \u{001B}[38;5;141mPlan: Q Developer Pro\u{001B}[0m
        Your plan is managed by admin
        """

        let probe = KiroStatusProbe()
        let snapshot = try probe.parse(output: output)

        #expect(snapshot.planName == "Q Developer Pro")
    }

    @Test
    func rejects_header_only_new_format_without_managed_marker() {
        let output = """
        Plan: Q Developer Pro
        Tip: to see context window usage, run /context
        """

        let probe = KiroStatusProbe()
        #expect(throws: KiroStatusProbeError.self) {
            try probe.parse(output: output)
        }
    }

    @Test
    func preserves_parsed_usage_for_managed_plan_with_metrics() throws {
        let output = """
        Plan: Q Developer Enterprise
        Your plan is managed by admin
        ████████████████████████████████████████████████████ 40%
        (20.00 of 50 covered in plan), resets on 03/15
        """

        let probe = KiroStatusProbe()
        let snapshot = try probe.parse(output: output)

        #expect(snapshot.planName == "Q Developer Enterprise")
        #expect(snapshot.creditsPercent == 40)
        #expect(snapshot.creditsUsed == 20)
        #expect(snapshot.creditsTotal == 50)
        #expect(snapshot.resetsAt != nil)
    }

    @Test
    func parses_kiro_cli_two_usage_format() throws {
        let output = """
        \u{001B}[1mEstimated Usage\u{001B}[0m | resets on 2026-06-01 | \u{001B}[mKIRO FREE\u{001B}[0m

        🎁 Bonus credits: 45.53/2000 credits used, expires in 19 days

        \u{001B}[1mCredits\u{001B}[0m (0.17 of 50 covered in plan)
        ████████████████████████████████████████████████████████████████████████████████ 0%

        Overages: \u{001B}[1mDisabled\u{001B}[0m

        To manage your plan or configure overages navigate to https://app.kiro.dev/account/usage
        """

        let probe = KiroStatusProbe()
        let snapshot = try probe.parse(
            output: output,
            accountEmail: "person@example.com",
            authMethod: "Google")

        #expect(snapshot.planName == "KIRO FREE")
        #expect(snapshot.displayPlanName == "Kiro Free")
        #expect(snapshot.accountEmail == "person@example.com")
        #expect(snapshot.authMethod == "Google")
        #expect(snapshot.creditsUsed == 0.17)
        #expect(snapshot.creditsTotal == 50)
        #expect(snapshot.creditsRemaining == 49.83)
        #expect(snapshot.bonusCreditsUsed == 45.53)
        #expect(snapshot.bonusCreditsTotal == 2000)
        #expect(snapshot.bonusCreditsRemaining == 1954.47)
        #expect(snapshot.bonusExpiryDays == 19)
        #expect(snapshot.overagesStatus == "Disabled")
        #expect(snapshot.manageURL == "https://app.kiro.dev/account/usage")
        #expect(snapshot.resetsAt != nil)
    }

    @Test
    func parses_kiro_overage_credits_and_estimated_cost() throws {
        let output = """
        Estimated Usage | resets on 2026-06-01 | KIRO PRO
        Credits (1000.00 of 1000 covered in plan)
        ████████████████████████████████████████████████████████████████████████████████ 100%

        Overages: Enabled  billed at $0.04 per request
        Credits used: 40.29
        Est. cost: $1.61 USD

        To manage your plan or configure overages navigate to https://app.kiro.dev/account/usage
        """

        let probe = KiroStatusProbe()
        let snapshot = try probe.parse(output: output)

        #expect(snapshot.planName == "KIRO PRO")
        #expect(snapshot.creditsUsed == 1000)
        #expect(snapshot.creditsTotal == 1000)
        #expect(snapshot.overagesStatus == "Enabled  billed at $0.04 per request")
        #expect(snapshot.overageCreditsUsed == 40.29)
        #expect(snapshot.estimatedOverageCostUSD == 1.61)
    }

    @Test
    func parses_context_usage() throws {
        let output = """
        Context window: 1.3% used (estimated)
        ██████████████████████████████████████████████████████████████████████████████ 1.3%

        █ Context files 0.5% (estimated)
        █ Tools 0.8% (estimated)
        █ Kiro responses 0.0% (estimated)
        █ Your prompts 0.0% (estimated)
        """

        let probe = KiroStatusProbe()
        let context = try #require(probe.parseContextUsage(output: output))

        #expect(context.totalPercentUsed == 1.3)
        #expect(context.contextFilesPercent == 0.5)
        #expect(context.toolsPercent == 0.8)
        #expect(context.kiroResponsesPercent == 0)
        #expect(context.promptsPercent == 0)
    }

    // MARK: - Snapshot Conversion

    @Test
    func converts_snapshot_to_usage_snapshot() throws {
        let now = Date()
        let resetDate = try #require(Calendar.current.date(byAdding: .day, value: 7, to: now))

        let snapshot = KiroUsageSnapshot(
            planName: "KIRO PRO",
            creditsUsed: 25.0,
            creditsTotal: 100.0,
            creditsPercent: 25.0,
            bonusCreditsUsed: 5.0,
            bonusCreditsTotal: 20.0,
            bonusExpiryDays: 14,
            resetsAt: resetDate,
            updatedAt: now)

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary?.usedPercent == 25.0)
        #expect(usage.primary?.resetsAt == resetDate)
        #expect(usage.secondary?.usedPercent == 25.0) // 5/20 * 100
        #expect(usage.loginMethod(for: .kiro) == nil)
        #expect(usage.accountOrganization(for: .kiro) == nil)
        #expect(usage.kiroUsage?.displayPlanName == "Kiro Pro")
        #expect(usage.kiroUsage?.creditsRemaining == 75)
    }

    @Test
    func converts_snapshot_without_bonus_credits() {
        let snapshot = KiroUsageSnapshot(
            planName: "KIRO FREE",
            creditsUsed: 10.0,
            creditsTotal: 50.0,
            creditsPercent: 20.0,
            bonusCreditsUsed: nil,
            bonusCreditsTotal: nil,
            bonusExpiryDays: nil,
            resetsAt: nil,
            updatedAt: Date())

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary?.usedPercent == 20.0)
        #expect(usage.secondary == nil)
    }

    // MARK: - Error Cases

    @Test
    func empty_output_throws_parse_error() {
        let probe = KiroStatusProbe()

        #expect(throws: KiroStatusProbeError.self) {
            try probe.parse(output: "")
        }
    }

    @Test
    func warning_output_throws_parse_error() {
        let output = """
        \u{001B}[38;5;11m⚠️  Warning: Could not retrieve usage information from backend
        \u{001B}[38;5;8mError: dispatch failure (io error): an i/o error occurred
        """

        let probe = KiroStatusProbe()

        #expect(throws: KiroStatusProbeError.self) {
            try probe.parse(output: output)
        }
    }

    @Test
    func unrecognized_format_throws_parse_error() {
        // Simulates a CLI format change where none of the expected patterns match
        let output = """
        Welcome to Kiro!
        Your account is active.
        Usage: unknown format
        """

        let probe = KiroStatusProbe()

        do {
            try probe.parse(output: output)
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case let KiroStatusProbeError.parseError(msg) = error else { return false }
                return msg.contains("No recognizable usage patterns")
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func login_prompt_throws_not_logged_in() {
        let output = """
        Failed to initialize auth portal.
        Please try again with: kiro-cli login --use-device-flow
        error: OAuth error: All callback ports are in use.
        """

        let probe = KiroStatusProbe()

        do {
            try probe.parse(output: output)
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case KiroStatusProbeError.notLoggedIn = error else { return false }
                return true
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    // MARK: - WhoAmI Validation

    @Test
    func whoami_not_logged_in_throws() {
        let probe = KiroStatusProbe()

        do {
            try probe.validateWhoAmIOutput(stdout: "Not logged in", stderr: "", terminationStatus: 1)
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case KiroStatusProbeError.notLoggedIn = error else { return false }
                return true
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func whoami_login_required_throws() {
        let probe = KiroStatusProbe()

        do {
            try probe.validateWhoAmIOutput(stdout: "login required", stderr: "", terminationStatus: 1)
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case KiroStatusProbeError.notLoggedIn = error else { return false }
                return true
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func whoami_empty_output_with_zero_status_throws() {
        let probe = KiroStatusProbe()

        do {
            try probe.validateWhoAmIOutput(stdout: "", stderr: "", terminationStatus: 0)
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case KiroStatusProbeError.cliFailed = error else { return false }
                return true
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func whoami_non_zero_status_with_message_throws() {
        let probe = KiroStatusProbe()

        do {
            try probe.validateWhoAmIOutput(stdout: "", stderr: "Connection error", terminationStatus: 1)
            Issue.record("expected an error to be thrown")
        } catch {
            let expectationMatches: Bool = { (error: any Error) -> Bool in
                guard case KiroStatusProbeError.cliFailed = error else { return false }
                return true
            }(error)
            #expect(expectationMatches, "unexpected error: \(error)")
        }
    }

    @Test
    func whoami_success_does_not_throw() throws {
        let probe = KiroStatusProbe()

        let account = try probe.validateWhoAmIOutput(
            stdout: """
            Logged in with Google
            Email: user@example.com
            """,
            stderr: "",
            terminationStatus: 0)

        #expect(account.authMethod == "Google")
        #expect(account.email == "user@example.com")
    }

    @Test
    func whoami_legacy_bare_email_parses_account() throws {
        let probe = KiroStatusProbe()

        let account = try probe.validateWhoAmIOutput(
            stdout: "user@example.com",
            stderr: "",
            terminationStatus: 0)

        #expect(account.authMethod == nil)
        #expect(account.email == "user@example.com")
    }
}

extension KiroStatusProbeTests {
    @Test
    func fetch_cancellation_while_joining_account_after_usage_failure_is_preserved() async throws {
        let accountStarted = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-kiro-failed-usage-account-\(UUID().uuidString).started")
        let cliURL = try self.makeCLI(
            """
            #!/bin/sh
            if [ "$1" = "whoami" ]; then
              : > '\(accountStarted.path)'
              trap '' TERM
              while true; do sleep 1; done
            fi

            if [ "$1" = "chat" ] && [ "$3" = "/usage" ]; then
              exit 1
            fi

            exit 1
            """)
        defer {
            try? FileManager.default.removeItem(at: cliURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: accountStarted)
        }

        let probe = KiroStatusProbe(cliBinaryResolver: { cliURL.path }, accountProbeTimeout: 2.0)
        let task = Task { try await probe.fetch() }
        defer { task.cancel() }

        try await waitForFile(accountStarted)
        try await Task.sleep(for: .milliseconds(300))

        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }
}
