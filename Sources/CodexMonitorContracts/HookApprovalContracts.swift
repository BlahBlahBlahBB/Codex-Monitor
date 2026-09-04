import Foundation
import CryptoKit

/// A one-way identity emitted by the future Hook writer.  The runtime accepts
/// only keyed, HMAC-shaped values; raw Codex session, turn, or tool IDs never
/// enter this journal contract.
public struct HookOpaqueIdentity: Hashable, Codable, Sendable, Comparable {
    public let value: String

    public init?(_ value: String) {
        let prefix = "hmac-sha256:"
        let digest = String(value.dropFirst(prefix.count))
        guard value.hasPrefix(prefix), (32...128).contains(digest.count),
              digest.allSatisfy({ $0.isHexDigit }) else { return nil }
        self.value = value.lowercased()
    }

    public static func < (lhs: HookOpaqueIdentity, rhs: HookOpaqueIdentity) -> Bool { lhs.value < rhs.value }

    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let opaque = HookOpaqueIdentity(value) else {
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Expected an HMAC-shaped opaque identity")
        }
        self = opaque
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

public struct HookApprovalJournalEventID: Hashable, Codable, Sendable, Comparable {
    public let value: UInt64
    public init?(_ value: UInt64) {
        guard value > 0 else { return nil }
        self.value = value
    }
    public static func < (lhs: HookApprovalJournalEventID, rhs: HookApprovalJournalEventID) -> Bool { lhs.value < rhs.value }

    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(UInt64.self)
        guard let eventID = HookApprovalJournalEventID(value) else {
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Expected a positive journal event identity")
        }
        self = eventID
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

/// Exact ownership used by the Hook lane.  All three identities are opaque at
/// the persistence boundary, so neither raw session nor raw turn data is kept.
public struct HookApprovalTurnOwner: Hashable, Codable, Sendable {
    public let sourceID: HookOpaqueIdentity
    public let sessionID: HookOpaqueIdentity
    public let turnID: HookOpaqueIdentity

    public init(sourceID: HookOpaqueIdentity, sessionID: HookOpaqueIdentity, turnID: HookOpaqueIdentity) {
        self.sourceID = sourceID; self.sessionID = sessionID; self.turnID = turnID
    }
}

/// Shared, keyed reduction boundary for Hook and desktop runtime identities.
/// Callers may hold raw values only long enough to derive these HMAC-shaped
/// values; the raw inputs never enter a journal checkpoint or domain event.
public protocol HookApprovalIdentityResolving: Sendable {
    func owner(sourceRawID: String, sessionRawID: String, turnRawID: String) -> HookApprovalTurnOwner?
}

public struct KeyedHookApprovalIdentityDeriver: HookApprovalIdentityResolving, Sendable {
    private let key: SymmetricKey

    public init?(keyMaterial: Data) {
        guard !keyMaterial.isEmpty else { return nil }
        key = SymmetricKey(data: keyMaterial)
    }

    public func owner(sourceRawID: String, sessionRawID: String, turnRawID: String) -> HookApprovalTurnOwner? {
        guard !sourceRawID.isEmpty, !sessionRawID.isEmpty, !turnRawID.isEmpty,
              let source = identity("source", sourceRawID),
              let session = identity("session", sessionRawID),
              let turn = identity("turn", turnRawID) else { return nil }
        return HookApprovalTurnOwner(sourceID: source, sessionID: session, turnID: turn)
    }

    private func identity(_ domain: String, _ raw: String) -> HookOpaqueIdentity? {
        let message = Data((domain + "\\u{0}" + raw).utf8)
        let digest = HMAC<SHA256>.authenticationCode(for: message, using: key)
        return HookOpaqueIdentity("hmac-sha256:" + digest.map { String(format: "%02x", $0) }.joined())
    }
}

public enum HookApprovalSourceHealthState: String, Codable, Sendable, Equatable {
    case unknown
    case available
    case unavailable
}

public enum HookApprovalJournalHealthReason: String, Codable, Sendable, Equatable {
    case malformedRecord
    case outOfOrderEvent
    case sourceMismatch
    case sourceReadFailed
}

public struct HookApprovalSourceHealth: Sendable, Equatable {
    public let sourceID: HookOpaqueIdentity?
    public let state: HookApprovalSourceHealthState
    public let observedAt: Date
    public let reason: HookApprovalJournalHealthReason?

