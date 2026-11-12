//
//  SwamaRequestTests.swift
//  MoltenTests
//
//  Regression coverage for audit finding F-42:
//  Swama requests must carry explicit timeouts (previously the 60s
//  URLSession default applied, with no timeout on getModels at all).
//

import XCTest
@testable import Molten

final class SwamaRequestTests: XCTestCase {

    private func makeService() -> SwamaService {
        // Internal init; reads the user's Swama settings but performs no I/O.
        SwamaService()
    }

    func testGetRequestCarriesMethodTimeoutAndHeaders() {
        let service = makeService()

        let request = service.makeRequest(path: "/v1/models", timeout: SwamaService.modelsTimeout)

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.timeoutInterval, SwamaService.modelsTimeout)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Accept"))
        XCTAssertTrue(request.url?.absoluteString.hasSuffix("/v1/models") ?? false)
    }

    func testStreamRequestSetsSSEAcceptHeaderAndStartTimeout() {
        let service = makeService()

        let request = service.makeRequest(
            path: "/v1/chat/completions",
            method: "POST",
            timeout: SwamaService.streamStartTimeout,
            accept: "text/event-stream"
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, SwamaService.streamStartTimeout)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertTrue(request.url?.absoluteString.hasSuffix("/v1/chat/completions") ?? false)
    }

    func testTimeoutConstantsMatchDocumentedValues() {
        XCTAssertEqual(SwamaService.modelsTimeout, 15)
        XCTAssertEqual(SwamaService.streamStartTimeout, 120)
        XCTAssertEqual(SwamaService.completionTimeout, 300)
    }

    // MARK: - ProviderEndpointResolver (deferred-fixes §3.3 dedup)

    private let defaultURL = URL(string: "http://localhost:28100")!

    /// Fresh isolated suite per test — the bundle is hosted in Molten.app,
    /// so UserDefaults.standard holds the user's real settings.
    private func makeDefaults() -> UserDefaults {
        let suiteName = "SwamaRequestTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    private func resolve(
        url: String? = nil,
        token: String? = nil,
        defaults: UserDefaults
    ) -> ProviderEndpoint {
        ProviderEndpointResolver.resolve(
            url: url,
            token: token,
            urlKey: "swamaUri",
            tokenKey: "swamaApiKey",
            defaultLocalhost: defaultURL,
            defaults: defaults
        )
    }

    func testUnconfiguredFallsBackToDefaultLocalhost() {
        let endpoint = resolve(defaults: makeDefaults())
        XCTAssertEqual(endpoint.baseURL, defaultURL)
        XCTAssertTrue(endpoint.usingDefaultLocalhost)
        XCTAssertFalse(endpoint.disabled)
    }

    func testFirstLaunchEmptyExplicitURLDoesNotDisable() {
        // Settings passes its empty @AppStorage default on save/check; with
        // no stored key that must still auto-detect localhost, not disable.
        let endpoint = resolve(url: "", defaults: makeDefaults())
        XCTAssertEqual(endpoint.baseURL, defaultURL)
        XCTAssertTrue(endpoint.usingDefaultLocalhost)
        XCTAssertFalse(endpoint.disabled)
    }

    func testStoredEmptyURLDisablesProvider() {
        let defaults = makeDefaults()
        defaults.set("", forKey: "swamaUri")
        let endpoint = resolve(defaults: defaults)
        XCTAssertTrue(endpoint.disabled)
        XCTAssertFalse(endpoint.usingDefaultLocalhost)
    }

    func testExplicitURLWinsOverStored() {
        let defaults = makeDefaults()
        defaults.set("http://stored.example:1111", forKey: "swamaUri")
        let endpoint = resolve(url: "http://explicit.example:2222", defaults: defaults)
        XCTAssertEqual(endpoint.baseURL.absoluteString, "http://explicit.example:2222")
        XCTAssertFalse(endpoint.usingDefaultLocalhost)
        XCTAssertFalse(endpoint.disabled)
    }

    func testStoredURLUsedWhenNoExplicit() {
        let defaults = makeDefaults()
        defaults.set("http://stored.example:1111", forKey: "swamaUri")
        let endpoint = resolve(defaults: defaults)
        XCTAssertEqual(endpoint.baseURL.absoluteString, "http://stored.example:1111")
        XCTAssertFalse(endpoint.usingDefaultLocalhost)
    }

    func testSchemePrependedAndWhitespaceTrimmed() {
        let endpoint = resolve(url: "  myhost.example:8080  ", defaults: makeDefaults())
        XCTAssertEqual(endpoint.baseURL.absoluteString, "http://myhost.example:8080")
    }

    func testMalformedURLFallsBackToDefault() {
        let endpoint = resolve(url: "http://not a valid url", defaults: makeDefaults())
        XCTAssertEqual(endpoint.baseURL, defaultURL)
        XCTAssertTrue(endpoint.usingDefaultLocalhost)
    }

    func testTokenExplicitWinsOverStored() {
        let defaults = makeDefaults()
        defaults.set("stored-token", forKey: "swamaApiKey")
        XCTAssertEqual(resolve(token: "explicit-token", defaults: defaults).bearerToken, "explicit-token")
        XCTAssertEqual(resolve(defaults: defaults).bearerToken, "stored-token")
    }

    func testEmptyTokenMeansNoToken() {
        let defaults = makeDefaults()
        defaults.set("stored-token", forKey: "swamaApiKey")
        // Explicit empty overrides stored with "no token" (F-44/F-48 semantics).
        XCTAssertNil(resolve(token: "", defaults: defaults).bearerToken)
        defaults.set("", forKey: "swamaApiKey")
        XCTAssertNil(resolve(defaults: defaults).bearerToken)
    }

    func testTokenSurvivesDefaultLocalhostPath() {
        // F-48 regression: the default-localhost path used to drop the token.
        let defaults = makeDefaults()
        defaults.set("stored-token", forKey: "swamaApiKey")
        let endpoint = resolve(defaults: defaults)
        XCTAssertTrue(endpoint.usingDefaultLocalhost)
        XCTAssertEqual(endpoint.bearerToken, "stored-token")
    }

    func testServiceWiringUsesResolvedEndpoint() {
        // Service-level check against UserDefaults.standard (save/restore):
        // initEndpoint must feed the resolver's result into makeRequest.
        let key = "swamaUri"
        let original = UserDefaults.standard.string(forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        UserDefaults.standard.set("http://127.0.0.1:9999", forKey: key)
        let service = SwamaService()
        let request = service.makeRequest(path: "/v1/models", timeout: 5)
        XCTAssertEqual(request.url?.host, "127.0.0.1")
        XCTAssertEqual(request.url?.port, 9999)
        XCTAssertFalse(service.usingDefaultLocalhost)
    }

    func testDisabledServiceIsUnreachableWithoutNetwork() async {
        let key = "swamaUri"
        let original = UserDefaults.standard.string(forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        UserDefaults.standard.set("", forKey: key)
        let service = SwamaService()
        // Guarded by isConfigured — returns false immediately, no request.
        let reachable = await service.reachable()
        XCTAssertFalse(reachable)
    }
}
