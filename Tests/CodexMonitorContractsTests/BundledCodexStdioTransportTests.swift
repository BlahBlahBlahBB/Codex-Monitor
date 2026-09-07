import Foundation
import XCTest
@testable import CodexMonitorApp

final class BundledCodexStdioTransportTests: XCTestCase {
    func testPartialLineThenFinishCompletesPendingReadExactlyOnce() async throws {
        let pipe = Pipe()
        let reader = StdioLineReader(handle: pipe.fileHandleForReading)
        let receive = Task { await reader.nextLine() }

        try await waitForPendingRead(in: reader)
        reader.ingestForTesting(Data("{\"partial\":".utf8))
        XCTAssertEqual(reader.pendingReadCountForTesting, 1, "an incomplete line must not complete or discard its receiver")

        reader.finish()
        let result = await receive.value
        XCTAssertNil(result)
        reader.finish()
        XCTAssertEqual(reader.pendingReadCountForTesting, 0)
        pipe.fileHandleForWriting.closeFile()
    }

    func testCompleteLineWinsRaceWithLaterFinish() async throws {
        let pipe = Pipe()
        let reader = StdioLineReader(handle: pipe.fileHandleForReading)
        let receive = Task { await reader.nextLine() }

        try await waitForPendingRead(in: reader)
        reader.ingestForTesting(Data("{\"id\":1}\n".utf8))
        let result = await receive.value
        XCTAssertEqual(result, Data("{\"id\":1}".utf8))

        reader.finish()
        XCTAssertEqual(reader.pendingReadCountForTesting, 0)
        pipe.fileHandleForWriting.closeFile()
    }

    private func waitForPendingRead(in reader: StdioLineReader) async throws {
        for _ in 0..<10_000 {
            if reader.pendingReadCountForTesting == 1 { return }
            await Task.yield()
        }
        throw PendingReadError.notRegistered
    }
}

private enum PendingReadError: Error {
    case notRegistered
}
