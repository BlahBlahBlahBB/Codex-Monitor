import Foundation
import XCTest
import CSQLite
@testable import CodexMonitorApp
@testable import CodexMonitorContracts

final class LocalUsageLedgerTests: XCTestCase {
    func testAdvancingTotalIsAdmittedOnceAndReplayAfterRestartDoesNotDoubleCount() async throws {
        let fixture = try LedgerFixture()
        defer { fixture.remove() }
        let ledger = LocalUsageLedgerProvider(databaseURL: fixture.databaseURL, calendar: fixture.calendar)
        await ledger.start()
        await ledger.ingest(registrations: [], observations: [fixture.token(total: 100, last: nil, at: fixture.day(12, 10))])
        await ledger.ingest(registrations: [], observations: [fixture.token(total: 130, last: nil, at: fixture.day(12, 11)), fixture.token(total: 130, last: nil, at: fixture.day(12, 11), offset: 99)])
        let first = await ledger.snapshot(now: fixture.day(12, 12))
        XCTAssertEqual(first.today?.totalTokens, 30)
        await ledger.stop()

        let restarted = LocalUsageLedgerProvider(databaseURL: fixture.databaseURL, calendar: fixture.calendar)
        await restarted.start()
        await restarted.ingest(registrations: [], observations: [fixture.token(total: 130, last: nil, at: fixture.day(12, 11))])
        let replay = await restarted.snapshot(now: fixture.day(12, 12))
        XCTAssertEqual(replay.today?.totalTokens, 30)
    }

    func testModelAttributionCacheAccountingAndReasoningDoesNotDoubleCount() async throws {
        let fixture = try LedgerFixture()
        defer { fixture.remove() }
        let ledger = LocalUsageLedgerProvider(databaseURL: fixture.databaseURL, calendar: fixture.calendar)
        await ledger.start()
        await ledger.ingest(registrations: [], observations: [fixture.token(total: 10, last: nil, at: fixture.day(12, 9))])
        let breakdown = TokenUsageBreakdown(inputTokens: 12, cachedInputTokens: 2, outputTokens: 8, reasoningOutputTokens: 5, totalTokens: 20)
        await ledger.ingest(registrations: [], observations: [fixture.token(total: 30, last: 20, breakdown: breakdown, at: fixture.day(12, 10))])
        let snapshot = await ledger.snapshot(now: fixture.day(12, 12))
        let row = try XCTUnwrap(snapshot.today?.models.first)
        XCTAssertEqual(row.displayName, "GPT-5.6 Terra")
        XCTAssertEqual(row.totalTokens, 20)
        XCTAssertEqual(row.estimatedCostUSD ?? -1, 0.000_145_5, accuracy: 0.000_000_001)
        XCTAssertEqual(row.estimatedCredits ?? -1, 0.003_637_5, accuracy: 0.000_000_001)
    }

    func testUnknownOrIncompleteBreakdownNeverCreatesCost() async throws {
        let fixture = try LedgerFixture(model: "gpt-unpriced")
        defer { fixture.remove() }
        let ledger = LocalUsageLedgerProvider(databaseURL: fixture.databaseURL, calendar: fixture.calendar)
        await ledger.start()
        await ledger.ingest(registrations: [], observations: [fixture.token(total: 10, last: nil, at: fixture.day(12, 9))])
        await ledger.ingest(registrations: [], observations: [fixture.token(total: 20, last: 10, breakdown: TokenUsageBreakdown(inputTokens: 5, cachedInputTokens: 0, outputTokens: 5, reasoningOutputTokens: 1, totalTokens: 10), at: fixture.day(12, 10))])
        let snapshot = await ledger.snapshot(now: fixture.day(12, 12))
        XCTAssertEqual(snapshot.today?.models.first?.displayName, "gpt-unpriced")
        XCTAssertNil(snapshot.today?.estimatedCostUSD)
        XCTAssertNil(snapshot.last30EstimatedCostUSD)
    }

