import Foundation
import Combine

enum APIError: LocalizedError {
    case unauthorized
    case message(String)
    case conflict(String)
    case invalid(String)
    case forbidden(String)
    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Tu sesión venció o cambió tu acceso. Inicia sesión de nuevo."
        case .message(let message): return message
        case .conflict(let message): return message
        case .invalid(let message): return message
        case .forbidden(let message): return message
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
final class PayrollClient: ObservableObject {
    nonisolated static let productionURL = URL(string: "https://jhonalexcastano.com")!
    let baseURL: URL
    private let vault: SessionStoring
    private let session: URLSession
    private let decoder = JSONDecoder()
    let offlineCache: OfflineResponseCache
    @Published private(set) var usingOfflineCopy = false
    @Published private(set) var cacheRevision = 0
    @Published private(set) var offlineSyncMessage: String?
    @Published private(set) var syncingOffline = false
    var onSessionInvalidated: (() -> Void)?
    private var syncTask: Task<Void, Never>?
    private var storageFailures = 0
    private var cacheGeneration = 0
    private let automaticOfflineSync: Bool
    let agendaCache: AgendaOfflineCache
    private var cookieName: String { "__Host-jac_session" }
    private var origin: String { baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }

    init(baseURL: URL = PayrollClient.productionURL, vault: SessionStoring? = nil, configuration: URLSessionConfiguration = .ephemeral, agendaCache: AgendaOfflineCache? = nil, offlineCache: OfflineResponseCache? = nil, automaticallyDownloadOffline: Bool? = nil) {
        precondition(baseURL.scheme == "https" && baseURL.host != nil && baseURL.path.isEmpty && baseURL.user == nil && baseURL.query == nil)
        self.baseURL = baseURL
        self.vault = vault ?? KeychainSessionStore(account: baseURL.host!)
        self.agendaCache = agendaCache ?? AgendaOfflineCache()
        self.automaticOfflineSync = automaticallyDownloadOffline ?? !baseURL.host!.hasSuffix(".invalid")
        self.offlineCache = offlineCache ?? OfflineResponseCache(root: baseURL.host!.hasSuffix(".invalid") ? FileManager.default.temporaryDirectory.appendingPathComponent("offline-fixture-" + UUID().uuidString) : nil)
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        if let token = try? self.vault.load(), token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil { self.offlineCache.removeOtherSessions(OfflineResponseCache.scope(origin: baseURL.absoluteString, token: token)) }
    }

