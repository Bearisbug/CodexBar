import Foundation
import Testing
@testable import CodexBar

@MainActor
struct CursorLoginBrowserRoutingTests {
    private static let authURL = URL(string: "https://authenticator.cursor.sh/")!
    private static let cometApplicationURL = URL(fileURLWithPath: "/Applications/Comet.app")
    private static let chromeApplicationURL = URL(fileURLWithPath: "/Applications/Google Chrome.app")
    private static let handlerApplicationURL = URL(fileURLWithPath: "/Applications/Link Router.app")

    @Test
    func supported_handler_is_pinned_for_launch_and_polling() {
        let loginURL = Self.authURL
        var discoveryURLs: [URL] = []
        var chooserCalls = 0

        let resolution = CursorLoginBrowserRouter.resolve(
            loginURL: loginURL,
            handlerApplicationURL: Self.cometApplicationURL,
            applicationURLs: {
                discoveryURLs.append($0)
                return [Self.chromeApplicationURL]
            },
            chooseApplication: { _ in
                chooserCalls += 1
                return Self.chromeApplicationURL
            },
            supportsBrowser: Self.supportsFixtureBrowser)

        #expect(resolution == .route(.init(
            launchURL: loginURL,
            browserApplicationURL: Self.cometApplicationURL)))
        #expect(discoveryURLs.isEmpty)
        #expect(chooserCalls == 0)
    }

    @Test
    func known_handler_with_unavailable_cookie_source_falls_back_to_browser_chooser() {
        var chooserCandidates: [URL] = []
        let resolution = CursorLoginBrowserRouter.resolve(
            loginURL: Self.authURL,
            handlerApplicationURL: Self.cometApplicationURL,
            applicationURLs: { _ in [Self.cometApplicationURL, Self.chromeApplicationURL] },
            chooseApplication: { candidates in
                chooserCandidates = candidates
                return Self.chromeApplicationURL
            },
            supportsBrowser: { applicationURL in
                applicationURL == Self.chromeApplicationURL
            })

        #expect(chooserCandidates == [Self.chromeApplicationURL])
        #expect(resolution == .route(.init(
            launchURL: Self.authURL,
            browserApplicationURL: Self.chromeApplicationURL)))
    }

    @Test
    func unsupported_handler_asks_for_explicit_selection_of_the_sole_supported_application() {
        let loginURL = Self.authURL
        var discoveryURLs: [URL] = []
        var chooserCalls = 0

        let resolution = CursorLoginBrowserRouter.resolve(
            loginURL: loginURL,
            handlerApplicationURL: Self.handlerApplicationURL,
            applicationURLs: {
                discoveryURLs.append($0)
                return [
                    URL(fileURLWithPath: "/Applications/Unsupported.app"),
                    Self.cometApplicationURL,
                ]
            },
            chooseApplication: { candidates in
                chooserCalls += 1
                #expect(candidates == [Self.cometApplicationURL])
                return Self.cometApplicationURL
            },
            supportsBrowser: Self.supportsFixtureBrowser)

        #expect(resolution == .route(.init(
            launchURL: loginURL,
            browserApplicationURL: Self.cometApplicationURL)))
        #expect(discoveryURLs == [loginURL])
        #expect(chooserCalls == 1)
    }

    @Test
    func missing_handler_asks_for_explicit_selection_of_a_sole_supported_application() {
        var chooserCandidates: [URL] = []
        let resolution = CursorLoginBrowserRouter.resolve(
            loginURL: Self.authURL,
            handlerApplicationURL: nil,
            applicationURLs: { _ in [Self.chromeApplicationURL] },
            chooseApplication: {
                chooserCandidates = $0
                return Self.chromeApplicationURL
            },
            supportsBrowser: Self.supportsFixtureBrowser)

        #expect(chooserCandidates == [Self.chromeApplicationURL])
        #expect(resolution == .route(.init(
            launchURL: Self.authURL,
            browserApplicationURL: Self.chromeApplicationURL)))
    }

    @Test
    func multiple_supported_applications_use_the_explicit_selection() {
        var chooserCandidates: [URL] = []
        let resolution = CursorLoginBrowserRouter.resolve(
            loginURL: Self.authURL,
            handlerApplicationURL: Self.handlerApplicationURL,
            applicationURLs: { _ in [
                Self.chromeApplicationURL,
                Self.cometApplicationURL,
                URL(fileURLWithPath: "/Applications/Unsupported.app"),
                Self.cometApplicationURL,
            ] },
            chooseApplication: {
                chooserCandidates = $0
                return Self.chromeApplicationURL
            },
            supportsBrowser: Self.supportsFixtureBrowser)

        #expect(chooserCandidates == [Self.cometApplicationURL, Self.chromeApplicationURL])
        #expect(resolution == .route(.init(
            launchURL: Self.authURL,
            browserApplicationURL: Self.chromeApplicationURL)))
    }

    @Test
    func cancelling_the_explicit_chooser_with_one_candidate_is_distinct_from_unavailable() {
        let resolution = CursorLoginBrowserRouter.resolve(
            loginURL: Self.authURL,
            handlerApplicationURL: Self.handlerApplicationURL,
            applicationURLs: { _ in [Self.cometApplicationURL] },
            chooseApplication: { _ in nil },
            supportsBrowser: Self.supportsFixtureBrowser)

        #expect(resolution == .cancelled)
    }

    @Test
    func no_supported_application_is_unavailable_without_showing_a_chooser() {
        var chooserCalls = 0
        let resolution = CursorLoginBrowserRouter.resolve(
            loginURL: Self.authURL,
            handlerApplicationURL: Self.handlerApplicationURL,
            applicationURLs: { _ in [URL(fileURLWithPath: "/Applications/Unsupported.app")] },
            chooseApplication: { _ in
                chooserCalls += 1
                return Self.cometApplicationURL
            },
            supportsBrowser: Self.supportsFixtureBrowser)

        #expect(resolution == .unavailable)
        #expect(chooserCalls == 0)
    }

    @Test
    func chooser_cannot_return_an_application_outside_the_supported_candidates() {
        let resolution = CursorLoginBrowserRouter.resolve(
            loginURL: Self.authURL,
            handlerApplicationURL: Self.handlerApplicationURL,
            applicationURLs: { _ in [Self.cometApplicationURL, Self.chromeApplicationURL] },
            chooseApplication: { _ in URL(fileURLWithPath: "/Applications/Safari.app") },
            supportsBrowser: Self.supportsFixtureBrowser)

        #expect(resolution == .unavailable)
    }

    @Test
    func candidate_labels_are_stable_and_disambiguate_duplicate_application_names() {
        let applications = [
            URL(fileURLWithPath: "/Applications/Comet.app"),
            URL(fileURLWithPath: "/Volumes/Tools/Comet.app"),
            Self.chromeApplicationURL,
        ]

        #expect(CursorLoginBrowserRouter.applicationLabels(applications) == [
            "Comet (/Applications)",
            "Comet (/Volumes/Tools)",
            "Google Chrome",
        ])
    }

    private static func supportsFixtureBrowser(_ applicationURL: URL?) -> Bool {
        applicationURL == self.cometApplicationURL || applicationURL == self.chromeApplicationURL
    }
}