    func testLocalMidnightAndTwoThreadsStayIsolatedAcrossExactThirtyDays() async throws {
        let fixture = try LedgerFixture()
        defer { fixture.remove() }
        let ledger = LocalUsageLedgerProvider(databaseURL: fixture.databaseURL, calendar: fixture.calendar)
        await ledger.start()
        await ledger.ingest(registrations: [], observations: [
            fixture.token(total: 10, last: nil, at: fixture.day(11, 23, minute: 59)),
            fixture.token(total: 15, last: nil, at: fixture.day(12, 0, minute: 1), thread: "second", turn: "second-turn", session: "second-session"),
            fixture.token(total: 30, last: nil, at: fixture.day(12, 0, minute: 2)),
            fixture.token(total: 25, last: nil, at: fixture.day(12, 0, minute: 3), thread: "second", turn: "second-turn", session: "second-session"),
        ])
        let snapshot = await ledger.snapshot(now: fixture.day(12, 12))
        XCTAssertEqual(snapshot.days.count, 30)
        XCTAssertEqual(snapshot.day(named: "2026-08-11")?.totalTokens, 0)
        XCTAssertEqual(snapshot.day(named: "2026-08-12")?.totalTokens, 30)
        XCTAssertEqual(snapshot.today?.models.reduce(0) { $0 + $1.totalTokens }, snapshot.today?.totalTokens)
        XCTAssertEqual(snapshot.last30TokenTotal, snapshot.days.reduce(0) { $0 + $1.totalTokens })
    }

    func testThirtyDayHeadlineUsesAccountUsage() throws {
        let fixture = try HybridFixture()
        let result = fixture.compose(accountToday: 100, accountYesterday: 200, localToday: 7)
        XCTAssertEqual(result.headlineTokens, 300)
        XCTAssertEqual(result.today?.provenance, .authoritativeAccount)
    }

    func testMissingAuthoritativeTodayUsesLocalProvisional() throws {
        let fixture = try HybridFixture()
        let result = fixture.compose(accountToday: nil, accountYesterday: 200, localToday: 7)
        XCTAssertEqual(result.headlineTokens, 207)
        XCTAssertEqual(result.today?.tokens, 7)
        XCTAssertEqual(result.today?.provenance, .localRealtimeProvisional)
    }

    func testAuthoritativeTodayReplacesProvisionalWithoutDoubleCount() throws {
        let fixture = try HybridFixture()
        let result = fixture.compose(accountToday: 100, accountYesterday: 200, localToday: 7)
        XCTAssertEqual(result.headlineTokens, 300)
        XCTAssertNotEqual(result.headlineTokens, 307)
    }

    func testHistoricalMissingAccountDayIsNotFilledFromLocalLedger() throws {
        let fixture = try HybridFixture()
        let result = fixture.compose(accountToday: 100, accountYesterday: nil, localToday: 7, localYesterday: 900)
        let yesterday = try XCTUnwrap(result.days.dropLast().last)
        XCTAssertNil(yesterday.tokens)
        XCTAssertEqual(yesterday.provenance, .sourceAbsent)
    }

    func testAccountThirtyDayDoesNotUseLocalPartialHistory() throws {
        let fixture = try HybridFixture()
        let result = fixture.compose(accountToday: nil, accountYesterday: 500, localToday: 7, localYesterday: 900)
        XCTAssertEqual(result.headlineTokens, 507)
        XCTAssertNotEqual(result.headlineTokens, 1_407)
    }

    func testPerModelTotalsNeverReceiveUnattributedAccountDifference() throws {
        let fixture = try HybridFixture()
        let result = fixture.compose(accountToday: 100, accountYesterday: 0, localToday: 7)
        let localModelTotal = try XCTUnwrap(fixture.local(localToday: 7).today).models.reduce(0) { $0 + $1.totalTokens }
        XCTAssertEqual(localModelTotal, 7)
        XCTAssertEqual(result.today?.tokens, 100)
        XCTAssertNotEqual(localModelTotal, result.today?.tokens)
    }

    func testThirtyDayCostUnavailableWhenOnlyPartialLocalCostExists() throws {
        let fixture = try HybridFixture()
        let result = fixture.compose(accountToday: 100, accountYesterday: 200, localToday: 7)
        XCTAssertNil(result.headlineEstimatedCostUSD)
    }

    func testSameSessionNewTurnUsesSessionCumulativeDelta() async throws {
        let fixture = try LedgerFixture()
        defer { fixture.remove() }
        let ledger = LocalUsageLedgerProvider(databaseURL: fixture.databaseURL, calendar: fixture.calendar)
        await ledger.start()
        await ledger.ingest(registrations: [], observations: [
            fixture.token(total: 100, last: nil, at: fixture.day(12, 9), turn: "turn-a"),
            fixture.token(total: 130, last: nil, at: fixture.day(12, 10), turn: "turn-b")
        ])
        let snapshot = await ledger.snapshot(now: fixture.day(12, 12))
        XCTAssertEqual(snapshot.today?.totalTokens, 30)
    }

