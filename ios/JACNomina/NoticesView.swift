import SwiftUI

struct JACNotice: Decodable, Identifiable {
    let id: String; let kind: String; let title: String; let body: String; let filename: String; let size: Int; let createdAt: String; let read: Bool
    var createdLabel: String {
        guard let date = CalendarClock.instant(createdAt) else { return "Fecha no disponible" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "es_CO"); formatter.timeZone = CalendarClock.calendar.timeZone
        formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
struct NoticeFeed: Decodable {
    let notices: [JACNotice]; let nextCursor: String; let settings: NoticeSettings; let users: [NoticeUser]
}
struct NoticeSettings: Decodable { let version: Int; let slackConnected: Bool; let appleConfigured: Bool; let webPublicKey: String }
struct NoticeUser: Decodable, Identifiable { let id: String; let name: String }

struct NoticesView: View {
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var push = JACNotifications.shared
    let user: PayrollUser
    var kind = "itinerary"
    var initialNotice: String? = nil
    @State private var feed: NoticeFeed?
    @State private var records: [JACNotice] = []
    @State private var error: String?
    @State private var notice: String?
    @State private var detail: JACNotice?
    @State private var editor = false
    @State private var loading = false
    @State private var handledInitial = false
    @State private var incomingKind: String?
    private var effectiveKind: String { incomingKind ?? kind }
    var body: some View {
        List {
            if let error { Section { InlineError(message: error); Button("Reintentar") { Task { await refresh() } } } }
            if let notice { Section { Text(notice).foregroundStyle(JACTheme.action) } }
            Section("Notificaciones") {
                if let message = push.message { Text(message).font(.footnote) }
                Button("Activar en este iPhone") { Task { await push.enable(store.client) } }.accessibilityIdentifier("notices.enable")
                Button("Desactivar en este iPhone") { Task { await push.disable(store.client) } }
                if feed?.settings.appleConfigured == false { Text(user.isOwner ? "Prepara Apple desde Itinerarios → Conexión en el webapp para habilitar los avisos push." : "Camilo está preparando los avisos push del iPhone.").font(.footnote).foregroundStyle(.secondary) }
            }
            if loading && feed == nil { ProgressView("Consultando…") }
            Section(effectiveKind == "itinerary" ? "PDF de itinerarios" : "Avisos del equipo") {
                let items = records.filter { $0.kind == effectiveKind }
                if items.isEmpty && feed != nil { Text(effectiveKind == "itinerary" ? "Todavía no hay itinerarios publicados." : "No tienes alertas en este momento.").foregroundStyle(.secondary) }
                ForEach(items) { item in Button { detail = item } label: { VStack(alignment: .leading, spacing: 7) { Label(item.title, systemImage: item.kind == "itinerary" ? "doc.text" : "bell").font(.headline); Text(item.createdLabel + (item.kind == "itinerary" ? " · PDF" : "") + (item.read ? "" : " · Nuevo")).font(.caption).foregroundStyle(.secondary) } }.buttonStyle(.plain).accessibilityIdentifier("notices.item.\(item.id)") }
                if let cursor = feed?.nextCursor, !cursor.isEmpty { Button("Ver anteriores") { Task { await refresh(cursor) } }.disabled(loading) }
            }
            if effectiveKind == "itinerary", feed?.settings.slackConnected == false { Section { Text(user.isOwner ? "Conecta Slack desde Itinerarios → Conexión en el webapp. Solo se comparten los PDF de #itinerarios-finales." : "Camilo está preparando la conexión de itinerarios.").font(.footnote).foregroundStyle(.secondary) } }
        }.jacSurface().navigationTitle(effectiveKind == "itinerary" ? "Itinerarios" : "Alertas").refreshable { await refresh() }
            .toolbar { if user.isOwner && effectiveKind == "alert" { ToolbarItem(placement: .topBarTrailing) { Button { editor = true } label: { Image(systemName: "plus") }.accessibilityLabel("Crear alerta").accessibilityIdentifier("notices.create").disabled(feed == nil) } } }
            .task { await refresh() }
            .onChange(of: scenePhase) { _, value in if value == .active { Task { await refresh() } } }
            .sheet(item: $detail, onDismiss: { Task { await refresh() } }) { item in NoticeDetail(item: item) }
            .sheet(isPresented: $editor) { if let feed { NoticeComposer(users: feed.users) { notice = "Alerta guardada para los destinatarios elegidos."; await refresh() } } }
    }
    private func refresh(_ cursor: String = "") async {
        guard !loading else { return }; loading = true; defer { loading = false }
        do { let result = try await store.client.notices(cursor: cursor); feed = result; if cursor.isEmpty { records = result.notices } else { records += result.notices.filter { item in !records.contains { $0.id == item.id } } }; error = nil
            if !handledInitial, let initialNotice { handledInitial = true; let item: JACNotice; if let found = records.first(where: { $0.id == initialNotice }) { item = found } else { item = try await store.client.notice(id: initialNotice) }; incomingKind = item.kind; detail = item }
        } catch { self.error = error.localizedDescription; store.report(error) }
    }
}

struct NoticeDetail: View {
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.dismiss) private var dismiss
    let item: JACNotice
    @State private var document: ExportedDocument?
    @State private var previousDocument: ExportedDocument?
    @State private var downloading = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section { Text(item.title).font(.title2.bold()); Text(item.createdLabel).foregroundStyle(.secondary) }
                if let error { Section { InlineError(message: error) } }
                if item.kind == "itinerary" { Section { Text(item.filename); Text("\(max(1,item.size/1024)) KB · PDF").font(.caption).foregroundStyle(.secondary)
                    Button { Task { downloading = true; defer { downloading = false }; do { let file = try await store.client.itinerary(item); previousDocument = file; document = file } catch { self.error = error.localizedDescription; store.report(error) } } } label: { HStack { Label("Abrir PDF", systemImage: "doc.text"); if downloading { ProgressView() } } }.buttonStyle(JACPrimaryButtonStyle()).disabled(downloading).accessibilityIdentifier("notices.pdf")
                } } else { Section { Text(item.body).textSelection(.enabled) } }
            }.jacSurface().navigationTitle(item.kind == "itinerary" ? "Itinerario" : "Alerta").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() }.accessibilityIdentifier("notices.detail.close") } }
                .task { do { try await store.client.noticeCommand(.object(["action": .string("read"), "id": .string(item.id)])) } catch { store.report(error) } }
                .sheet(item: $document, onDismiss: { if let previousDocument { TemporaryDocuments.remove(previousDocument); self.previousDocument = nil } }) { file in NavigationStack { DocumentPreview(url: file.url).ignoresSafeArea(edges: .bottom).navigationTitle("Itinerario PDF").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Listo") { document = nil }.accessibilityIdentifier("notices.pdf.close") }; ToolbarItem(placement: .confirmationAction) { ShareLink(item: file.url) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Compartir PDF") } } } }
        }
    }
}
struct NoticeComposer: View {
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.dismiss) private var dismiss
    let users: [NoticeUser]
    let onSaved: () async -> Void
    @State private var requestID = UUID().uuidString.lowercased()
    @State private var title = ""
    @State private var message = ""
    @State private var recipients: Set<String>
    @State private var busy = false
    @State private var error: String?
    init(users: [NoticeUser], onSaved: @escaping () async -> Void) { self.users = users; self.onSaved = onSaved; _recipients = State(initialValue: Set(users.map(\.id))) }
    var body: some View {
        NavigationStack {
            Form {
                if let error { Section { InlineError(message: error) } }
                Section("Alerta") { TextField("Título", text: $title).accessibilityIdentifier("notices.editor.title"); TextField("Mensaje", text: $message, axis: .vertical).lineLimit(4...10).accessibilityIdentifier("notices.editor.message") }
                Section("Destinatarios") { ForEach(users) { user in Toggle(user.name, isOn: Binding(get: { recipients.contains(user.id) }, set: { value in if value { recipients.insert(user.id) } else { recipients.remove(user.id) } })).accessibilityIdentifier("notices.recipient.\(user.id)") } }
                Section { Button(busy ? "Guardando…" : "Crear alerta y notificar") { Task { await save() } }.buttonStyle(JACPrimaryButtonStyle()).accessibilityIdentifier("notices.editor.save") }
            }.jacSurface().navigationTitle("Crear alerta").navigationBarTitleDisplayMode(.inline).disabled(busy).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(busy) } }
        }.interactiveDismissDisabled(busy)
    }
    private func save() async {
        guard !busy else { return }; guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 120, message.count <= 2000, !recipients.isEmpty else { error = "Revisa el título, mensaje y destinatarios."; return }
        busy = true; defer { busy = false }; error = nil
        do { try await store.client.noticeCommand(.object(["action": .string("alert"), "alert": .object(["id": .string(requestID), "title": .string(title), "body": .string(message), "recipients": .array(recipients.sorted().map(JSONValue.string))])])); dismiss(); await onSaved() }
        catch { self.error = error.localizedDescription; store.report(error) }
    }
}