    func hasSession() throws -> Bool { try vault.load() != nil }
    func agendaScope() throws -> AgendaCacheScope? {
        guard let token = try vault.load(), token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else { return nil }
        return AgendaCacheScope(origin: origin, token: token)
    }
    func cachedAgenda() -> AgendaOfflineRecord? {
        guard let scope = try? agendaScope() else { return nil }
        return agendaCache.load(scope)
    }
    func clearCachedAgenda() { if let scope = try? agendaScope() { agendaCache.remove(scope) } }
    func saveAgenda(_ record: AgendaOfflineRecord, scope: AgendaCacheScope) throws {
        guard scope.id == (try agendaScope())?.id else { throw CancellationError() }
        try agendaCache.save(record, scope: scope)
    }
    func clearSession() throws {
        syncTask?.cancel(); syncTask = nil
        cacheGeneration += 1
        if let scope = try offlineScope() { offlineCache.clear(scope) }
        clearCachedAgenda(); try vault.clear(); TemporaryDocuments.clear()
        usingOfflineCopy = false; syncingOffline = false; offlineSyncMessage = nil; cacheRevision += 1; onSessionInvalidated?()
    }
    func offlineScope() throws -> AgendaCacheScope? {
        guard let token = try vault.load(), token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else { return nil }
        return OfflineResponseCache.scope(origin: origin, token: token)
    }
    func beginOfflineRestore() { usingOfflineCopy = true }
    private func resourceURL(path: String, query: [URLQueryItem]) -> URL {
        var parts = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { parts.queryItems = query.sorted { ($0.name, $0.value ?? "") < ($1.name, $1.value ?? "") } }
        return parts.url!
    }
    private func resourceKey(_ url: URL, revision: Int = 0) -> String { url.absoluteString + "\nrevision=\(revision)" }
    func cached<T: Decodable>(_ type: T.Type, path: String, query: [URLQueryItem] = [], revision: Int = 0) -> T? {
        guard let scope = try? offlineScope(), let record = offlineCache.load(scope, key: resourceKey(resourceURL(path: path, query: query), revision: revision)) else { return nil }
        return try? decoder.decode(type, from: record.data)
    }
    func cachedWorkspace() -> PayrollWorkspace? { cached(PayrollWorkspace.self, path: "api/mobile/payroll", query: [URLQueryItem(name: "workspace", value: "1")]) }
    func cachedNotices(cursor: String = "", boarding: String? = nil) -> NoticeFeed? {
        guard let first = cached(NoticeFeed.self, path: "api/notices", query: (cursor.isEmpty ? [] : [URLQueryItem(name: "cursor", value: cursor)]) + (boarding.map { [URLQueryItem(name: "boarding", value: $0)] } ?? [])) else { return nil }
        var items = first.notices, next = first.nextCursor
        if usingOfflineCopy, let scope = try? offlineScope() {
            items = []
            for entry in offlineCache.entries(scope) {
                guard let parts = URLComponents(string: entry.url), parts.path == "/api/notices", parts.queryItems?.contains(where: { $0.name == "item" }) != true,
                      (parts.queryItems?.contains(where: { $0.name == "boarding" }) == true) == (boarding != nil),
                      let saved = offlineCache.load(scope, key: entry.key), let page = try? decoder.decode(NoticeFeed.self, from: saved.data) else { continue }
                items += page.notices
            }
            if let boarding { items = items.filter { boarding == "history" ? ($0.travelDate ?? "") < BoardingClock.today() : ($0.travelDate ?? "") >= BoardingClock.today() } }
            next = ""
        }
        var unique: [String: JACNotice] = [:]
        for item in items { let latest = cachedNotice(item.id) ?? item; if (latest.revision ?? 1) >= (unique[item.id]?.revision ?? 0) { unique[item.id] = latest } }
        let sorted = unique.values.sorted { boarding == nil ? $0.createdAt > $1.createdAt : (boarding == "history" ? ($0.travelDate ?? "") > ($1.travelDate ?? "") : ($0.travelDate ?? "") < ($1.travelDate ?? "")) }
        return NoticeFeed(notices: sorted, nextCursor: next, settings: first.settings, users: first.users, boardingUsers: first.boardingUsers, today: BoardingClock.today())
    }
    func cachedExpenses() -> TravelExpenseFeed? {
        guard let first = cached(TravelExpenseFeed.self, path: "api/expenses") else { return nil }
        guard usingOfflineCopy, let scope = try? offlineScope() else { return first }
        var items: [String: TravelExpense] = [:]
        for entry in offlineCache.entries(scope) where URL(string: entry.url)?.path == "/api/expenses" {
            guard let saved = offlineCache.load(scope, key: entry.key), let page = try? decoder.decode(TravelExpenseFeed.self, from: saved.data) else { continue }
            for item in page.expenses where item.version >= (items[item.id]?.version ?? 0) { items[item.id] = item }
        }
        return TravelExpenseFeed(expenses: items.values.sorted { $0.expenseDate > $1.expenseDate }, nextCursor: "", reviewer: first.reviewer, employees: first.employees, periods: first.periods)
    }
    func cachedNotice(_ id: String) -> JACNotice? {
        struct Wrapper: Decodable { let item: JACNotice }
        return cached(Wrapper.self, path: "api/notices", query: [URLQueryItem(name: "item", value: id)])?.item
    }
    private func cacheable(_ path: String, query: [URLQueryItem]) -> Bool {
        if path == "api/calendar" { return !query.contains { $0.name == "action" } }
        return ["api/mobile/payroll", "api/notices", "api/notices/pdf", "api/notices/file", "api/payroll/export", "api/payroll/email", "api/users", "api/expenses", "api/expenses/file"].contains(path)
    }

