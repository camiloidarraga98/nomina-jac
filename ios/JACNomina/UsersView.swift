import SwiftUI

struct UserEditorSession: Identifiable { let id = UUID(); let user: ManagedUser }
struct UsersView: View {
    @EnvironmentObject private var store: PayrollStore
    @State private var users: [ManagedUser] = []
    @State private var editor: UserEditorSession?
    @State private var busy = false
    @State private var selectedInvite: ManagedUser?
    @State private var invitation: URL?
    @State private var notice: String?
    var body: some View {
        List {
            if store.hasOperationStatus { OperationStatusSection() }
            if store.overview?.user.canViewPresence == true {
                Section {
                    NavigationLink { ActiveConnectionsView() } label: { Label("Conexiones activas", systemImage: "dot.radiowaves.left.and.right") }
                }
            }
            if let notice { Section { Text(notice).foregroundStyle(.green) } }
            if let invitation {
                Section("Enlace de activación") {
                    ShareLink("Compartir enlace privado", item: invitation)
                    Text("Úsalo una sola vez, antes de 24 horas. Compártelo únicamente con la persona indicada.").font(.footnote).foregroundStyle(.secondary)
                    Button("Ocultar enlace") { self.invitation = nil }
                }
            }
            ForEach(users) { user in
                Section(user.name) {
                    LabeledContent("Usuario", value: user.username); LabeledContent("Correo", value: user.email)
                    LabeledContent("Estado", value: user.active ? (user.ready ? "Activo" : "Pendiente de activación") : "Inactivo")
                    if user.owner { Label("Administrador · permisos completos", systemImage: "person.badge.key") }
                    else {
                        Text(user.effectiveSections.compactMap { JACSection(rawValue:$0)?.title }.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
                        Button("Editar cuenta y permisos") { editor = UserEditorSession(user: user) }.disabled(busy || store.isOffline)
                        if user.active { Button(user.ready ? "Restablecer contraseña" : "Generar invitación") { selectedInvite = user }.disabled(busy || store.isOffline) }
                    }
                }
            }
            if busy { Section { ProgressView() } }
        }.jacSurface().navigationTitle("Usuarios y permisos").jacInlineTitle()
            .task { await load() }.refreshable { await load() }
            .toolbar {
                ToolbarItem(placement: .jacTrailing) {
                    Button {
                        editor = UserEditorSession(user: ManagedUser(id: "", username: "", email: "", name: "", owner: false, active: true, permissions: ["export"], version: 1, ready: false))
                    } label: { Image(systemName: "person.badge.plus") }.accessibilityLabel("Crear usuario").disabled(busy || store.isOffline)
                }
            }.sheet(item: $editor) { session in UserEditorView(user: session.user) { Task { invitation = nil; await load() } } }
            .confirmationDialog("¿Generar un enlace para \(selectedInvite?.name ?? "esta cuenta")?", isPresented: Binding(get: { selectedInvite != nil }, set: { if !$0 { selectedInvite = nil } }), titleVisibility: .visible) {
                if let user = selectedInvite { Button("Generar enlace privado") { selectedInvite = nil; Task { await invite(user) } } }
            } message: { Text("Los enlaces anteriores y la contraseña anterior quedarán invalidados. Sus sesiones se cerrarán. El nuevo enlace vence en 24 horas.") }
    }
    private func load() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        if users.isEmpty, let saved = store.client.cached(UserDirectory.self, path: "api/users") { users = saved.users }; do { users = try await store.client.users().users } catch { store.reportReadFailure(error) }
    }
    private func invite(_ user: ManagedUser) async {
        guard !busy else { return }; busy = true; invitation = nil; defer { busy = false }
        do {
            let response = try await store.client.invite(userID: user.id)
            guard let url = URL(string: response.activationPath, relativeTo: store.client.baseURL)?.absoluteURL,
                  url.scheme == "https", url.host == store.client.baseURL.host, url.port == store.client.baseURL.port, url.path == "/acceso",
                  url.user == nil, url.password == nil, url.query == nil,
                  ActivationInput.token(url.absoluteString, baseURL: store.client.baseURL) != nil else { throw APIError.message("El enlace recibido no es válido.") }
            invitation = url; notice = response.notice
        } catch { store.report(error) }
    }
}

private struct ActiveConnectionsView: View {
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.scenePhase) private var phase
    @State private var connections: [ActiveConnection]?
    @State private var error: String?
    @State private var loading = false

    private var canRead: Bool {
        phase == .active && !store.isOffline && store.overview?.user.canViewPresence == true
    }

    var body: some View {
        List {
            Section {
                if !canRead { Text("Conéctate para ver las conexiones activas.").foregroundStyle(.secondary) }
                else if let error { InlineError(message: error) }
                else if let connections {
                    if connections.isEmpty { Text("Las conexiones aparecerán aquí cuando alguien abra JAC.").foregroundStyle(.secondary) }
                    ForEach(connections) { connection in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(connection.name).font(.headline)
                            Text("\(connection.platform) · \(connection.section)")
                            Text("Desde \(PayrollFormat.timestamp(connection.connectedAt))").font(.footnote).foregroundStyle(.secondary)
                        }.padding(.vertical, 3)
                    }
                } else { ProgressView("Consultando conexiones…") }
            } footer: { Text("Pestañas y apps de JAC en primer plano. Horas de Colombia.") }
        }.jacSurface().navigationTitle("Conexiones activas").jacInlineTitle().privacySensitive()
            .refreshable { await load() }
            .task(id: canRead) {
                if !canRead { connections = nil; error = nil; return }
                while !Task.isCancelled {
                    await load()
                    do { try await Task.sleep(for: .seconds(10)) } catch { return }
                }
            }
    }

    private func load() async {
        guard canRead, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let current = try await store.client.activeConnections()
            guard !Task.isCancelled, canRead else { return }
            connections = current
            error = nil
        } catch {
            guard !Task.isCancelled, canRead else { return }
            connections = nil
            self.error = error.localizedDescription
        }
    }
}

