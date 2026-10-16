import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var store: PayrollStore
    let user: PayrollUser
    @State private var confirmLogout = false
    var body: some View {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text(user.displayName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()).font(.system(.title2,design:.rounded,weight:.bold))
                                .frame(width:58,height:58).background(.white.opacity(0.12),in:RoundedRectangle(cornerRadius:20))
                            Spacer(); BrandView().frame(width:105)
                        }
                        Text(user.displayName).font(.system(.title2,design:.rounded,weight:.bold))
                        Text(user.isOwner ? "Administrador de JAC" : "Equipo JAC").font(.subheadline).foregroundStyle(JACTheme.highlight)
                    }.foregroundStyle(.white).padding(22).frame(maxWidth:.infinity,alignment:.leading)
                        .background(LinearGradient(colors:[JACTheme.navy,JACTone.violet.deep],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:24))
                }.jacStandaloneRow()
                Section("Tu cuenta") {
                    LabeledContent("Usuario", value: user.username)
                    LabeledContent("Correo", value: user.email).textSelection(.enabled)
                    if !store.isAgendaOnly { NavigationLink { ChangePasswordView() } label:{ Label("Cambiar contraseña",systemImage:"key") }.disabled(store.isOffline).accessibilityLabel("Cambiar contraseña") }
                }
                if !store.isAgendaOnly { Section("Permisos de tu cuenta") {
                    ForEach(PayrollFormat.permissionNames.keys.sorted(), id: \.self) { permission in
                        LabeledContent(PayrollFormat.permissionNames[permission] ?? permission) {
                            Image(systemName: user.can(permission) ? "checkmark.circle.fill" : "minus.circle")
                                .foregroundStyle(user.can(permission) ? Color.green : Color.secondary)
                                .accessibilityLabel(user.can(permission) ? "Autorizado" : "Sin permiso")
                        }
                    }
                } }
                Section("Copia sin conexión") {
                    if store.isOffline { Label("Consultando la última copia guardada", systemImage: "wifi.slash").font(.footnote) }
                    if store.client.syncingOffline { ProgressView("Guardando información y adjuntos…") }
                    if let message = store.client.offlineSyncMessage { Text(message).font(.footnote).accessibilityIdentifier("offline.sync.status") }
                    Button { Task { try? await store.refresh() } } label: { Label("Actualizar copia",systemImage:"arrow.down.circle").frame(maxWidth:.infinity) }.buttonStyle(JACSecondaryButtonStyle(tone:.teal)).disabled(store.client.syncingOffline).accessibilityIdentifier("offline.sync")
                    Text("La copia se cifra y se elimina al cerrar sesión. Para modificar datos se necesita conexión.").font(.footnote).foregroundStyle(.secondary)
                }
                Section { Button("Cerrar sesión", role: .destructive) { confirmLogout = true }.disabled(store.busy) }
                Section {
                    Text("La app utiliza las mismas quincenas, cuentas y permisos que la web. Los cálculos y las condiciones históricas se conservan en el servidor.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .jacSurface().navigationTitle("Mi cuenta").jacInlineTitle()
            .confirmationDialog("¿Cerrar sesión en este \(JACDevice.name)? Los cambios pendientes sin guardar se descartarán.", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("Cerrar sesión", role: .destructive) { Task { await store.signOut() } }
            }
    }
}

struct ChangePasswordView: View {
    @EnvironmentObject private var store: PayrollStore
    @State private var current = ""
    @State private var new = ""
    @State private var repeatPassword = ""
    @State private var busy = false
    @State private var error: String?
    @State private var saved = false
    var body: some View {
        Form {
            Section {
                SecureField("Contraseña actual", text: $current).textContentType(.password)
                SecureField("Nueva contraseña", text: $new).textContentType(.newPassword)
                SecureField("Repetir nueva contraseña", text: $repeatPassword).textContentType(.newPassword)
            }
            if let error { Section { InlineError(message: error) } }
            if saved { Section { Label("Contraseña actualizada", systemImage: "checkmark.circle.fill").foregroundStyle(.green) } }
            Section {
                Button {
                    guard !current.isEmpty, !new.isEmpty else { error = "Ingresa la contraseña actual y la nueva."; return }
                    guard new == repeatPassword else { error = "Las contraseñas nuevas no coinciden."; return }
                    busy = true; error = nil; saved = false
                    Task {
                        defer { busy = false }
                        do { try await store.client.changePassword(current: current, new: new); current = ""; new = ""; repeatPassword = ""; saved = true }
                        catch { self.error = error.localizedDescription; store.report(error) }
                    }
                } label: { HStack { Text("Guardar contraseña"); Spacer(); if busy { ProgressView() } } }
            }
        }.jacSurface().navigationTitle("Contraseña").disabled(busy || store.isOffline)
    }
}
