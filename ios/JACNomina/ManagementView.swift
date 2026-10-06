import SwiftUI

struct ManagementView: View {
    let user: PayrollUser
    var body: some View {
        NavigationStack {
            List {
                OperationStatusSection()
                Section("Administración") {
                    NavigationLink { AccountView(user: user) } label: { Label("Mi cuenta", systemImage: "person.crop.circle") }
                    NavigationLink { ConceptsRulesView(user: user) } label: { Label("Conceptos y reglas", systemImage: "list.bullet.rectangle") }
                    NavigationLink { MailView(user: user) } label: { Label("Correos y Gmail", systemImage: "envelope") }
                    if user.isOwner { NavigationLink { UsersView() } label: { Label("Usuarios y permisos", systemImage: "person.badge.key") } }
                }
            }.navigationTitle("Gestión")
        }
    }
}
struct ConceptsRulesView: View {
    @EnvironmentObject private var store: PayrollStore
    let user: PayrollUser
    @State private var editor: PayrollEditorSession?
    var body: some View {
        List {
            OperationStatusSection()
            if let w = store.workspace {
                let settings = w.data["settings"]
                Section("Parámetros de nómina") {
                    LabeledContent("Empresa", value: settings["company"].text); LabeledContent("NIT", value: settings["nit"].text)
                    LabeledContent("Divisor mensual de horas", value: PayrollFormat.number(settings["hourDivisor"].number))
                    ForEach(Array(settings["hourFactors"].elements.enumerated()), id: \.offset) { index, factor in
                        LabeledContent(index < PayrollFormat.hourNames.count ? PayrollFormat.hourNames[index] : "Factor", value: PayrollFormat.number(factor.number))
                    }
                    if user.can("rules") { Button("Editar parámetros") { editor = PayrollEditorSession(kind: .settings, workspace: w, detail: nil, record: settings) }.disabled(!store.canWrite) }
                }
                Section("Conceptos reutilizables") {
                    ForEach(Array(w.data["concepts"].elements.enumerated()), id: \.offset) { _, concept in
                        VStack(alignment: .leading, spacing: 8) {
                            AmountRow(title: concept["name"].text, value: concept["amount"].number)
                            Text(PayrollChoices.kinds.first { $0.0 == concept["kind"].text }?.1 ?? concept["kind"].text).font(.caption).foregroundStyle(.secondary)
                            if user.can("rules") { Button("Editar") { editor = PayrollEditorSession(kind: .concept, workspace: w, detail: nil, record: concept) }.disabled(!store.canWrite) }
                        }
                    }
                    if user.can("rules") { Button("Agregar concepto") { editor = PayrollEditorSession(kind: .concept, workspace: w, detail: nil, record: PayrollEditorSession.newRecord(.concept, workspace: w)) }.disabled(!store.canWrite).accessibilityIdentifier("concept.create") }
                }
            }
        }.navigationTitle("Conceptos y reglas").navigationBarTitleDisplayMode(.inline)
            .refreshable { try? await store.refresh() }.sheet(item: $editor) { PayrollEditorView(session: $0) }
    }
}