    private func request(path: String, query: [URLQueryItem] = [], body: JSONValue? = nil, document: Bool = false, forceNetwork: Bool = false, cacheRevision: Int = 0) async throws -> (Data, HTTPURLResponse) {
        let url = resourceURL(path: path, query: query)
        let key = resourceKey(url, revision: cacheRevision)
        let scope = try offlineScope(), generation = cacheGeneration
        let canCache = body == nil && cacheable(path, query: query)
        let saved = canCache ? scope.flatMap { offlineCache.load($0, key: key) } : nil
        if let saved, let response = saved.response, !forceNetwork, usingOfflineCopy { return (saved.data, response) }
        if usingOfflineCopy, body == nil, !forceNetwork, saved == nil { throw APIError.message("Este contenido todavía no está descargado. Conéctate para guardarlo en este iPhone.") }
        if let body, usingOfflineCopy, path != "api/auth" || !["logout", "login", "activate"].contains(body["action"].text) {
            throw APIError.invalid("Estás consultando una copia guardada. Conéctate antes de guardar cambios.")
        }
        var request = URLRequest(url: url)
        if saved != nil { request.timeoutInterval = 5 }
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
        let data: Data, rawResponse: URLResponse
        do { (data, rawResponse) = try await session.data(for: request) }
        catch {
            guard sentToken == (try vault.load()), generation == cacheGeneration else { throw CancellationError() }
            if AgendaOfflineCache.isUnavailable(error) {
                usingOfflineCopy = true
                if let saved, let response = saved.response, !forceNetwork { return (saved.data, response) }
            }
            throw error
        }
        let response = rawResponse
        guard let response = response as? HTTPURLResponse else { throw APIError.message("El servidor no respondió correctamente.") }
        // A response from a previous login must not restore payroll data or
        // invalidate the session of a user who signed in while it was pending.
        guard sentToken == (try vault.load()), generation == cacheGeneration else { throw CancellationError() }
        if response.statusCode == 401 || (300..<400).contains(response.statusCode) {
            if sentToken == (try vault.load()) { try clearSession() }
            throw APIError.unauthorized
        }
        if [500, 502, 503, 504].contains(response.statusCode), let saved, let result = saved.response, !forceNetwork {
            usingOfflineCopy = true; return (saved.data, result)
        }
        guard (200..<300).contains(response.statusCode) else {
            if path == "api/mobile/payroll", query.contains(where: { $0.name == "workspace" }), response.statusCode == 403 { try clearSession(); throw APIError.unauthorized }
            if let scope, body == nil, [403, 404, 410].contains(response.statusCode) {
                if path.hasPrefix("api/notices"), let id = query.first(where: { ["id", "item"].contains($0.name) })?.value { removeCachedNotice(id, scope: scope) }
                else { offlineCache.remove(scope) { URL(string: $0.url)?.path.hasPrefix("/" + path) == true } }
                cacheGeneration += 1; syncTask?.cancel(); syncTask = nil; syncingOffline = false
                offlineSyncMessage = "Se conserva lo descargado. Quedan datos o adjuntos por actualizar."
                TemporaryDocuments.clear(); self.cacheRevision += 1
            }
            struct ServerError: Decodable { let error: String }
            let message = (try? decoder.decode(ServerError.self, from: data).error) ?? "No se pudo completar la operación. Intenta de nuevo."
            if response.statusCode == 409 { throw APIError.conflict(message) }
            if response.statusCode == 403 { if path == "api/calendar" { clearCachedAgenda() }; throw APIError.forbidden(message) }
            if response.statusCode == 400 || response.statusCode == 413 { throw APIError.invalid(message) }
            throw APIError.message(message)
        }
        if path == "api/auth" {
            let fields = Dictionary(uniqueKeysWithValues: response.allHeaderFields.map { (String(describing: $0.key), String(describing: $0.value)) })
            if let cookie = HTTPCookie.cookies(withResponseHeaderFields: fields, for: baseURL).first(where: { $0.name == cookieName }) {
                if cookie.value.isEmpty { try clearSession() }
                else if cookie.value.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil { if cookie.value != sentToken { if let scope { offlineCache.clear(scope) }; clearCachedAgenda(); TemporaryDocuments.clear() }; try vault.save(cookie.value); if let currentScope = try offlineScope() { offlineCache.removeOtherSessions(currentScope) } }
            }
        }
        if path == "api/mobile/payroll", query.contains(where: { $0.name == "workspace" }), body == nil { usingOfflineCopy = false }
        if canCache, let scope {
            do { try saveOffline(data, response: response, key: key, revision: cacheRevision, scope: scope) }
            catch { storageFailures += 1; offlineSyncMessage = "No se pudo guardar toda la copia local: " + error.localizedDescription }
        }
        return (data, response)
    }