    public init(sourceID: HookOpaqueIdentity?, state: HookApprovalSourceHealthState, observedAt: Date, reason: HookApprovalJournalHealthReason? = nil) {
        self.sourceID = sourceID; self.state = state; self.observedAt = observedAt; self.reason = reason
    }
}

public struct HookApprovalLifecycleEvent: Sendable, Equatable {
    public let journalEventID: HookApprovalJournalEventID
    public let owner: HookApprovalTurnOwner
    /// Present only if the Hook supplied it.  Reducer resolution deliberately
    /// does not use this value as a correlation key.
    public let toolUseID: HookOpaqueIdentity?
    public let observedAt: Date

    public init(journalEventID: HookApprovalJournalEventID, owner: HookApprovalTurnOwner, toolUseID: HookOpaqueIdentity? = nil, observedAt: Date) {
        self.journalEventID = journalEventID; self.owner = owner; self.toolUseID = toolUseID; self.observedAt = observedAt
    }
}

/// Closed, sanitized domain events.  No case carries Hook JSON, prompts,
/// commands, tool input/output, assistant content, or raw identifiers.
public enum HookApprovalEvent: Sendable, Equatable {
    case permissionRequest(HookApprovalLifecycleEvent)
    case postToolUse(HookApprovalLifecycleEvent)
    case stop(HookApprovalLifecycleEvent)
    case sourceHealth(HookApprovalSourceHealth)
}

public enum HookApprovalJournalRecordKind: String, Codable, Sendable {
    case permissionRequest
    case postToolUse
    case stop
    case sourceHealth
}

/// The allow-listed on-disk schema for a future Hook-owned journal.  Its
/// decoder rejects unknown keys, raw-content fields, invalid opaque IDs, and
/// structurally invalid event variants before the runtime sees an event.
public struct HookApprovalJournalRecord: Codable, Sendable, Equatable {
    public static let schemaVersion = 1

    public let schema: Int
    public let journalEventID: HookApprovalJournalEventID
    public let kind: HookApprovalJournalRecordKind
    public let sourceID: HookOpaqueIdentity
    public let sessionID: HookOpaqueIdentity?
    public let turnID: HookOpaqueIdentity?
    public let toolUseID: HookOpaqueIdentity?
    public let observedAtMilliseconds: Int64
    public let sourceHealth: HookApprovalSourceHealthState?

    public init?(journalEventID: HookApprovalJournalEventID, kind: HookApprovalJournalRecordKind, sourceID: HookOpaqueIdentity, sessionID: HookOpaqueIdentity? = nil, turnID: HookOpaqueIdentity? = nil, toolUseID: HookOpaqueIdentity? = nil, observedAtMilliseconds: Int64, sourceHealth: HookApprovalSourceHealthState? = nil) {
        guard observedAtMilliseconds >= 0 else { return nil }
        switch kind {
        case .permissionRequest, .postToolUse, .stop:
            guard sessionID != nil, turnID != nil, sourceHealth == nil else { return nil }
        case .sourceHealth:
            guard sessionID == nil, turnID == nil, toolUseID == nil,
                  sourceHealth == .available || sourceHealth == .unavailable else { return nil }
        }
        self.schema = Self.schemaVersion
        self.journalEventID = journalEventID; self.kind = kind; self.sourceID = sourceID
        self.sessionID = sessionID; self.turnID = turnID; self.toolUseID = toolUseID
        self.observedAtMilliseconds = observedAtMilliseconds; self.sourceHealth = sourceHealth
    }

    public var event: HookApprovalEvent {
        let observedAt = Date(timeIntervalSince1970: Double(observedAtMilliseconds) / 1_000)
        switch kind {
        case .permissionRequest:
            return .permissionRequest(lifecycleEvent(observedAt: observedAt))
        case .postToolUse:
            return .postToolUse(lifecycleEvent(observedAt: observedAt))
        case .stop:
            return .stop(lifecycleEvent(observedAt: observedAt))
        case .sourceHealth:
            return .sourceHealth(HookApprovalSourceHealth(sourceID: sourceID, state: sourceHealth!, observedAt: observedAt))
        }
    }

