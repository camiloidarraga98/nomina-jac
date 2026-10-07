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
            OperationStatusSection()
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
                        Text(user.permissions.compactMap { PayrollFormat.permissionNames[$0] }.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
                        Button("Editar cuenta y permisos") { editor = UserEditorSession(user: user) }.disabled(busy)
                        if user.active { Button(user.ready ? "Restablecer contraseña" : "Generar invitación") { selectedInvite = user }.disabled(busy) }
                    }
                }
            }
            if busy { Section { ProgressView() } }
        }.jacSurface().navigationTitle("Usuarios y permisos").navigationBarTitleDisplayMode(.inline)
            .task { await load() }.refreshable { await load() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editor = UserEditorSession(user: ManagedUser(id: "", username: "", email: "", name: "", owner: false, active: true, permissions: ["export"], version: 1, ready: false))
                    } label: { Image(systemName: "person.badge.plus") }.accessibilityLabel("Crear usuario").disabled(busy)
                }
            }.sheet(item: $editor) { session in UserEditorView(user: session.user) { Task { invitation = nil; await load() } } }
            .confirmationDialog("¿Generar un enlace para \(selectedInvite?.name ?? "esta cuenta")?", isPresented: Binding(get: { selectedInvite != nil }, set: { if !$0 { selectedInvite = nil } }), titleVisibility: .visible) {
                if let user = selectedInvite { Button("Generar enlace privado") { selectedInvite = nil; Task { await invite(user) } } }
            } message: { Text("Los enlaces anteriores y la contraseña anterior quedarán invalidados. Sus sesiones se cerrarán. El nuevo enlace vence en 24 horas.") }
    }
    private func load() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { users = try await store.client.users().users } catch { store.reportReadFailure(error) }
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
                Section {
                    ForEach(["payroll", "staff", "rules", "close", "send", "export", "modifyClosed"], id: \.self) { permission in
                        Toggle(PayrollFormat.permissionNames[permission] ?? permission, isOn: Binding(get: { user.permissions.contains(permission) }, set: { enabled in
                            user.permissions.removeAll { $0 == permission }; if enabled { user.permissions.append(permission) }
                        }))
                    }
                } header: { Text("Permisos") } footer: {
                    Text("Modificar cierres es un permiso independiente. Guardar cambios invalida las sesiones e invitaciones anteriores.")
                }
            }.jacSurface().navigationTitle(user.id.isEmpty ? "Nuevo usuario" : "Editar usuario").navigationBarTitleDisplayMode(.inline)
                .disabled(busy || user.owner)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Guardar") {
                            busy = true; error = nil
                            Task {
                                defer { busy = false }
                                do { _ = try await store.client.updateUser(user); onSaved(); dismiss() }
                                catch { self.error = error.localizedDescription; store.report(error) }
                            }
                        }.disabled(busy || user.owner || user.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || user.username.isEmpty || user.email.isEmpty)
                    }
                }.interactiveDismissDisabled(busy).scrollDismissesKeyboard(.interactively)
        }
    }
}
