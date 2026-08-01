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
}