    private func lifecycleEvent(observedAt: Date) -> HookApprovalLifecycleEvent {
        HookApprovalLifecycleEvent(
            journalEventID: journalEventID,
            owner: HookApprovalTurnOwner(sourceID: sourceID, sessionID: sessionID!, turnID: turnID!),
            toolUseID: toolUseID,
            observedAt: observedAt
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schema, journalEventID, kind, sourceID, sessionID, turnID, toolUseID, observedAtMilliseconds, sourceHealth
    }

    /// A dynamic key is required here: a container keyed by `CodingKeys` only
    /// exposes recognized keys, and therefore cannot prove that the raw JSON
    /// object did not carry an extra prompt, command, or other payload field.
    private struct RawCodingKey: CodingKey {
        let stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        let intValue: Int? = nil
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: any Decoder) throws {
        let rawContainer = try decoder.container(keyedBy: RawCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.stringValue))
        guard Set(rawContainer.allKeys.map(\.stringValue)).isSubset(of: allowed) else {
            throw DecodingError.dataCorruptedError(forKey: RawCodingKey(stringValue: "schema")!, in: rawContainer, debugDescription: "Journal record contains a non-allow-listed field")
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(Int.self, forKey: .schema)
        guard schema == Self.schemaVersion else {
            throw DecodingError.dataCorruptedError(forKey: .schema, in: container, debugDescription: "Unsupported journal schema")
        }
        guard let value = HookApprovalJournalRecord(
            journalEventID: try container.decode(HookApprovalJournalEventID.self, forKey: .journalEventID),
            kind: try container.decode(HookApprovalJournalRecordKind.self, forKey: .kind),
            sourceID: try container.decode(HookOpaqueIdentity.self, forKey: .sourceID),
            sessionID: try container.decodeIfPresent(HookOpaqueIdentity.self, forKey: .sessionID),
            turnID: try container.decodeIfPresent(HookOpaqueIdentity.self, forKey: .turnID),
            toolUseID: try container.decodeIfPresent(HookOpaqueIdentity.self, forKey: .toolUseID),
            observedAtMilliseconds: try container.decode(Int64.self, forKey: .observedAtMilliseconds),
            sourceHealth: try container.decodeIfPresent(HookApprovalSourceHealthState.self, forKey: .sourceHealth)
        ) else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Invalid sanitized journal record")
        }
        self = value
    }
}

public struct HookApprovalPendingEvidence: Codable, Sendable, Equatable {
    public let journalEventID: HookApprovalJournalEventID
    public let owner: HookApprovalTurnOwner
    public let observedAt: Date
    public init(journalEventID: HookApprovalJournalEventID, owner: HookApprovalTurnOwner, observedAt: Date) {
        self.journalEventID = journalEventID; self.owner = owner; self.observedAt = observedAt
    }
}

/// Persistable reconciliation input for the future Hook lane.  It includes
/// only opaque IDs and timestamps and can therefore be safely retained across
/// a Monitor restart without retaining Hook payload content.
public struct HookApprovalJournalCheckpoint: Codable, Sendable, Equatable {
    public let sourceID: HookOpaqueIdentity?
    public let lastJournalEventID: HookApprovalJournalEventID?
    public let unresolved: [HookApprovalPendingEvidence]
    public let sourceHealth: HookApprovalSourceHealthState

    public init(sourceID: HookOpaqueIdentity?, lastJournalEventID: HookApprovalJournalEventID?, unresolved: [HookApprovalPendingEvidence], sourceHealth: HookApprovalSourceHealthState = .unknown) {
        self.sourceID = sourceID; self.lastJournalEventID = lastJournalEventID
        self.unresolved = unresolved.sorted { $0.journalEventID < $1.journalEventID }
        self.sourceHealth = sourceHealth
    }
}

public struct HookApprovalJournalReadResult: Sendable, Equatable {
    public let events: [HookApprovalEvent]
    public let checkpoint: HookApprovalJournalCheckpoint
    public let health: HookApprovalSourceHealth
}

/// Injected, read-only source of already-sanitized Hook journal bytes. The
/// production monitor owns no Hook installation, discovery, or execution.
public protocol HookApprovalJournalSource: Sendable {
    func readRecords() throws -> [Data]
}

/// In-memory adapter for sanitized journal records.  It performs no I/O and
/// does not install, activate, or communicate with a Codex Hook.
public final class HookApprovalJournalReader: @unchecked Sendable {
    private var sourceID: HookOpaqueIdentity?
    private var lastJournalEventID: HookApprovalJournalEventID?
    private var unresolved: [HookApprovalJournalEventID: HookApprovalPendingEvidence]
    private var health: HookApprovalSourceHealth

