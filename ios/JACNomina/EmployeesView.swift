import SwiftUI

struct EmployeesView: View {
    @EnvironmentObject private var store: PayrollStore
    let overview: PayrollOverview
    var embedded = false
    @State private var search = ""
    @State private var includeInactive = false
    @State private var includeDeleted = false
    @State private var editor: PayrollEditorSession?
    private var employees: [Employee] {
        overview.employees.filter {
            (includeDeleted || $0.deleted != true) && (includeInactive || $0.active || (includeDeleted && $0.deleted == true)) &&
            (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.role.localizedCaseInsensitiveContains(search))
        }.sorted { $0.name < $1.name }
    }
    var body: some View {
        Group { if embedded { content } else { NavigationStack { content } } }
    }
    private var content: some View {
            List {
                if store.hasOperationStatus { OperationStatusSection() }
                Section { Toggle("Incluir personas inactivas", isOn: $includeInactive); Toggle("Incluir personas eliminadas", isOn: $includeDeleted) }
                if employees.isEmpty { ContentUnavailableView("Sin resultados", systemImage: "person.2", description: Text("Prueba con otro nombre o cargo.")) }
                ForEach(PayrollChoices.categories, id: \.0) { category in
                    let group = employees.filter { $0.category == category.0 }
                    if !group.isEmpty {
                        Section(category.1) {
                            ForEach(group) { employee in
                                NavigationLink { EmployeeDetailView(employeeID: employee.id, user: overview.user) } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(employee.name).font(.headline)
                                        Text(employee.role + (employee.deleted == true ? " · Eliminado" : employee.active ? "" : " · Inactivo")).font(.subheadline).foregroundStyle(.secondary)
                                    }.padding(.vertical, 3)
                                }
                            }
                        }
                    }
                }
            }.jacSurface().navigationTitle("Equipo JAC").jacInlineTitle().jacSearchable(text: $search, prompt: "Buscar persona o cargo")
                .refreshable { try? await store.refresh() }
                .toolbar {
                    if overview.user.can("staff") {
                        ToolbarItem(placement: .jacTrailing) {
                            Button {
                                if let w = store.workspace { editor = PayrollEditorSession(kind: .employee, workspace: w, detail: nil, record: PayrollEditorSession.newRecord(.employee, workspace: w)) }
                            } label: { Image(systemName: "person.badge.plus") }.accessibilityLabel("Agregar persona").accessibilityIdentifier("employee.create").disabled(!store.canWrite)
                        }
                    }
                }.sheet(item: $editor) { PayrollEditorView(session: $0) }
    }
}
struct EmployeeDetailView: View {
    @EnvironmentObject private var store: PayrollStore
    let employeeID: String
    let user: PayrollUser
    @State private var editor: PayrollEditorSession?
    @State private var confirmDelete = false
    private var record: JSONValue { store.workspace?.record("employees", id: employeeID) ?? .null }
    var body: some View {
        List {
            if store.hasOperationStatus { OperationStatusSection() }
            EmployeeConditionsSection(record: record)
            if user.can("staff") {
                Section("Acciones") {
                    if record["deleted"].flag {
                        Button("Restaurar persona") { Task { _ = await store.action("restoreEmployee", employeeID: employeeID) } }.disabled(!store.canWrite)
                        Text("La persona restaurada queda inactiva. Actívala al editar si corresponde.").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Button("Editar persona y condiciones") {
                            if let w = store.workspace { editor = PayrollEditorSession(kind: .employee, workspace: w, detail: nil, record: record) }
                        }.disabled(!store.canWrite)
                        Button("Eliminar persona", role: .destructive) { confirmDelete = true }.disabled(!store.canWrite)
                    }
                }
            }
        }.jacSurface().navigationTitle("Personal").jacInlineTitle()
            .sheet(item: $editor) { PayrollEditorView(session: $0) }
            .confirmationDialog("¿Eliminar esta persona del personal vigente?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Eliminar persona", role: .destructive) { Task { _ = await store.action("deleteEmployee", employeeID: employeeID) } }
            } message: { Text("Sus registros históricos se conservan. Si tiene registros en una quincena abierta, primero debes retirarlos o cerrar esa quincena.") }
    }
}
struct EmployeeConditionsSection: View {
    let record: JSONValue
    var body: some View {
        Section("Datos personales") {
            Text(record["name"].text).font(.title2.weight(.semibold))
            LabeledContent("Documento", value: record["document"].text); LabeledContent("Cargo", value: record["role"].text)
            LabeledContent("Categoría", value: PayrollFormat.category(record["category"].text))
            LabeledContent("Estado", value: record["deleted"].flag ? "Eliminado" : record["active"].flag ? "Activo" : "Inactivo")
            if !record["email"].text.isEmpty { LabeledContent("Correo", value: record["email"].text).textSelection(.enabled) }
        }
        Section("Servicios y shows") {
            AmountRow(title: "Honorario por show", value: record["showRate"].number); AmountRow(title: "Tarifa por kilómetro", value: record["kmRate"].number)
            AmountRow(title: "Honorario fijo quincenal", value: record["fixedService"].number)
            LabeledContent("Retención", value: PayrollFormat.number(record["withholding"].number * 100) + " %")
            LabeledContent("ReteICA", value: PayrollFormat.number(record["ica"].number * 100) + " %")
        }
        Section("Nómina de dependientes") {
            AmountRow(title: "Salario mensual", value: record["salary"].number); AmountRow(title: "Auxilio mensual", value: record["transport"].number)
            LabeledContent("Frecuencia", value: record["cycle"].text == "mensual" ? "Mensual" : "Quincenal")
            if record["cycle"].text == "mensual" { LabeledContent("Corte mensual", value: record["monthlyHalf"].number == 1 ? "Primera quincena" : "Segunda quincena") }
            AmountRow(title: "Movilización no salarial", value: record["nonSalary"].number)
            LabeledContent("Base de aportes", value: PayrollFormat.number(record["contributionBase"].number * 100) + " %")
            AmountRow(title: "Retención de nómina", value: record["incomeTax"].number); AmountRow(title: "Solidaridad", value: record["solidarity"].number)
            LabeledContent("EPS", value: record["health"].flag ? "Sí" : "No"); LabeledContent("AFP", value: record["pension"].flag ? "Sí" : "No")
        }
    }
}
