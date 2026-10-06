import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var store: PayrollStore
    let user: PayrollUser
    @State private var confirmLogout = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    BrandView().frame(maxWidth: 220).frame(maxWidth: .infinity).padding(.vertical, 10)
                    Text(user.displayName).font(.title2.weight(.semibold))
                    LabeledContent("Usuario", value: user.username)
                    LabeledContent("Correo", value: user.email).textSelection(.enabled)
                    LabeledContent("Perfil", value: user.isOwner ? "Administrador" : "Equipo administrativo")
                }
                Section("Acceso") {
                    NavigationLink("Cambiar contraseña") { ChangePasswordView() }
                    Button("Cerrar sesión", role: .destructive) { confirmLogout = true }.disabled(store.busy)
                }
                Section("Permisos de tu cuenta") {
                    ForEach(PayrollFormat.permissionNames.keys.sorted(), id: \.self) { permission in
                        LabeledContent(PayrollFormat.permissionNames[permission] ?? permission) {
                            Image(systemName: user.can(permission) ? "checkmark.circle.fill" : "minus.circle")
                                .foregroundStyle(user.can(permission) ? Color.green : Color.secondary)
                                .accessibilityLabel(user.can(permission) ? "Autorizado" : "Sin permiso")
                        }
                    }
                }
                Section {
                    Text("La app utiliza las mismas quincenas, cuentas y permisos que la web. Los cálculos y las condiciones históricas se conservan en el servidor.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Mi cuenta")
            .confirmationDialog("¿Cerrar sesión en este iPhone? Los cambios pendientes sin guardar se descartarán.", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("Cerrar sesión", role: .destructive) { Task { await store.signOut() } }
            }
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
        }.navigationTitle("Contraseña").disabled(busy)
    }
}