    public init(checkpoint: HookApprovalJournalCheckpoint = .init(sourceID: nil, lastJournalEventID: nil, unresolved: []), observedAt: Date = Date()) {
        self.sourceID = checkpoint.sourceID
        self.lastJournalEventID = checkpoint.lastJournalEventID
        self.unresolved = Dictionary(uniqueKeysWithValues: checkpoint.unresolved.map { ($0.journalEventID, $0) })
        self.health = HookApprovalSourceHealth(sourceID: checkpoint.sourceID, state: checkpoint.sourceHealth, observedAt: observedAt)
    }

    public func checkpoint() -> HookApprovalJournalCheckpoint {
        HookApprovalJournalCheckpoint(sourceID: sourceID, lastJournalEventID: lastJournalEventID, unresolved: Array(unresolved.values), sourceHealth: health.state)
    }

    public func markUnavailable() -> HookApprovalJournalReadResult {
        unavailable(.sourceReadFailed, admitted: [])
    }

    /// Reads records in their supplied journal order.  Replays at or before a
    /// committed cursor are idempotent; a newly observed backward event is
    /// rejected rather than reordered or guessed.
    public func ingest(_ encodedRecords: [Data]) -> HookApprovalJournalReadResult {
        var admitted: [HookApprovalEvent] = []
        let originalLastID = lastJournalEventID
        var acceptedInThisBatch = false

        for data in encodedRecords {
            guard let record = try? JSONDecoder().decode(HookApprovalJournalRecord.self, from: data) else {
                return unavailable(.malformedRecord, admitted: admitted)
            }
            if let expectedSource = sourceID, record.sourceID != expectedSource {
                return unavailable(.sourceMismatch, admitted: admitted)
            }
            if sourceID == nil { sourceID = record.sourceID }

            if let last = lastJournalEventID, record.journalEventID <= last {
                if acceptedInThisBatch && (originalLastID == nil || record.journalEventID > originalLastID!) {
                    return unavailable(.outOfOrderEvent, admitted: admitted)
                }
                continue
            }

            let event = record.event
            apply(event)
            admitted.append(event)
            lastJournalEventID = record.journalEventID
            acceptedInThisBatch = true
        }

        if let latest = admitted.last {
            health = healthAfter(admitting: latest)
        }
        return HookApprovalJournalReadResult(events: admitted, checkpoint: checkpoint(), health: health)
    }

    private func apply(_ event: HookApprovalEvent) {
        switch event {
        case .permissionRequest(let value):
            unresolved[value.journalEventID] = HookApprovalPendingEvidence(journalEventID: value.journalEventID, owner: value.owner, observedAt: value.observedAt)
        case .postToolUse(let value):
            let matching = unresolved.values.filter { $0.owner == value.owner }
            if matching.count == 1, let pending = matching.first {
                unresolved.removeValue(forKey: pending.journalEventID)
            }
        case .stop(let value):
            unresolved = unresolved.filter { $0.value.owner != value.owner }
        case .sourceHealth:
            break
        }
    }

    private func healthAfter(admitting event: HookApprovalEvent) -> HookApprovalSourceHealth {
        switch event {
        case .sourceHealth(let value): return value
        case .permissionRequest(let value), .postToolUse(let value), .stop(let value):
            return HookApprovalSourceHealth(sourceID: value.owner.sourceID, state: .available, observedAt: value.observedAt)
        }
    }

    private func unavailable(_ reason: HookApprovalJournalHealthReason, admitted: [HookApprovalEvent]) -> HookApprovalJournalReadResult {
        health = HookApprovalSourceHealth(sourceID: sourceID, state: .unavailable, observedAt: Date(), reason: reason)
        return HookApprovalJournalReadResult(events: admitted, checkpoint: checkpoint(), health: health)
    }
}
