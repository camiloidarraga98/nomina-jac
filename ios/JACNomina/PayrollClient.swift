import Foundation

enum APIError: LocalizedError {
    case unauthorized
    case message(String)
    case conflict(String)
    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Tu sesión venció o cambió tu acceso. Inicia sesión de nuevo."
        case .message(let message): return message
        case .conflict(let message): return message
        }
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward payroll credentials to a redirect destination.
        completionHandler(nil)
    }
}

@MainActor
final class PayrollClient {
    nonisolated static let productionURL = URL(string: "https://jhonalexcastano.com")!
    let baseURL: URL
    private let vault: SessionStoring
    private let session: URLSession
    private let decoder = JSONDecoder()
    private var cookieName: String { "__Host-jac_session" }
    private var origin: String { baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }

    init(baseURL: URL = PayrollClient.productionURL, vault: SessionStoring? = nil, configuration: URLSessionConfiguration = .ephemeral) {
        precondition(baseURL.scheme == "https" && baseURL.host != nil && baseURL.path.isEmpty && baseURL.user == nil && baseURL.query == nil)
        self.baseURL = baseURL
        self.vault = vault ?? KeychainSessionStore(account: baseURL.host!)
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }

    func hasSession() throws -> Bool { try vault.load() != nil }
    func clearSession() throws { try vault.clear(); TemporaryDocuments.clear() }