    func testHistoricalLowerCumulativeReplayDoesNotLowerCursor() async throws {
        let fixture = try LedgerFixture()
        defer { fixture.remove() }
        let ledger = LocalUsageLedgerProvider(databaseURL: fixture.databaseURL, calendar: fixture.calendar)
        await ledger.start()
        await ledger.ingest(registrations: [], observations: [
            fixture.token(total: 100, last: nil, at: fixture.day(12, 9)),
            fixture.token(total: 130, last: nil, at: fixture.day(12, 10)),
            fixture.token(total: 80, last: nil, at: fixture.day(12, 11)),
            fixture.token(total: 130, last: nil, at: fixture.day(12, 12))
        ])
        let snapshot = await ledger.snapshot(now: fixture.day(12, 12))
        XCTAssertEqual(snapshot.today?.totalTokens, 30)
    }

    func testBrandNewLiveSessionCountsFirstTokenEventFromZero() async throws {
        let fixture = try LedgerFixture()
        defer { fixture.remove() }
        let ledger = LocalUsageLedgerProvider(databaseURL: fixture.databaseURL, calendar: fixture.calendar)
        await ledger.start()
        await ledger.ingest(registrations: [], observations: [fixture.token(total: 25, last: 25, at: fixture.day(12, 10))], completeFromSessionStartSessions: [fixture.cursorSourceKey()])
        let snapshot = await ledger.snapshot(now: fixture.day(12, 12))
        XCTAssertEqual(snapshot.today?.totalTokens, 25)
    }

    func testFirstCumulativeRequiresTheExactLiveSessionKey() async throws {
        let fixture = try LedgerFixture()
        defer { fixture.remove() }
        let ledger = LocalUsageLedgerProvider(databaseURL: fixture.databaseURL, calendar: fixture.calendar)
        await ledger.start()
        await ledger.ingest(registrations: [], observations: [
            fixture.token(total: 25, last: 25, at: fixture.day(12, 10), session: "other-session")
        ], completeFromSessionStartSessions: [fixture.cursorSourceKey()])
        await ledger.ingest(registrations: [], observations: [
            fixture.token(total: 30, last: 30, at: fixture.day(12, 11))
        ], completeFromSessionStartSessions: [fixture.cursorSourceKey()])
        let snapshot = await ledger.snapshot(now: fixture.day(12, 12))
        XCTAssertEqual(snapshot.today?.totalTokens, 30)
    }

    func testMidstreamHistoricalFirstObservationRemainsBaseline() async throws {
        let fixture = try LedgerFixture()
        defer { fixture.remove() }
        let ledger = LocalUsageLedgerProvider(databaseURL: fixture.databaseURL, calendar: fixture.calendar)
        await ledger.start()
        await ledger.ingest(registrations: [], observations: [
            fixture.token(total: 100, last: nil, at: fixture.day(12, 9)),
            fixture.token(total: 130, last: nil, at: fixture.day(12, 10))
        ], admission: .midstreamBaseline)
        let snapshot = await ledger.snapshot(now: fixture.day(12, 12))
        XCTAssertEqual(snapshot.today?.totalTokens, 30)
    }

    func testRestartReplayDoesNotDoubleCountAcrossTurns() async throws {
        let fixture = try LedgerFixture()
        defer { fixture.remove() }
        let first = LocalUsageLedgerProvider(databaseURL: fixture.databaseURL, calendar: fixture.calendar)
        await first.start()
        await first.ingest(registrations: [], observations: [
            fixture.token(total: 100, last: nil, at: fixture.day(12, 9), turn: "turn-a"),
            fixture.token(total: 130, last: nil, at: fixture.day(12, 10), turn: "turn-b")
        ])
        await first.stop()
        let restarted = LocalUsageLedgerProvider(databaseURL: fixture.databaseURL, calendar: fixture.calendar)
        await restarted.start()
        await restarted.ingest(registrations: [], observations: [
            fixture.token(total: 100, last: nil, at: fixture.day(12, 11), turn: "turn-a"),
            fixture.token(total: 130, last: nil, at: fixture.day(12, 12), turn: "turn-b")
        ])
        let snapshot = await restarted.snapshot(now: fixture.day(12, 12))
        XCTAssertEqual(snapshot.today?.totalTokens, 30)
    }