/// Report the visible section of an authenticated workspace, independently of its refresh and offline cache.
struct JACPresenceReporter: ViewModifier {
    let user: PayrollUser
    let route: String
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.scenePhase) private var phase
    @State private var clientId = UUID()
    @State private var sequence = 0
    @State private var reported = false

    private struct Target: Equatable {
        let userId: String
        let section: String?
    }

    private var section: String {
        switch route {
        case "payroll": "quincena"
        case "agenda": "agenda"
        case "itineraries": user.hasSection(.itineraries) ? "itinerarios" : "pases"
        case "boarding": "pases"
        case "alerts": "alertas"
        case "media": "fotografia"
        case "music": "musica"
        case "crm": "crm"
        case "account": "cuenta"
        default: "gestion"
        }
    }

    func body(content: Content) -> some View {
        let target = Target(userId: user.id, section: phase == .active && !store.isOffline ? section : nil)
        content.task(id: target) {
            guard !Task.isCancelled, store.client.baseURL.host?.hasSuffix(".invalid") != true else { return }
            guard target.section != nil else {
                if reported { reported = false; await send(target) }
                return
            }
            reported = true
            while !Task.isCancelled {
                await send(target)
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }

    private func send(_ target: Target) async {
        guard store.overview?.user.id == target.userId else { return }
        sequence += 1
        try? await store.client.reportPresence(userId: target.userId, clientId: clientId, section: target.section, sequence: sequence)
    }
}
struct UserEditorView: View {
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.dismiss) private var dismiss
    @State var user: ManagedUser
    var onSaved: () -> Void
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                if let error { Section { InlineError(message: error) } }
                Section("Identidad") {
                    TextField("Nombre", text: $user.name)
                    TextField("Usuario", text: $user.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Correo", text: $user.email).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("Cuenta activa", isOn: $user.active)
                }
                Section("Secciones disponibles") {
                    ForEach(JACSection.allCases.filter { $0 != .crm },id:\.self) { section in
                        Toggle(section.title,isOn:Binding(get:{user.sections?.contains(section.rawValue) == true},set:{enabled in
                            var selected=user.sections ?? user.effectiveSections;selected.removeAll{$0 == section.rawValue}
                            if enabled {selected.append(section.rawValue)}
                            if section == .mediaUpload && enabled && !selected.contains("media") {selected.append("media")}
                            if section == .musicUpload && enabled && !selected.contains("music") {selected.append("music")}
                            if section == .music && !enabled {selected.removeAll{$0 == "musicUpload"}}
                            if section == .media && !enabled {selected.removeAll{$0 == "mediaUpload"}}
                            if section == .payroll && !enabled {user.permissions.removeAll{$0 != "administrator"}}
                            user.sections=selected
                        })).disabled(user.administrator == true).accessibilityIdentifier("users.section."+section.rawValue)
                    }
                    LabeledContent("CRM",value:user.administrator == true ? "Administrador" : "Solo administradores")
                }
                Section {
                    ForEach(["payroll", "staff", "rules", "close", "send", "export", "modifyClosed"], id: \.self) { permission in
                        Toggle(PayrollFormat.permissionNames[permission] ?? permission, isOn: Binding(get: { user.permissions.contains(permission) }, set: { enabled in
                            user.permissions.removeAll { $0 == permission }; if enabled { user.permissions.append(permission) }
                        })).disabled(user.sections?.contains("payroll") != true).accessibilityIdentifier("users.permission."+permission)
                    }
                } header: { Text("Permisos") } footer: {
                    Text("Modificar cierres es un permiso independiente. Guardar cambios invalida las sesiones e invitaciones anteriores.")
                }
            }.jacSurface().navigationTitle(user.id.isEmpty ? "Nuevo usuario" : "Editar usuario").jacInlineTitle()
                .onAppear { if user.sections == nil || user.administrator == true {user.sections=user.effectiveSections} }
                .disabled(busy || user.owner)
                .toolbar {
                    ToolbarItem(placement: .jacLeading) { Button("Cancelar") { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .jacTrailing) {
                        Button("Guardar") {
                            busy = true; error = nil
                            Task {
                                defer { busy = false }
                                do { _ = try await store.client.updateUser(user); onSaved(); dismiss() }
                                catch { self.error = error.localizedDescription; store.report(error) }
                            }
                        }.disabled(busy || store.isOffline || user.owner || user.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || user.username.isEmpty || user.email.isEmpty)
                    }
                }.interactiveDismissDisabled(busy).scrollDismissesKeyboard(.interactively)
        }
    }
}