    private func request(path: String, query: [URLQueryItem] = [], body: JSONValue? = nil, document: Bool = false) async throws -> (Data, HTTPURLResponse) {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpShouldHandleCookies = false
        request.setValue(document ? "*/*" : "application/json", forHTTPHeaderField: "Accept")
        request.setValue("JACNomina-iPhone/1.0", forHTTPHeaderField: "User-Agent")
        let sentToken = try vault.load()
        if let token = sentToken {
            guard token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else { try clearSession(); throw APIError.unauthorized }
            request.setValue("\(cookieName)=\(token)", forHTTPHeaderField: "Cookie")
        }
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(origin, forHTTPHeaderField: "Origin")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError.message("El servidor no respondió correctamente.") }
        if response.statusCode == 401 || (300..<400).contains(response.statusCode) {
            if sentToken == (try vault.load()) { try clearSession() }
            throw APIError.unauthorized
        }
        guard (200..<300).contains(response.statusCode) else {
            struct ServerError: Decodable { let error: String }
            let message = (try? decoder.decode(ServerError.self, from: data).error) ?? "No se pudo completar la operación. Intenta de nuevo."
            if response.statusCode == 409 { throw APIError.conflict(message) }
            throw APIError.message(message)
        }
        if path == "api/auth" {
            let fields = Dictionary(uniqueKeysWithValues: response.allHeaderFields.map { (String(describing: $0.key), String(describing: $0.value)) })
            if let cookie = HTTPCookie.cookies(withResponseHeaderFields: fields, for: baseURL).first(where: { $0.name == cookieName }) {
                if cookie.value.isEmpty { try clearSession() }
                else if cookie.value.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil { try vault.save(cookie.value) }
            }
        }
        return (data, response)
    }

    func login(username: String, password: String) async throws {
        _ = try await request(path: "api/auth", body: .object(["action": .string("login"), "username": .string(username.trimmingCharacters(in: .whitespacesAndNewlines)), "password": .string(password)]))
        guard try hasSession() else { throw APIError.message("No se pudo guardar la sesión. Intenta de nuevo.") }
    }
    func overview() async throws -> PayrollOverview {
        let (data, _) = try await request(path: "api/mobile/payroll")
        return try decoder.decode(PayrollOverview.self, from: data)
    }
    func detail(periodID: String) async throws -> PeriodDetail {
        let (data, _) = try await request(path: "api/mobile/payroll", query: [URLQueryItem(name: "period", value: periodID)])
        return try decoder.decode(PeriodDetail.self, from: data)
    }
    func changePassword(current: String, new: String) async throws {
        _ = try await request(path: "api/auth", body: .object(["action": .string("password"), "currentPassword": .string(current), "password": .string(new)]))
    }
    func logout() async throws {
        do { _ = try await request(path: "api/auth", body: .object(["action": .string("logout")])) }
        catch { try clearSession(); throw error }
        try clearSession()
    }
    func workspace() async throws -> PayrollWorkspace {
        let (data, _) = try await request(path: "api/mobile/payroll", query: [URLQueryItem(name: "workspace", value: "1")])
        return try decoder.decode(PayrollWorkspace.self, from: data)
    }
    func payroll(_ command: JSONValue) async throws -> PayrollEnvelope {
        let (data, _) = try await request(path: "api/mobile/payroll", body: command)
        return try decoder.decode(PayrollEnvelope.self, from: data)
    }
    func preview(_ command: JSONValue) async throws -> PayrollPreview {
        var body = command; body["action"] = .string("previewEdit")
        let (data, _) = try await request(path: "api/mobile/payroll", body: body)
        return try decoder.decode(PayrollPreview.self, from: data)
    }
    func users() async throws -> UserDirectory {
        let (data, _) = try await request(path: "api/users")
        return try decoder.decode(UserDirectory.self, from: data)
    }
    func updateUser(_ user: ManagedUser) async throws -> OperationNotice {
        let record = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(user))
        return try await notice(path: "api/users", body: .object(["action": .string(user.id.isEmpty ? "create" : "update"), "id": .string(user.id), "version": .number(Double(user.version)), "user": record]))
    }
    func invite(userID: String) async throws -> InvitationResult {
        let (data, _) = try await request(path: "api/users", body: .object(["action": .string("invite"), "id": .string(userID)]))
        return try decoder.decode(InvitationResult.self, from: data)
    }
    func activate(token: String, password: String) async throws {
        _ = try await request(path: "api/auth", body: .object(["action": .string("activate"), "token": .string(token), "password": .string(password)]))
        guard try hasSession() else { throw APIError.message("No se pudo guardar la sesión. Intenta de nuevo.") }
    }
    func mail(periodID: String?) async throws -> PayrollMail {
        let (data, _) = try await request(path: "api/payroll/email", query: periodID.map { [URLQueryItem(name: "period", value: $0)] } ?? [])
        return try decoder.decode(PayrollMail.self, from: data)
    }
    func mailOperation(_ body: JSONValue) async throws -> OperationNotice { try await notice(path: "api/payroll/email", body: body) }
    private func notice(path: String, body: JSONValue) async throws -> OperationNotice {
        let (data, _) = try await request(path: path, body: body)
        return try decoder.decode(OperationNotice.self, from: data)
    }
    func startGmail() async throws -> GmailStart {
        let (data, _) = try await request(path: "api/mobile/gmail", body: .object([:]))
        let start = try decoder.decode(GmailStart.self, from: data)
        guard start.url.scheme == "https", start.url.host == baseURL.host, start.url.port == baseURL.port,
              start.url.path == "/api/mobile/gmail", start.url.user == nil, start.url.password == nil,
              start.nonce.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else {
            throw APIError.message("La autorización recibida no es válida.")
        }
        return start
    }
    func download(periodID: String, format: DocumentFormat, employeeID: String? = nil) async throws -> ExportedDocument {
        var query = [URLQueryItem(name: "period", value: periodID), URLQueryItem(name: "format", value: format.rawValue)]
        if let employeeID { query.append(URLQueryItem(name: "employee", value: employeeID)) }
        let (data, response) = try await request(path: "api/payroll/export", query: query, document: true)
        guard !data.isEmpty else { throw APIError.message("El documento llegó vacío. Intenta de nuevo.") }
        let expectedType = format == .xlsx ? "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" : format == .zip ? "application/zip" : "application/pdf"
        guard response.mimeType == expectedType else { throw APIError.message("No se recibió un documento válido.") }
        let fallback = "nomina-\(UUID().uuidString).\(format.fileExtension)"
        let filename = response.value(forHTTPHeaderField: "Content-Disposition")?.components(separatedBy: "filename=\"").last?.components(separatedBy: "\"").first
        let safeName = filename.map { ($0 as NSString).lastPathComponent } ?? fallback
        return try TemporaryDocuments.save(data, filename: safeName.isEmpty ? fallback : safeName)
    }
}

struct ExportedDocument: Identifiable {
    let id: UUID
    let url: URL
}

enum TemporaryDocuments {
    static var root: URL { FileManager.default.temporaryDirectory.appendingPathComponent("JACPayrollDocuments", isDirectory: true) }
    static func save(_ data: Data, filename: String) throws -> ExportedDocument {
        let id = UUID()
        let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(filename)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return ExportedDocument(id: id, url: url)
    }
    static func remove(_ document: ExportedDocument) { try? FileManager.default.removeItem(at: root.appendingPathComponent(document.id.uuidString)) }
    static func clear() { try? FileManager.default.removeItem(at: root) }
}
