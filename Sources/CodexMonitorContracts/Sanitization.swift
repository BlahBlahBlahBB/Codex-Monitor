import Foundation

public struct SanitizedDiagnostic: Codable, Sendable, Equatable {
    public let sourceKind: SourceKind
    public let code: String
    public let method: String?
    public let safeFieldNames: [String]
    public let transport: TransportProvenance?

    public init(sourceKind: SourceKind, code: String, method: String? = nil, safeFieldNames: [String] = [], transport: TransportProvenance? = nil) {
        self.sourceKind = sourceKind
        self.code = code
        self.method = method
        self.safeFieldNames = safeFieldNames
        self.transport = transport
    }
}

public enum DiagnosticSanitizer {
    private static let sensitiveFragments = [
        "authorization", "credential", "secret", "password", "token", "email",
        "content", "text", "preview", "title", "path", "cookie", "key"
    ]

    /// Returns names only, never values. This avoids retaining conversation text,
    /// socket paths, credentials, and private protocol payloads in diagnostics.
    public static func summarize(sourceKind: SourceKind, code: String, method: String? = nil, payload: JSONValue? = nil, transport: TransportProvenance? = nil) -> SanitizedDiagnostic {
        let names = payload?.objectValue?.keys.filter(isSafeFieldName).sorted() ?? []
        return SanitizedDiagnostic(sourceKind: sourceKind, code: code, method: safeMethod(method), safeFieldNames: names, transport: transport)
    }

    private static func isSafeFieldName(_ key: String) -> Bool {
        let lower = key.lowercased()
        return !sensitiveFragments.contains { lower.contains($0) }
    }

    private static func safeMethod(_ method: String?) -> String? {
        guard let method,
              method.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "/" || $0 == "_" || $0 == "-" }) else {
            return nil
        }
        return method
    }
}