    private func saveOffline(_ data: Data, response: HTTPURLResponse, key: String, revision: Int, scope: AgendaCacheScope) throws {
        guard let url = response.url else { return }
        let mime = response.mimeType ?? "application/json"
        if url.path == "/api/notices/file" || url.path == "/api/notices/pdf" || url.path == "/api/expenses/file" {
            guard data.count <= 10 * 1024 * 1024, (try? NoticeUpload.mime(data)) == mime else { throw APIError.message("No se recibió un adjunto válido para guardar.") }
        } else if !url.path.hasSuffix("/export"), (try? JSONDecoder().decode(JSONValue.self, from: data)) == nil { throw APIError.message("No se recibió información válida para guardar.") }
        if url.path == "/api/expenses", let feed = try? decoder.decode(TravelExpenseFeed.self, from: data) {
            for item in feed.expenses {
                offlineCache.remove(scope) { entry in
                    guard let parts = URLComponents(string: entry.url), parts.path == "/api/expenses/file", parts.queryItems?.first(where: { $0.name == "id" })?.value == item.id else { return false }
                    return entry.revision != item.version || !item.attachments.contains { $0.id == parts.queryItems?.first(where: { $0.name == "file" })?.value }
                }
            }
        }
        if url.path == "/api/calendar", let calendar = try? decoder.decode(AgendaData.self, from: data) {
            offlineCache.remove(scope) { entry in
                guard URL(string: entry.url)?.path == "/api/calendar", let saved = offlineCache.load(scope, key: entry.key), let old = try? decoder.decode(AgendaData.self, from: saved.data) else { return false }
                return !calendar.connection.connected || old.connection.revision != calendar.connection.revision || old.connection.selected?.id != calendar.connection.selected?.id
            }
            if !calendar.connection.connected || calendar.connection.selected == nil { clearCachedAgenda() }
        }
        let headers = ["Content-Type": response.value(forHTTPHeaderField: "Content-Type") ?? mime,
                       "Content-Disposition": response.value(forHTTPHeaderField: "Content-Disposition") ?? ""]
        try offlineCache.save(OfflineResponse(key: key, url: url.absoluteString, headers: headers, data: data, receivedAt: Date(), revision: revision), scope: scope)
        if url.path == "/api/notices", let json = try? decoder.decode(JSONValue.self, from: data) {
            let items = json["item"].fields.isEmpty ? json["notices"].elements : [json["item"]]
            for item in items where !item["id"].text.isEmpty {
                let id = item["id"].text, currentRevision = max(1, Int(item["revision"].number))
                if let existing = cachedNotice(id), (existing.revision ?? 1) > currentRevision { continue }
                let itemURL = resourceURL(path: "api/notices", query: [URLQueryItem(name: "item", value: id)])
                let bytes = try JSONEncoder().encode(JSONValue.object(["item": item]))
                try offlineCache.save(OfflineResponse(key: resourceKey(itemURL), url: itemURL.absoluteString, headers: ["Content-Type": "application/json"], data: bytes, receivedAt: Date(), revision: currentRevision), scope: scope)
                let allowed = Set(item["attachments"].elements.map { $0["id"].text })
                offlineCache.remove(scope) { entry in
                    guard let parts = URLComponents(string: entry.url), ["/api/notices/file", "/api/notices/pdf"].contains(parts.path), parts.queryItems?.first(where: { $0.name == "id" })?.value == id else { return false }
                    return entry.revision != currentRevision || (parts.path.hasSuffix("/file") && !allowed.contains(parts.queryItems?.first(where: { $0.name == "file" })?.value ?? ""))
                }
            }
        }
        self.cacheRevision += 1
    }
    private func removeCachedNotice(_ id: String, scope: AgendaCacheScope) {
        offlineCache.remove(scope) { entry in
            guard let parts = URLComponents(string: entry.url), parts.path.hasPrefix("/api/notices") else { return false }
            return parts.queryItems?.contains(where: { ["id", "item"].contains($0.name) && $0.value == id }) == true
        }
        for entry in offlineCache.entries(scope) where URL(string: entry.url)?.path == "/api/notices" {
            guard let saved = offlineCache.load(scope, key: entry.key), var json = try? decoder.decode(JSONValue.self, from: saved.data), !json["notices"].elements.isEmpty else { continue }
            json["notices"] = .array(json["notices"].elements.filter { $0["id"].text != id })
            if let bytes = try? JSONEncoder().encode(json) { try? offlineCache.save(OfflineResponse(key: saved.key, url: saved.url, headers: saved.headers, data: bytes, receivedAt: Date(), revision: saved.revision), scope: scope) }
        }
        cacheRevision += 1
    }
    func rememberWorkspace(_ workspace: PayrollWorkspace) {
        guard let scope = try? offlineScope() else { return }
        let url = resourceURL(path: "api/mobile/payroll", query: [URLQueryItem(name: "workspace", value: "1")])
        offlineCache.remove(scope) { URL(string: $0.url)?.path == "/api/payroll/export" && $0.revision != workspace.version }
        do { try offlineCache.save(OfflineResponse(key: resourceKey(url), url: url.absoluteString, headers: ["Content-Type": "application/json"], data: JSONEncoder().encode(workspace), receivedAt: Date(), revision: workspace.version), scope: scope) }
        catch { storageFailures += 1; offlineSyncMessage = "No se pudo guardar la copia local: " + error.localizedDescription }
    }
    func synchronizeOfflineContent(_ workspace: PayrollWorkspace) {
        guard automaticOfflineSync, syncTask == nil, !usingOfflineCopy else { return }
        syncTask = Task { [weak self] in
            guard let self, let token = try? self.vault.load() else { return }
            let generation = self.cacheGeneration, failures = self.storageFailures
            self.syncingOffline = true; self.offlineSyncMessage = "Guardando información y adjuntos para consultar sin conexión…"
            defer { if generation == self.cacheGeneration { self.syncingOffline = false; self.syncTask = nil } }
            var partial = false
            @MainActor func validate() throws {
                try Task.checkCancellation()
                guard generation == self.cacheGeneration, token == (try self.vault.load()), !self.usingOfflineCopy else { throw CancellationError() }
            }
            @MainActor func optionalRead(_ action: @MainActor () async throws -> Void) async throws {
                try validate()
                do { try await action() }
                catch { try validate(); partial = true }
            }
            do {
                var noticeIDs = Set<String>(), fetchedKeys = Set<String>()
                for boarding: String? in ["current", nil, "history"] {
                    var cursor = "", visited = Set<String>()
                    repeat {
                        try validate()
                        let query = (cursor.isEmpty ? [] : [URLQueryItem(name: "cursor", value: cursor)]) + (boarding.map { [URLQueryItem(name: "boarding", value: $0)] } ?? [])
                        let (bytes, _) = try await self.request(path: "api/notices", query: query, forceNetwork: true)
                        fetchedKeys.insert(self.resourceKey(self.resourceURL(path: "api/notices", query: query)))
                        let page = try self.decoder.decode(NoticeFeed.self, from: bytes)
                        for item in page.notices {
                            try validate(); noticeIDs.insert(item.id)
                            for file in item.files {
                                let path = item.attachments == nil && item.kind == "itinerary" ? "api/notices/pdf" : "api/notices/file"
                                let query = [URLQueryItem(name: "id", value: item.id)] + (path.hasSuffix("/file") ? [URLQueryItem(name: "file", value: file.id)] : [])
                                let key = self.resourceKey(self.resourceURL(path: path, query: query), revision: item.revision ?? 1)
                                if let scope = try self.offlineScope(), self.offlineCache.load(scope, key: key) == nil { try await optionalRead { _ = try await self.request(path: path, query: query, document: true, forceNetwork: true, cacheRevision: item.revision ?? 1) } }
                            }
                        }
                        cursor = page.nextCursor
                        guard cursor.isEmpty || visited.insert(cursor).inserted else { throw APIError.message("No se pudo completar la copia de avisos.") }
                    } while !cursor.isEmpty
                }
                if let scope = try self.offlineScope() {
                    let obsolete = self.offlineCache.entries(scope).compactMap { entry -> String? in
                        guard let parts = URLComponents(string: entry.url), parts.path.hasPrefix("/api/notices") else { return nil }
                        return parts.queryItems?.first(where: { ["id", "item"].contains($0.name) })?.value
                    }.filter { !noticeIDs.contains($0) }
                    for id in Set(obsolete) { self.removeCachedNotice(id, scope: scope) }
                    self.offlineCache.remove(scope) { entry in
                        guard let parts = URLComponents(string: entry.url), parts.path == "/api/notices", parts.queryItems?.contains(where: { $0.name == "item" }) != true else { return false }
                        return !fetchedKeys.contains(entry.key)
                    }
                }
                for period in workspace.periods {
                    let query = [URLQueryItem(name: "period", value: period.id)]
                    if self.cached(PeriodDetail.self, path: "api/mobile/payroll", query: query)?.version == workspace.version { continue }
                    try await optionalRead { _ = try await self.request(path: "api/mobile/payroll", query: query, forceNetwork: true) }
                }
                try await optionalRead { _ = try await self.agenda(month: CalendarClock.month(Date())) }
                var cursor = "", visited = Set<String>()
                repeat {
                    try validate()
                    let (bytes, _) = try await self.request(path: "api/expenses", query: cursor.isEmpty ? [] : [URLQueryItem(name: "cursor", value: cursor)], forceNetwork: true)
                    let page = try self.decoder.decode(TravelExpenseFeed.self, from: bytes)
                    for expense in page.expenses { for file in expense.attachments {
                        let query = [URLQueryItem(name: "id", value: expense.id), URLQueryItem(name: "file", value: file.id)]
                        if let scope = try self.offlineScope(), self.offlineCache.load(scope, key: self.resourceKey(self.resourceURL(path: "api/expenses/file", query: query), revision: expense.version)) == nil { try await optionalRead { _ = try await self.request(path: "api/expenses/file", query: query, document: true, forceNetwork: true, cacheRevision: expense.version) } }
                    } }
                    cursor = page.nextCursor; guard cursor.isEmpty || visited.insert(cursor).inserted else { throw APIError.message("No se pudo completar la copia de gastos.") }
                } while !cursor.isEmpty
                if workspace.user.isOwner { try await optionalRead { _ = try await self.users() } }
                if workspace.user.itinerariesOnly != true {
                    try await optionalRead { _ = try await self.mail(periodID: nil) }
                    for period in workspace.periods { try await optionalRead { _ = try await self.mail(periodID: period.id) } }
                }
                try validate()
                self.offlineSyncMessage = partial || failures != self.storageFailures ? "Se conserva lo descargado. Quedan datos o adjuntos por actualizar." : "La última información y sus adjuntos están guardados en este iPhone."
            } catch { if generation == self.cacheGeneration { self.offlineSyncMessage = "Se conserva lo descargado. Quedan datos o adjuntos por actualizar." } }
        }
    }

