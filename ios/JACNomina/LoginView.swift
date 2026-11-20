import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var store: PayrollStore
    #if os(iOS)
    @State private var hasTeamKiosk = false
    #endif
    @State private var username = ""
    @State private var password = ""
    @State private var keepSignedIn = false
    #if os(iOS) && DEBUG
    @EnvironmentObject private var accounts: JACAccountSessions
    @State private var privateAddress = JACAccountSessions.lastAddress
    private var kioskLogin: Bool { JACAccountSessions.isKioskLogin(username) }
    private var pilotProgress: String? { accounts.pilotProgress }
    #else
    private var kioskLogin: Bool { false }
    private var pilotProgress: String? { nil }
    #endif
    @FocusState private var focus: Field?
    private enum Field { case username, password }
    private var busy: Bool { store.busy || pilotProgress != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack { BrandView().frame(width: 156); Spacer(); Image(systemName: "waveform").font(.system(size: 34, weight: .light)).foregroundStyle(JACTheme.highlight).accessibilityHidden(true) }
                        Text("El equipo se mueve contigo.").font(.system(.title, design: .rounded, weight: .bold)).foregroundStyle(.white)
                        Text("Tu agenda, tus viajes y cada show. JAC, donde estés.").font(.subheadline).foregroundStyle(Color(red: 0.80, green: 0.89, blue: 0.96))
                    }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                        .background(LinearGradient(colors:[JACTheme.navy, JACTone.blue.deep],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:28))
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Bienvenido.").font(.system(.title2, design: .rounded, weight: .bold))
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Usuario o correo").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            TextField("Usuario o correo", text: $username)
                                .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .focused($focus, equals: .username).submitLabel(.next).onSubmit { focus = .password }
                                .accessibilityIdentifier("login.username")
                                .disabled(busy)
                                .padding(15).background(JACTheme.canvas,in:RoundedRectangle(cornerRadius:14))
                        }
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Contraseña").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            SecureField("Contraseña", text: $password).textContentType(.password)
                                .focused($focus, equals: .password).submitLabel(.go).onSubmit { signIn() }
                                .accessibilityIdentifier("login.password")
                                .disabled(busy)
                                .padding(15).background(JACTheme.canvas,in:RoundedRectangle(cornerRadius:14))
                        }
                        Toggle("Mantener la sesión iniciada", isOn: $keepSignedIn).font(.subheadline).accessibilityIdentifier("login.keepSignedIn").disabled(busy)
                        Text("Si la activas, permanecerás conectado en este \(JACDevice.name) hasta que cierres sesión.").font(.caption).foregroundStyle(.secondary)
                        if let error = store.error { InlineError(message: error) }
                        #if os(iOS) && DEBUG
                        if kioskLogin && JACAccountSessions.needsAddressField {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("Servidor privado de Asistencia").font(.caption.weight(.semibold))
                                TextField("https://asistencia.local", text: $privateAddress)
                                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .textFieldStyle(.roundedBorder).accessibilityIdentifier("login.attendanceServer")
                                    .disabled(busy)
                            }
                        }
                        #endif
                        if let pilotProgress {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(pilotProgress).font(.subheadline)
                            }.frame(maxWidth: .infinity).accessibilityElement(children: .combine)
                                .accessibilityIdentifier("login.attendanceProgress")
                        } else {
                            Button(action: signIn) {
                                HStack {
                                    Spacer()
                                    if store.busy { ProgressView().tint(.white) }
                                    Text("Iniciar sesión")
                                    Image(systemName: "arrow.right"); Spacer()
                                }
                            }.buttonStyle(JACPrimaryButtonStyle()).disabled(busy).accessibilityIdentifier("login.submit")
                        }
                        #if os(iOS) && DEBUG
                        if accounts.canCancelPreparation {
                            Button("Cancelar espera") { accounts.cancelPreparation() }
                                .frame(maxWidth: .infinity).accessibilityIdentifier("login.cancelAttendance")
                        }
                        #endif
                    }.padding(22).background(JACTheme.card,in:RoundedRectangle(cornerRadius:24))
                    if !kioskLogin && !store.client.isAttendancePilot {
                        #if os(iOS)
                        if hasTeamKiosk {
                            NavigationLink {
                                TeamAttendanceView(administrator:nil).navigationTitle("Kiosco de asistencia").jacInlineTitle()
                            } label: {
                                Label("Marcar asistencia",systemImage:"person.crop.square").frame(maxWidth:.infinity)
                            }.buttonStyle(JACPrimaryButtonStyle()).accessibilityIdentifier("attendance.openKiosk")
                        }
                        #endif
                        NavigationLink("Activar cuenta o restablecer contraseña") { ActivateAccountView() }
                            #if os(iOS)
                            .onAppear { hasTeamKiosk=TeamAttendanceDevice.shared.isPaired }
                            #endif
                            .disabled(busy)
                            .font(.subheadline.weight(.medium)).frame(maxWidth:.infinity).padding(.vertical,4)
                        Text("Usa la misma cuenta que en la web. Acceso exclusivo del equipo autorizado.").font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity).multilineTextAlignment(.center)
                    }
                }.padding(20).frame(maxWidth: JACDevice.isPad ? 540 : .infinity).frame(maxWidth: .infinity)
            }
            .jacSurface().navigationTitle("JAC Music").jacInlineTitle()
            .scrollDismissesKeyboard(.interactively).disabled(store.busy)
        }
    }
    private func signIn() {
        guard !busy else { return }
        focus = nil
        Task {
            #if os(iOS) && DEBUG
            if kioskLogin {
                await accounts.signInPilot(password: password, keepSignedIn: keepSignedIn, address: privateAddress) { password = "" }
                return
            }
            #endif
            await store.signIn(username: username, password: password, keepSignedIn: keepSignedIn)
            password = ""
        }
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
