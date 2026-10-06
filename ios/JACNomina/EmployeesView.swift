import SwiftUI

struct EmployeesView: View {
    @EnvironmentObject private var store: PayrollStore
    let overview: PayrollOverview
    @State private var search = ""
    @State private var includeInactive = false
    private var employees: [Employee] {
        overview.employees.filter { $0.deleted != true && (includeInactive || $0.active) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.role.localizedCaseInsensitiveContains(search)) }.sorted { $0.name < $1.name }
    }
    var body: some View {
        NavigationStack {
            List {
                if let error = store.error { Section { InlineError(message: error) } }
                Section { Toggle("Incluir personas inactivas", isOn: $includeInactive) }
                if employees.isEmpty { ContentUnavailableView("Sin resultados", systemImage: "person.2", description: Text("Prueba con otro nombre o cargo.")) }
                ForEach(["musicos", "tecnica", "conductores", "administracion", "comision"], id: \.self) { category in
                    let group = employees.filter { $0.category == category }
                    if !group.isEmpty {
                        Section(PayrollFormat.category(category)) {
                            ForEach(group) { employee in
                                NavigationLink { EmployeeDetailView(employee: employee) } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(employee.name).font(.headline)
                                        Text(employee.role + (employee.active ? "" : " · Inactivo")).font(.subheadline).foregroundStyle(.secondary)
                                    }.padding(.vertical, 3)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Equipo JAC")
            .searchable(text: $search, prompt: "Buscar persona o cargo")
            .refreshable { try? await store.refresh() }
        }
    }
}

struct EmployeeDetailView: View {
    let employee: Employee
    var body: some View {
        List {
            Section("Datos personales") {
                Text(employee.name).font(.title2.weight(.semibold))
                LabeledContent("Documento", value: employee.document)
                LabeledContent("Cargo", value: employee.role)
                LabeledContent("Categoría", value: employee.categoryName)
                LabeledContent("Estado", value: employee.active ? "Activo" : "Inactivo")
                if let email = employee.email, !email.isEmpty { LabeledContent("Correo", value: email).textSelection(.enabled) }
            }
            Section("Condiciones de pago") {
                AmountRow(title: "Honorario por show", value: employee.showRate)
                if employee.kmRate > 0 { AmountRow(title: "Tarifa por kilómetro", value: employee.kmRate) }
                if employee.fixedService > 0 { AmountRow(title: "Honorario fijo quincenal", value: employee.fixedService) }
                if employee.salary > 0 {
                    AmountRow(title: "Salario mensual", value: employee.salary)
                    AmountRow(title: "Auxilio de transporte", value: employee.transport)
                    LabeledContent("Ciclo de pago", value: employee.cycle == "mensual" ? "Mensual" : "Quincenal")
                    LabeledContent("EPS", value: employee.health ? "Sí" : "No")
                    LabeledContent("AFP", value: employee.pension ? "Sí" : "No")
                }
            }
        }.navigationTitle("Personal").navigationBarTitleDisplayMode(.inline)
    }
}