    func login(username: String, password: String, keepSignedIn: Bool = false) async throws {
        _ = try await request(path: "api/auth", body: .object(["action": .string("login"), "username": .string(username.trimmingCharacters(in: .whitespacesAndNewlines)), "password": .string(password), "keepSignedIn": .bool(keepSignedIn)]))
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
        if usingOfflineCopy { try clearSession(); return }
        do { _ = try await request(path: "api/auth", body: .object(["action": .string("logout"), "notificationDeviceId": .string(JACNotifications.deviceID)])) }
        catch { try clearSession(); throw error }
        try clearSession()
    }
    func workspace(forceNetwork: Bool = false) async throws -> PayrollWorkspace {
        let (data, _) = try await request(path: "api/mobile/payroll", query: [URLQueryItem(name: "workspace", value: "1")], forceNetwork: forceNetwork)
        return try decoder.decode(PayrollWorkspace.self, from: data)
    }
    func notices(cursor: String = "", boarding: String? = nil) async throws -> NoticeFeed {
        let (data, _) = try await request(path: "api/notices", query: (cursor.isEmpty ? [] : [URLQueryItem(name: "cursor", value: cursor)]) + (boarding.map { [URLQueryItem(name:"boarding",value:$0)] } ?? []))
        return try decoder.decode(NoticeFeed.self, from: data)
    }
    func noticeCommand(_ command: JSONValue) async throws { _ = try await request(path: "api/notices", body: command) }
    func notice(id: String) async throws -> JACNotice {
        struct Response: Decodable { let item: JACNotice }
        let (data, _) = try await request(path: "api/notices", query: [URLQueryItem(name: "item", value: id)])
        return try decoder.decode(Response.self, from: data).item
    }
    func itinerary(_ notice: JACNotice) async throws -> ExportedDocument {
        let (data, response) = try await request(path: "api/notices/pdf", query: [URLQueryItem(name: "id", value: notice.id)], document: true, cacheRevision: notice.revision ?? 1)
        guard response.mimeType == "application/pdf", data.count <= 10*1024*1024, data.starts(with: Data("%PDF-".utf8)) else { throw APIError.message("No se recibió un PDF válido.") }
        let name = (notice.filename as NSString).lastPathComponent
        return try TemporaryDocuments.save(data, filename: name.isEmpty ? "Itinerario.pdf" : name)
    }
    func publishNotice(id: String, kind: String, title: String, body: String, recipients: [String], files: [NoticeUpload], travelDate: String? = nil) async throws {
        guard files.count <= 5, files.reduce(0, { $0 + $1.data.count }) <= 10*1024*1024 else { throw APIError.message("Elige hasta 5 archivos que sumen como máximo 10 MB.") }
        for file in files { _ = try NoticeUpload.mime(file.data) }
        var payload: [String: JSONValue] = ["id": .string(id), "kind": .string(kind), "title": .string(title), "body": .string(body), "recipients": .array(recipients.sorted().map(JSONValue.string)), "files": .array(files.map { .object(["filename": .string($0.filename), "data": .string($0.data.base64EncodedString())]) })]
        if let travelDate { payload["travelDate"] = .string(travelDate) }; _ = try await request(path:"api/notices/publish",body:.object(payload))
    }
    func noticeFile(_ item: JACNotice, file: NoticeAttachment) async throws -> ExportedDocument {
        if let latest = cachedNotice(item.id), (latest.revision ?? 1) > (item.revision ?? 1) || !latest.files.contains(where: { $0.id == file.id }) { throw APIError.invalid("El documento cambió. Abre la versión más reciente.") }
        let (data, response) = try await request(path: "api/notices/file", query: [URLQueryItem(name: "id", value: item.id), URLQueryItem(name: "file", value: file.id)], document: true, cacheRevision: item.revision ?? 1)
        guard data.count <= 10*1024*1024, response.mimeType == file.mimeType, (try NoticeUpload.mime(data)) == file.mimeType else { throw APIError.message("No se recibió un archivo válido.") }
        let name = (file.filename as NSString).lastPathComponent
        return try TemporaryDocuments.save(data, filename: name.isEmpty ? "Adjunto" : name)
    }
    func confirmNotice(_ item: JACNotice) async throws {
        try await noticeCommand(.object(["action":.string("confirm"),"id":.string(item.id),"revision":.number(Double(item.revision ?? 1))]))
    }
    func updateItinerary(_ item: JACNotice, requestID: String, title: String, body: String, summary: String, files: [NoticeUpload]) async throws {
        _ = try await request(path:"api/notices/publish",query:[URLQueryItem(name:"update",value:"1")],body:.object(["id":.string(item.id),"requestId":.string(requestID),"revision":.number(Double(item.revision ?? 1)),"title":.string(title),"body":.string(body),"summary":.string(summary),"files":try travelUploads(files)]))
    }
    private func travelUploads(_ files:[NoticeUpload]) throws -> JSONValue {
        guard !files.isEmpty,files.count <= 5,files.reduce(0, { $0+$1.data.count }) <= 10*1024*1024 else { throw APIError.message("Adjunta de 1 a 5 archivos que sumen como máximo 10 MB.") }
        for f in files { _ = try NoticeUpload.mime(f.data) }
        return .array(files.map { .object(["filename":.string($0.filename),"data":.string($0.data.base64EncodedString())]) })
    }
    func expenses(cursor:String = "") async throws -> TravelExpenseFeed {
        let (data,_) = try await request(path:"api/expenses",query:cursor.isEmpty ? [] : [URLQueryItem(name:"cursor",value:cursor)])
        return try decoder.decode(TravelExpenseFeed.self,from:data)
    }
    func submitExpense(id:String,concept:String,amount:Double,date:String,note:String,files:[NoticeUpload]) async throws {
        _ = try await request(path:"api/expenses",body:.object(["id":.string(id),"concept":.string(concept),"amount":.number(amount),"expenseDate":.string(date),"note":.string(note),"files":try travelUploads(files)]))
    }
    func reviewExpense(_ expense:TravelExpense,approve:Bool,reason:String,employeeID:String,periodID:String) async throws {
        _ = try await request(path:"api/expenses",query:[URLQueryItem(name:"review",value:"1")],body:.object(["id":.string(expense.id),"version":.number(Double(expense.version)),"decision":.string(approve ? "approve" : "reject"),"reason":.string(reason),"employeeId":.string(employeeID),"periodId":.string(periodID)]))
    }
    func expenseFile(_ expense:TravelExpense,file:NoticeAttachment) async throws -> ExportedDocument {
        let (data,response) = try await request(path:"api/expenses/file",query:[URLQueryItem(name:"id",value:expense.id),URLQueryItem(name:"file",value:file.id)],document:true,cacheRevision:expense.version)
        guard data.count <= 10*1024*1024,response.mimeType == file.mimeType,(try NoticeUpload.mime(data)) == file.mimeType else { throw APIError.message("No se recibió un comprobante válido.") }
        return try TemporaryDocuments.save(data,filename:(file.filename as NSString).lastPathComponent)
    }
    func deleteNotice(_ item: JACNotice) async throws {
        try await noticeCommand(.object(["action": .string(item.kind == "boarding_pass" ? "deleteBoardingPass" : item.kind == "itinerary" ? "deleteItinerary" : "deleteAlert"), "id": .string(item.id), "confirmation": .string(item.id)]))
        if let scope = try offlineScope() { removeCachedNotice(item.id, scope: scope) }
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
    func agenda(month: String) async throws -> AgendaData {
        let (data, _) = try await request(path: "api/calendar", query: [URLQueryItem(name: "month", value: month)])
        return try decoder.decode(AgendaData.self, from: data)
    }
    func agendaCalendars() async throws -> [AgendaCalendar] {
        let (data, _) = try await request(path: "api/calendar", query: [URLQueryItem(name: "action", value: "calendars")])
        return try decoder.decode(AgendaCalendars.self, from: data).calendars
    }
    func saveAgendaEvent(_ draft: AgendaEventDraft, revision: Int, event: AgendaEvent?, requestID: UUID) async throws -> AgendaEventMutation {
        var body: [String: JSONValue] = ["action": .string(event == nil ? "createEvent" : "updateEvent"), "revision": .number(Double(revision)), "event": draft.value]
        if let event { body["eventId"] = .string(event.id); body["etag"] = .string(event.etag ?? "") }
        else { body["requestId"] = .string(requestID.uuidString.lowercased()) }
        let (data, _) = try await request(path: "api/calendar", body: .object(body))
        return try decoder.decode(AgendaEventMutation.self, from: data)
    }
    func agendaOperation(action: String, revision: Int, calendarID: String? = nil) async throws -> AgendaMutation {
        var body: [String: JSONValue] = ["action": .string(action), "revision": .number(Double(revision))]
        if let calendarID { body["calendarId"] = .string(calendarID) }
        let (data, _) = try await request(path: "api/calendar", body: .object(body))
        return try decoder.decode(AgendaMutation.self, from: data)
    }
    func startAgenda() async throws -> AgendaStart {
        let (data, _) = try await request(path: "api/calendar", body: .object(["action": .string("connect"), "native": .bool(true)]))
        let start = try decoder.decode(AgendaStart.self, from: data)
        guard start.url.scheme == "https", start.url.host == baseURL.host, start.url.port == baseURL.port,
              start.url.path == "/api/calendar/connect", start.url.user == nil, start.url.password == nil, start.url.fragment == nil,
              start.nonce.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else {
            throw APIError.message("La autorización de Agenda no es válida.")
        }
        return start
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
        let (data, response) = try await request(path: "api/payroll/export", query: query, document: true, cacheRevision: cachedWorkspace()?.version ?? 0)
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
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        let url = folder.appendingPathComponent(filename)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        return ExportedDocument(id: id, url: url)
    }
    static func remove(_ document: ExportedDocument) { try? FileManager.default.removeItem(at: root.appendingPathComponent(document.id.uuidString)) }
    static func clear() { try? FileManager.default.removeItem(at: root) }
}
