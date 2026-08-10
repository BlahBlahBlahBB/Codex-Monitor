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
    private static let sensitiveFragments = ["authorization", "bearer", "credential", "secret", "password", "token", "email", "content", "text", "preview", "title", "path", "cookie", "key"]
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
        let lower = key.lowercased()
        return !sensitiveFragments.contains { lower.contains($0) } && key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
    }
}
