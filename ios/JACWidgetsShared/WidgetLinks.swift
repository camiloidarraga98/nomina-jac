import Foundation

enum JACWidgetRoute: Equatable, Sendable {
    case calendar
    case photography(folderID: String?)

    init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "jacnomina", parts.host?.lowercased() == "widget",
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.fragment == nil else { return nil }
        let query = parts.queryItems ?? []
        switch parts.path {
        case "/calendar":
            guard query.isEmpty else { return nil }
            self = .calendar
        case "/fotografia":
            guard query.allSatisfy({ $0.name == "folder" }), query.count <= 1 else { return nil }
            if let folder = query.first?.value {
                guard Self.validFolder(folder) else { return nil }
                self = .photography(folderID: folder)
            } else {
                guard query.isEmpty else { return nil }
                self = .photography(folderID: nil)
            }
        default: return nil
        }
    }
    static func validFolder(_ id: String) -> Bool {
        id == "jac_r2_root" || id.range(of: "^r2_[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", options: .regularExpression) != nil
    }
    var url: URL {
        switch self {
        case .calendar:
            return URL(string: "jacnomina://widget/calendar")!
        case .photography(let folder):
            var parts = URLComponents()
            parts.scheme = "jacnomina"; parts.host = "widget"; parts.path = "/fotografia"
            if let folder, Self.validFolder(folder) { parts.queryItems = [URLQueryItem(name: "folder", value: folder)] }
            return parts.url!
        }
    }
}
