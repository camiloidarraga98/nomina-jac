import SwiftUI

struct ShowFields: View {
    @Binding var record: JSONValue
    let session: PayrollEditorSession
    private var people: [Employee] {
        let selected = record["participants"].elements.map { $0["employeeId"].text }
        let excluded = session.detail?.record["excludedEmployees"].elements.map(\.text) ?? []
        return session.employees.filter { selected.contains($0.id) || ($0.active && $0.deleted != true && ["musicos", "tecnica"].contains($0.category) && !excluded.contains($0.id)) }
    }
    var body: some View {
        Section("Evento") {
            RecordTextField(title: "Nombre del show", record: $record, key: "name")
            RecordDateField(title: "Fecha", record: $record, key: "date", start: session.detail?.period.start ?? "", end: session.detail?.period.end ?? "")
            RecordNumberField(title: "Venta del show", record: $record, key: "sale")
        }
        Section("Participantes y honorarios") {
            ForEach(people) { ParticipantField(record: $record, employee: $0) }
            Text("Los honorarios son manuales y no dependen de las ventas. Cambiar el nombre o fecha actualiza también el recorrido de este show.").font(.footnote).foregroundStyle(.secondary)
        }
    }
}
struct ParticipantField: View {
    @Binding var record: JSONValue
    let employee: Employee
    private var selected: Bool { record["participants"].elements.contains { $0["employeeId"].text == employee.id } }
    var body: some View {
        Toggle(employee.name, isOn: Binding(get: { selected }, set: { on in
            var list = record["participants"].elements.filter { $0["employeeId"].text != employee.id }
            if on { list.append(.object(["employeeId": .string(employee.id), "amount": .number(employee.showRate)])) }
            record["participants"] = .array(list)
        }))
        if selected {
            VStack(alignment: .leading, spacing: 8) {
                Text("Honorario").font(.subheadline).foregroundStyle(.secondary)
                TextField("Honorario", value: Binding(get: {
                    record["participants"].elements.first { $0["employeeId"].text == employee.id }?["amount"].number ?? 0
                }, set: { amount in
                    record["participants"] = .array(record["participants"].elements.map { entry in
                        var value = entry; if value["employeeId"].text == employee.id { value["amount"] = .number(amount) }; return value
                    })
                }), format: .number.locale(Locale(identifier: "es_CO"))).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder).frame(minHeight: 44).accessibilityLabel("Honorario de \(employee.name)")
            }
        }
    }
}
struct MovementFields: View {
    @Binding var record: JSONValue
    let session: PayrollEditorSession
    @State private var selectedConcept = ""
    var body: some View {
        Section {
            RecordChoice(title: "Persona", record: $record, key: "employeeId", options: session.activeEmployees.map { ($0.id, $0.name) })
            Picker("Usar concepto", selection: $selectedConcept) {
                Text("Concepto libre").tag("")
                ForEach(Array(session.concepts.enumerated()), id: \.offset) { _, concept in Text(concept["name"].text).tag(concept["id"].text) }
            }.onChange(of: selectedConcept) { _, id in
                if let concept = session.concepts.first(where: { $0["id"].text == id }) { record["concept"] = concept["name"]; record["kind"] = concept["kind"]; record["amount"] = concept["amount"] }
            }
            RecordTextField(title: "Concepto", record: $record, key: "concept")
            RecordChoice(title: "Tratamiento", record: $record, key: "kind", options: PayrollChoices.kinds)
            RecordNumberField(title: "Cantidad", record: $record, key: "quantity")
            RecordNumberField(title: "Valor por unidad", record: $record, key: "amount")
            RecordTextField(title: "Nota", record: $record, key: "note", multiline: true)
        }
    }
}
struct HoursFields: View {
    @Binding var record: JSONValue
    let session: PayrollEditorSession
    var body: some View {
        Section {
            Text(session.detail?.employeeName(record["employeeId"].text) ?? "Dependiente").font(.headline)
            RecordNumberField(title: "Días trabajados", record: $record, key: "days")
            RecordNumberField(title: "Vacaciones (COP)", record: $record, key: "vacations")
            RecordTextField(title: "Nota", record: $record, key: "note", multiline: true)
        }
        Section("Horas del corte") { ForEach(Array(PayrollFormat.hourNames.enumerated()), id: \.offset) { ArrayNumberField(title: $0.element, record: $record, key: "counts", index: $0.offset) } }
        Section { Text("El servidor aplica los días, recargos, deducciones y corte de pago mensual según las condiciones de esta persona.").font(.footnote).foregroundStyle(.secondary) }
    }
}
struct RouteFields: View {
    @Binding var record: JSONValue
    let session: PayrollEditorSession
    var body: some View {
        Section {
            if !record["showId"].text.isEmpty {
                LabeledContent("Show", value: record["name"].text); LabeledContent("Fecha", value: PayrollFormat.date(record["date"].text))
            } else {
                RecordTextField(title: "Nombre del recorrido", record: $record, key: "name")
                RecordDateField(title: "Fecha", record: $record, key: "date", start: session.detail?.period.start ?? "", end: session.detail?.period.end ?? "")
            }
            RecordNumberField(title: "Kilómetros totales (ida y regreso)", record: $record, key: "km")
            if !record["employeeId"].text.isEmpty {
                RecordChoice(title: "Conductor", record: $record, key: "employeeId", options: session.activeEmployees.filter { $0.category == "conductores" }.map { ($0.id, $0.name) })
                    .onChange(of: record["employeeId"]) { _, value in if let employee = session.employees.first(where: { $0.id == value.text }) { record["rate"] = .number(employee.kmRate) } }
                RecordNumberField(title: "Tarifa por kilómetro", record: $record, key: "rate")
            } else {
                ForEach(Array(record["drivers"].elements.enumerated()), id: \.offset) { _, driver in AmountRow(title: (session.detail?.employeeName(driver["employeeId"].text) ?? "") + " / km", value: driver["rate"].number) }
            }
        }
        Section {
            Text("El recorrido compartido registra una sola distancia. Cada conductor conserva su tarifa; cámbiala en Personal o en las condiciones del cierre si corresponde.").font(.footnote).foregroundStyle(.secondary)
            if record["legacyCount"].number > 0 { Text("Al guardar se consolidarán los registros anteriores que corresponden a este show.").font(.footnote).foregroundStyle(.orange) }
        }
    }
}
