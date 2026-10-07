import SwiftUI

struct MailView: View {
    @EnvironmentObject private var store: PayrollStore
    let user: PayrollUser
    var initialPeriodID: String? = nil
    @State private var selectedPeriod = ""
    @State private var mail: PayrollMail?
    @State private var busy = false
    @State private var notice: String?
    @State private var error: String?
    @State private var configure = false
    @State private var disconnect = false
    @State private var sending: MailSendSelection?
    @State private var editor: PayrollEditorSession?
    @State private var search = ""
    @State private var status = ""
    @State private var authorizer = GmailAuthorizer()
    private var selected: PeriodSummary? { store.overview?.periods.first { $0.id == selectedPeriod } }
    private var canSend: Bool { user.can("send") && selected?.isClosed == true && (selected?.ownerOnly != true || user.can("modifyClosed")) && mail?.connection.connected == true }
    var body: some View {
        List {
            OperationStatusSection()
            if let error { Section { InlineError(message: error) } }
            if let notice { Section { Text(notice).foregroundStyle(.green) } }
            if let mail {
                Section("Conexión de Gmail") {
                    LabeledContent("Remitente", value: mail.connection.sender)
                    LabeledContent("Estado", value: mail.connection.connected ? "Conectado" : mail.connection.configured ? "Pendiente de autorización" : "Sin configurar")
                    if !mail.connection.error.isEmpty { InlineError(message: mail.connection.error) }
                    if user.isOwner {
                        Button("Configurar credenciales de Google") { configure = true }.disabled(busy)
                        if mail.connection.configured { Button(mail.connection.connected ? "Volver a autorizar Gmail" : "Conectar Gmail") { Task { await connect() } }.disabled(busy) }
                        if mail.connection.connected { Button("Desconectar Gmail", role: .destructive) { disconnect = true }.disabled(busy) }
                        LabeledContent("URI de redirección", value: mail.connection.callback).textSelection(.enabled).font(.footnote)
                    }
                }
                Section("Quincena") {
                    Picker("Consultar envíos", selection: $selectedPeriod) {
                        Text("Seleccionar quincena").tag("")
                        ForEach((store.overview?.periods ?? []).sorted { $0.start > $1.start }) { Text($0.title).tag($0.id) }
                    }.onChange(of: selectedPeriod) { _, _ in Task { await load() } }
                    if selected?.isClosed == false { Text("Cierra la quincena para enviar los desprendibles.").font(.footnote).foregroundStyle(.secondary) }
                    if selected?.ownerOnly == true && !user.can("modifyClosed") { Text("Este cierre corregido requiere permiso para modificar cierres.").font(.footnote).foregroundStyle(.secondary) }
                    if canSend { Button("Enviar pendientes y errores de esta quincena") { sending = MailSendSelection(employeeID: nil, name: "toda la quincena") }.disabled(busy) }
                }
                if !selectedPeriod.isEmpty {
                    Section("Estado de envíos") {
                        TextField("Buscar persona o correo", text: $search)
                        Picker("Estado", selection: $status) {
                            Text("Todos").tag("")
                            ForEach(MailLabels.statuses, id: \.self) { Text(MailLabels.status($0)).tag($0) }
                        }
                        let jobs = mail.jobs.filter { (status.isEmpty || $0.status == status) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.email.localizedCaseInsensitiveContains(search)) }
                        if jobs.isEmpty { Text("Sin envíos para esta selección.").foregroundStyle(.secondary) }
                        ForEach(jobs) { job in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(job.name).font(.headline)
                                Text(job.email.isEmpty ? "Falta registrar correo" : job.email).font(.subheadline)
                                Label(MailLabels.status(job.status), systemImage: job.status == "sent" ? "checkmark.circle" : "envelope").font(.caption)
                                if !job.error.isEmpty { Text(job.error).font(.footnote).foregroundStyle(.secondary) }
                                if let sent = job.sentAt { Text(PayrollFormat.timestamp(sent)).font(.caption).foregroundStyle(.secondary) }
                                Text("Intentos: \(job.attempts)").font(.caption).foregroundStyle(.secondary)
                                if user.can("staff"), let w = store.workspace, let record = w.record("employees", id: job.employeeId), !record["deleted"].flag {
                                    Button("Editar correo de esta persona") { editor = PayrollEditorSession(kind: .employee, workspace: w, detail: nil, record: record) }.disabled(busy || !store.canWrite)
                                }
                                if canSend && ["pending", "missing", "error"].contains(job.status) {
                                    Button("Enviar a esta persona") { sending = MailSendSelection(employeeID: job.employeeId, name: job.name) }.disabled(busy)
                                }
                            }.padding(.vertical, 4)
                        }
                    }
                    Section { Text("«Enviado» significa que Gmail aceptó el mensaje. Los resultados inciertos y los mensajes enviados o cancelados no se reenvían automáticamente.").font(.footnote).foregroundStyle(.secondary) }
                }
            }
            if busy { Section { ProgressView("Consultando correo…") } }
            Button("Actualizar estados") { Task { await load() } }.disabled(busy)
        }.jacSurface().navigationTitle("Correos y Gmail").navigationBarTitleDisplayMode(.inline)
            .task { selectedPeriod = initialPeriodID ?? store.overview?.periods.sorted { $0.start > $1.start }.first?.id ?? ""; await load() }
            .refreshable { await load() }
            .onChange(of: store.workspace?.version) { _, _ in Task { await load() } }
            .sheet(isPresented: $configure) { GmailConfigurationView(callback: mail?.connection.callback ?? "") { Task { await load() } } }
            .sheet(item: $editor) { PayrollEditorView(session: $0) }
            .confirmationDialog("¿Desconectar Gmail?", isPresented: $disconnect, titleVisibility: .visible) {
                Button("Desconectar Gmail", role: .destructive) { Task { await operate(.object(["action": .string("disconnect")])) } }
            } message: { Text("Se conservarán los registros de envío. Dejarán de enviarse correos hasta conectar la cuenta de nuevo.") }
            .confirmationDialog("¿Enviar los desprendibles de \(sending?.name ?? "esta selección")?", isPresented: Binding(get: { sending != nil }, set: { if !$0 { sending = nil } }), titleVisibility: .visible) {
                if let selection = sending {
                    Button("Enviar desprendibles") {
                        var body: JSONValue = .object(["action": .string("send"), "periodId": .string(selectedPeriod)])
                        if let id = selection.employeeID { body["employeeId"] = .string(id) }
                        sending = nil; Task { await operate(body) }
                    }
                }
            } message: { Text("Se usarán los correos registrados y los documentos de este cierre. El servidor conserva los envíos anteriores para evitar duplicados.") }
    }
    private func load() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { mail = try await store.client.mail(periodID: selectedPeriod.isEmpty ? nil : selectedPeriod); error = nil }
        catch { self.error = store.reportReadFailure(error) }
    }
    private func operate(_ body: JSONValue) async {
        guard !busy else { return }; busy = true; error = nil
        do { notice = try await store.client.mailOperation(body).notice; mail = try await store.client.mail(periodID: selectedPeriod.isEmpty ? nil : selectedPeriod) }
        catch { self.error = error.localizedDescription; store.report(error) }; busy = false
    }
    private func connect() async {
        guard !busy else { return }; busy = true; error = nil
        do {
            let start = try await store.client.startGmail()
            try await authorizer.authorize(start)
            mail = try await store.client.mail(periodID: selectedPeriod.isEmpty ? nil : selectedPeriod); notice = "Gmail conectado."
        } catch { self.error = error.localizedDescription; store.report(error) }; busy = false
    }
}
struct MailSendSelection { let employeeID: String?; let name: String }
enum MailLabels {
    static let statuses = ["pending", "missing", "sending", "sent", "error", "uncertain", "cancelled"]
    static func status(_ value: String) -> String {
        ["pending": "Pendiente", "missing": "Sin correo", "sending": "Enviando", "sent": "Enviado", "error": "Error", "uncertain": "Resultado incierto", "cancelled": "Cancelado"][value] ?? value
    }
}
struct GmailConfigurationView: View {
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.dismiss) private var dismiss
    let callback: String
    var onSaved: () -> Void
    @State private var clientID = ""
    @State private var secret = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("ID de cliente OAuth", text: $clientID).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Secreto del cliente OAuth", text: $secret).textInputAutocapitalization(.never).autocorrectionDisabled()
                    LabeledContent("URI de redirección", value: callback).textSelection(.enabled).font(.footnote)
                } footer: { Text("Utiliza las credenciales del proyecto de Google. Los valores se guardan cifrados en el servidor; este formulario no los conserva al cerrarse.") }
                if let error { Section { InlineError(message: error) } }
            }.jacSurface().navigationTitle("Configurar Gmail").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { secret = ""; clientID = ""; dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Guardar") {
                            busy = true; error = nil
                            Task {
                                defer { busy = false }
                                do { _ = try await store.client.mailOperation(.object(["action": .string("configure"), "clientId": .string(clientID), "clientSecret": .string(secret)])); secret = ""; clientID = ""; onSaved(); dismiss() }
                                catch { self.error = error.localizedDescription; store.report(error) }
                            }
                        }.disabled(busy || clientID.isEmpty || secret.isEmpty)
                    }
                }.interactiveDismissDisabled(busy).onDisappear { secret = ""; clientID = "" }.scrollDismissesKeyboard(.interactively)
        }
    }
}