    func testTokenAttributionDoesNotCrossTurnsAfterModelSwitch() async throws {
        let fixture = try LedgerFixture()
        defer { fixture.remove() }
        let ledger = LocalUsageLedgerProvider(databaseURL: fixture.databaseURL, calendar: fixture.calendar)
        await ledger.start()
        await ledger.ingest(registrations: [], observations: [
            fixture.turnContext(turn: "turn-a", model: "gpt-5.6-terra", at: fixture.day(12, 8)),
            fixture.token(total: 100, last: nil, modelOverride: nil, at: fixture.day(12, 9), turn: "turn-a"),
            fixture.turnContext(turn: "turn-b", model: "gpt-5.6-luna", at: fixture.day(12, 9)),
            fixture.token(total: 130, last: nil, modelOverride: nil, at: fixture.day(12, 10), turn: "turn-a")
        ])
        let snapshot = await ledger.snapshot(now: fixture.day(12, 12))
        XCTAssertEqual(snapshot.today?.models.first?.displayName, "GPT-5.6 Terra")
    }

    func testIncompleteBreakdownWithResidualTokensHasNoCost() async throws {
        let fixture = try LedgerFixture()
        defer { fixture.remove() }
        let ledger = LocalUsageLedgerProvider(databaseURL: fixture.databaseURL, calendar: fixture.calendar)
        await ledger.start()
        let residual = TokenUsageBreakdown(inputTokens: 10, cachedInputTokens: 2, outputTokens: 8, reasoningOutputTokens: 5, totalTokens: 20)
        await ledger.ingest(registrations: [], observations: [
            fixture.token(total: 10, last: nil, at: fixture.day(12, 9)),
            fixture.token(total: 30, last: 20, breakdown: residual, at: fixture.day(12, 10))
        ])
        let snapshot = await ledger.snapshot(now: fixture.day(12, 12))
        XCTAssertNil(snapshot.today?.estimatedCostUSD)
    }

    func testVersionOneDerivedFactsAreAtomicallyInvalidatedBeforeRebuild() async throws {
        let fixture = try LedgerFixture()
        defer { fixture.remove() }
        try fixture.seedVersionOneLedger()

        let ledger = LocalUsageLedgerProvider(databaseURL: fixture.databaseURL, calendar: fixture.calendar)
        await ledger.start()
        let snapshot = await ledger.snapshot(now: fixture.day(12, 12))
        await ledger.stop()

        XCTAssertEqual(snapshot.availability, .unknown)
        XCTAssertEqual(try fixture.sqliteScalar("PRAGMA user_version"), 2)
        XCTAssertEqual(try fixture.sqliteScalar("SELECT COUNT(*) FROM usage_samples"), 0)
        XCTAssertEqual(try fixture.sqliteScalar("SELECT COUNT(*) FROM usage_cursors"), 0)
        XCTAssertEqual(try fixture.sqliteScalar("SELECT COUNT(*) FROM usage_ledger_migrations WHERE schema_version = 2"), 1)
    }
}

private final class LedgerFixture {
    let root: URL
    let databaseURL: URL
    var calendar: Calendar
    private let model: String

    init(model: String = "gpt-5.6-terra") throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("CodexMonitorLedgerTests-\(UUID().uuidString)", isDirectory: true)
        databaseURL = root.appendingPathComponent("usage.sqlite")
        self.model = model
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    func seedVersionOneLedger() throws {
        try sqliteExec("CREATE TABLE usage_samples (sample_id TEXT PRIMARY KEY NOT NULL, source_key TEXT NOT NULL, cumulative_total INTEGER NOT NULL, date_key TEXT NOT NULL, model_id TEXT NOT NULL, display_model TEXT NOT NULL, total_tokens INTEGER NOT NULL, estimated_cost_usd REAL, estimated_credits REAL)")
        try sqliteExec("CREATE TABLE usage_cursors (source_key TEXT PRIMARY KEY NOT NULL, cumulative_total INTEGER NOT NULL)")
        try sqliteExec("INSERT INTO usage_samples VALUES ('v1-sample', 'thread|turn|session', 100, '2026-08-12', 'gpt', 'GPT', 100, NULL, NULL)")
        try sqliteExec("INSERT INTO usage_cursors VALUES ('thread|turn|session', 100)")
        try sqliteExec("PRAGMA user_version = 1")
    }

