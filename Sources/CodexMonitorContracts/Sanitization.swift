import Foundation

/// Closed diagnostic vocabulary. Raw server strings can never become a code.
public enum DiagnosticCode: String, Codable, Sendable, Equatable, CaseIterable {
    case accountReadResponseDiscarded, unsupportedNotification, malformedMessage, socketClosed, sourceUnavailable
}

/// Only stable, phase-authorized method names may be emitted.
public enum SanitizedMethod: String, Codable, Sendable, Equatable, CaseIterable {
    case accountRead = "account/read"
    case threadStarted = "thread/started"
    case threadStatusChanged = "thread/status/changed"
    case turnStarted = "turn/started"
    case itemStarted = "item/started"
    case itemCompleted = "item/completed"
    case turnCompleted = "turn/completed"
    case threadTokenUsageUpdated = "thread/tokenUsage/updated"
}

public struct SanitizedDiagnostic: Codable, Sendable, Equatable {
    public let sourceKind: SourceKind
    public let code: DiagnosticCode
    public let method: SanitizedMethod?
    public let safeFieldNames: [String]
    public let transport: TransportProvenance?

    init(sourceKind: SourceKind, code: DiagnosticCode, method: SanitizedMethod? = nil, safeFieldNames: [String] = [], transport: TransportProvenance? = nil) {
        self.sourceKind = sourceKind; self.code = code; self.method = method; self.safeFieldNames = safeFieldNames; self.transport = transport
    }
}

public enum DiagnosticSanitizer {
    /// Closed machine-readable vocabulary. Unknown names are dropped even when
    /// they look harmless; a negative secret blacklist is not a security gate.
    private static let allowedFieldNames: Set<String> = [
        "id", "threadId", "turnId", "item", "thread", "turn", "type", "status",
        "startedAtMs", "completedAtMs", "tokenUsage", "last", "total",
        "cachedInputTokens", "inputTokens", "outputTokens", "reasoningOutputTokens", "totalTokens",
        "platformFamily", "platformOs"
    ]
    public static func summarize(sourceKind: SourceKind, code: DiagnosticCode, method: SanitizedMethod? = nil, payload: JSONValue? = nil, transport: TransportProvenance? = nil) -> SanitizedDiagnostic {
        SanitizedDiagnostic(sourceKind: sourceKind, code: code, method: method, safeFieldNames: safeNames(in: payload).sorted(), transport: transport)
    }

    private static func safeNames(in value: JSONValue?) -> [String] {
        guard let value else { return [] }
        switch value {
        case .object(let object):
            return object.flatMap { key, value in
                let own = isSafeFieldName(key) ? [key] : []
                return own + safeNames(in: value)
            }
        case .array(let values): return values.flatMap(safeNames)
        default: return []
        }
    }
    private static func isSafeFieldName(_ key: String) -> Bool {
        allowedFieldNames.contains(key)
    }
}
