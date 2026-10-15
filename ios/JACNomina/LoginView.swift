import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var store: PayrollStore
    @State private var username = ""
    @State private var password = ""
    @State private var keepSignedIn = false
    @FocusState private var focus: Field?
    private enum Field { case username, password }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    BrandView().frame(maxWidth: 230).frame(maxWidth: .infinity).padding(.vertical, 16)
                    Text("La nómina de tu equipo, contigo.").font(.title2.weight(.semibold)).foregroundStyle(.white)
                }.listRowBackground(JACTheme.navy)
                Section {
                    TextField("Usuario o correo", text: $username)
                        .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focus, equals: .username).submitLabel(.next)
                        .onSubmit { focus = .password }
                        .accessibilityIdentifier("login.username")
                    SecureField("Contraseña", text: $password).textContentType(.password)
                        .focused($focus, equals: .password).submitLabel(.go)
                        .onSubmit { signIn() }.accessibilityIdentifier("login.password")
                    Toggle("Mantener la sesión iniciada", isOn: $keepSignedIn)
                        .accessibilityIdentifier("login.keepSignedIn")
                } header: {
                    Text("Tu cuenta de nómina")
                } footer: {
                    Text("Si la marcas, permanecerás conectado en este iPhone hasta que cierres sesión.")
                }
                if let error = store.error { Section { InlineError(message: error) } }
                Section {
                    Button(action: signIn) {
                        HStack { Spacer(); if store.busy { ProgressView() }; Text("Iniciar sesión").fontWeight(.semibold); Spacer() }
                    }.buttonStyle(JACPrimaryButtonStyle()).disabled(store.busy).accessibilityIdentifier("login.submit")
                } footer: {
                    Text("Usa el mismo usuario y contraseña que en la web. El acceso es exclusivo para las cuentas autorizadas por Camilo.")
                }
                Section { NavigationLink("Activar cuenta o restablecer contraseña") { ActivateAccountView() } }
            }
            .jacSurface().navigationTitle("Nómina JAC")
            .scrollDismissesKeyboard(.interactively)
            .disabled(store.busy)
        }
    }
    private func signIn() {
        guard !store.busy else { return }
        focus = nil
        Task { await store.signIn(username: username, password: password, keepSignedIn: keepSignedIn); password = "" }
    }
}

enum ActivationInput {
    static func token(_ input: String, baseURL: URL = PayrollClient.productionURL) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil { return value }
        guard let parts = URLComponents(string: value), parts.scheme == "https", parts.host == baseURL.host, parts.port == baseURL.port,
              parts.path == "/acceso", parts.user == nil, parts.password == nil, parts.query == nil,
              let fragment = parts.fragment, fragment.hasPrefix("activacion=") else { return nil }
        let token = String(fragment.dropFirst("activacion=".count))
        return token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil ? token : nil
    }
}
struct ActivateAccountView: View {
    @EnvironmentObject private var store: PayrollStore
    @State private var link = ""
    @State private var password = ""
    @State private var repeated = ""
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                TextField("Pega el enlace privado de activación", text: $link, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                SecureField("Nueva contraseña", text: $password).textContentType(.newPassword)
                SecureField("Repetir contraseña", text: $repeated).textContentType(.newPassword)
            } footer: { Text("Usa el enlace individual generado por Camilo. Vence en 24 horas y funciona una sola vez.") }
            if let error = error ?? store.error { Section { InlineError(message: error) } }
            Section {
                Button("Activar y entrar") {
                    guard let token = ActivationInput.token(link, baseURL: store.client.baseURL) else { error = "Pega un enlace de activación válido."; return }
                    guard !password.isEmpty, password == repeated else { error = "Ingresa una contraseña y repítela igual."; return }
                    error = nil
                    Task { if await store.activate(token: token, password: password) { link = ""; password = ""; repeated = "" } }
                }.disabled(store.busy)
            }
        }.jacSurface().navigationTitle("Activar cuenta").disabled(store.busy).scrollDismissesKeyboard(.interactively)
            .onDisappear { link = ""; password = ""; repeated = "" }
    }
}