    func sqliteScalar(_ sql: String) throws -> Int64 {
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else { throw POSIXError(.EIO) }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw POSIXError(.EIO) }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw POSIXError(.EIO) }
        return sqlite3_column_int64(statement, 0)
    }

    private func sqliteExec(_ sql: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else { throw POSIXError(.EIO) }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw POSIXError(.EIO) }
    }

    func day(_ day: Int, _ hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour, minute: minute))!
    }

    func token(total: Int64, last: Int64?, breakdown: TokenUsageBreakdown? = nil, modelOverride: String? = "__fixture_default__", at: Date, thread: String = "thread", turn: String = "turn", session: String = "session", offset: UInt64 = 1) -> DesktopObservation {
        let source = SourceID("ledger-test")!
        let threadID = NamespacedID(sourceID: source, entityKind: .thread, rawID: thread)!
        let turnID = NamespacedID(sourceID: source, entityKind: .turn, rawID: turn)!
        let eventModel = modelOverride == "__fixture_default__" ? model : modelOverride
        return .rollout(RolloutRecordEnvelope(threadID: threadID, turnID: turnID, itemID: nil, kind: .tokenCount, activity: nil, tokenSnapshot: TokenSnapshot(totalTokens: total, lastCallTokens: last, lastCallBreakdown: breakdown), model: eventModel, reasoningEffort: nil, sessionID: session, authoritativeEventAt: at, observedAt: at, fileOffset: offset))
    }

    func turnContext(turn: String, model: String, at: Date, thread: String = "thread") -> DesktopObservation {
        let source = SourceID("ledger-test")!
        let threadID = NamespacedID(sourceID: source, entityKind: .thread, rawID: thread)!
        let turnID = NamespacedID(sourceID: source, entityKind: .turn, rawID: turn)!
        return .rollout(RolloutRecordEnvelope(threadID: threadID, turnID: turnID, itemID: nil, kind: .turnContext, activity: nil, tokenSnapshot: nil, model: model, reasoningEffort: nil, sessionID: "session", authoritativeEventAt: at, observedAt: at, fileOffset: 0))
    }

    func cursorSourceKey(thread: String = "thread", session: String = "session") -> String {
        "ledger-test|\(thread)|\(session)"
    }
}

private final class HybridFixture {
    let calendar: Calendar
    let now: Date

    init() throws {
        var created = Calendar(identifier: .gregorian)
        created.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        calendar = created
        now = try XCTUnwrap(created.date(from: DateComponents(year: 2026, month: 8, day: 13, hour: 12)))
    }

    func compose(accountToday: Int?, accountYesterday: Int?, localToday: Int64, localYesterday: Int64 = 0) -> HybridUsageWindow {
        let todayKey = LocalUsageDateKey.value(for: now, calendar: calendar)
        let yesterdayKey = LocalUsageDateKey.value(for: calendar.date(byAdding: .day, value: -1, to: now)!, calendar: calendar)
        let buckets = (0..<30).reversed().map { offset -> AccountUsageDailyBucket in
            let key = LocalUsageDateKey.value(for: calendar.date(byAdding: .day, value: -offset, to: now)!, calendar: calendar)
            if key == todayKey, let accountToday { return AccountUsageDailyBucket(startDate: key, tokens: accountToday, isSourcePresent: true) }
            if key == yesterdayKey, let accountYesterday { return AccountUsageDailyBucket(startDate: key, tokens: accountYesterday, isSourcePresent: true) }
            return AccountUsageDailyBucket(startDate: key, tokens: 0, isSourcePresent: false)
        }
        return HybridUsageComposer.compose(accountDailyBuckets: buckets, accountAvailability: .available, localLedger: local(localToday: localToday, localYesterday: localYesterday), now: now, calendar: calendar)!
    }

    func local(localToday: Int64, localYesterday: Int64 = 0) -> LocalUsageLedgerSnapshot {
        let todayKey = LocalUsageDateKey.value(for: now, calendar: calendar)
        let yesterdayKey = LocalUsageDateKey.value(for: calendar.date(byAdding: .day, value: -1, to: now)!, calendar: calendar)
        let model = LocalUsageModelTotal(modelID: "gpt-5.6-terra", displayName: "GPT-5.6 Terra", totalTokens: localToday, estimatedCostUSD: 0.01, estimatedCredits: nil)
        return LocalUsageLedgerSnapshot(availability: .available, days: [
            LocalUsageDay(dateKey: yesterdayKey, totalTokens: localYesterday, models: localYesterday > 0 ? [LocalUsageModelTotal(modelID: "gpt-5.6-terra", displayName: "GPT-5.6 Terra", totalTokens: localYesterday, estimatedCostUSD: nil, estimatedCredits: nil)] : []),
            LocalUsageDay(dateKey: todayKey, totalTokens: localToday, models: [model])
        ])
    }
}
