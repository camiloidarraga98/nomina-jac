import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var store: PayrollStore
    @State private var username = ""
    @State private var password = ""
    @FocusState private var focus: Field?
    private enum Field { case username, password }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    BrandView().frame(maxWidth: 230).frame(maxWidth: .infinity).padding(.vertical, 16)
                    Text("La nómina de tu equipo, contigo.").font(.title2.weight(.semibold))
                }.listRowBackground(Color.clear)
                Section("Tu cuenta de nómina") {
                    TextField("Usuario o correo", text: $username)
                        .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focus, equals: .username).submitLabel(.next)
                        .onSubmit { focus = .password }
                        .accessibilityIdentifier("login.username")
                    SecureField("Contraseña", text: $password).textContentType(.password)
                        .focused($focus, equals: .password).submitLabel(.go)
                        .onSubmit { signIn() }.accessibilityIdentifier("login.password")
                }
                if let error = store.error { Section { InlineError(message: error) } }
                Section {
                    Button(action: signIn) {
                        HStack { Spacer(); if store.busy { ProgressView() }; Text("Iniciar sesión").fontWeight(.semibold); Spacer() }
                    }.disabled(store.busy).accessibilityIdentifier("login.submit")
                } footer: {
                    Text("Usa el mismo usuario y contraseña que en la web. El acceso es exclusivo para las cuentas autorizadas por Camilo.")
                }
            }
            .navigationTitle("Nómina JAC")
            .scrollDismissesKeyboard(.interactively)
            .disabled(store.busy)
        }
    }
    private func signIn() {
        guard !store.busy else { return }
        focus = nil
        Task { await store.signIn(username: username, password: password); password = "" }
    }
}
