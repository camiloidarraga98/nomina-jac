import SwiftUI

struct PeriodDetailView: View {
    @EnvironmentObject private var store: PayrollStore
    let summary: PeriodSummary
    let user: PayrollUser
    @State private var detail: PeriodDetail?
    @State private var error: String?
    @State private var loading = false
    @State private var section = "pagos"

    var body: some View {
        List {
            if let error {
                Section { InlineError(message: error); Button("Volver a intentar") { Task { await load() } } }
            }
            if let detail {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(detail.period.isClosed ? "Neto del cierre" : "Neto en preparación").font(.subheadline).foregroundStyle(.secondary)
                        Text(PayrollFormat.money(detail.calculation.total)).font(.largeTitle.weight(.bold)).minimumScaleFactor(0.6).lineLimit(1)
                        Label(detail.period.isClosed ? "Quincena cerrada" : "Quincena abierta", systemImage: detail.period.isClosed ? "lock.fill" : "pencil")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
                Section {
                    Picker("Vista de la quincena", selection: $section) {
                        Text("Pagos").tag("pagos")
                        Text("Actividad").tag("actividad")
                        Text("Documentos").tag("documentos")
                    }.pickerStyle(.segmented)
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                if section == "pagos" { payments(detail) }
                else if section == "actividad" { activity(detail) }
                else { DocumentsSection(detail: detail, user: user) }
            } else if loading {
                Section { HStack { Spacer(); ProgressView("Consultando quincena…"); Spacer() } }
            }
        }
        .navigationTitle(summary.title).navigationBarTitleDisplayMode(.inline)
        .task(id: summary.id) { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder private func payments(_ detail: PeriodDetail) -> some View {
        Section("Resumen") {
            AmountRow(title: "Ingresos", value: detail.calculation.gross)
            AmountRow(title: "Descuentos", value: detail.calculation.deductions)
            AmountRow(title: "Reintegros", value: detail.calculation.reimbursements)
            AmountRow(title: "Ventas de shows", value: detail.calculation.sale)
        }
        Section("Pagos del equipo") {
            if detail.calculation.rows.isEmpty { Text("No hay pagos en esta quincena.").foregroundStyle(.secondary) }
            ForEach(Array(detail.calculation.rows.enumerated()), id: \.offset) { _, row in
                NavigationLink { PaymentDetailView(row: row, period: detail.period, user: user) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(row.name).font(.headline)
                        HStack { Text(PayrollFormat.category(row.category)); Spacer(); Text(PayrollFormat.money(row.net)).fontWeight(.semibold) }
                            .font(.subheadline)
                    }.padding(.vertical, 4)
                }
            }
        }
        if !detail.closeIssues.isEmpty {
            Section("Pendiente para el cierre") {
                ForEach(detail.closeIssues, id: \.self) { Text($0).font(.subheadline) }
            }
        }
    }

    @ViewBuilder private func activity(_ detail: PeriodDetail) -> some View {
        Section("Shows") {
            if detail.period.shows.isEmpty { Text("Sin shows registrados.").foregroundStyle(.secondary) }
            ForEach(detail.period.shows) { show in
                NavigationLink {
                    List {
                        Section { LabeledContent("Fecha", value: PayrollFormat.date(show.date)); AmountRow(title: "Venta", value: show.sale) }
                        Section("Honorarios por participante") {
                            ForEach(show.participants, id: \.employeeId) { participant in
                                AmountRow(title: detail.employeeName(participant.employeeId), value: participant.amount)
                            }
                        }
                    }.navigationTitle(show.name).navigationBarTitleDisplayMode(.inline)
                } label: {
                    VStack(alignment: .leading) { Text(show.name).font(.headline); Text(PayrollFormat.date(show.date)).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        Section("Recorridos") {
            if detail.period.routes.isEmpty { Text("Sin recorridos registrados.").foregroundStyle(.secondary) }
            ForEach(detail.period.routes) { route in
                VStack(alignment: .leading, spacing: 5) {
                    Text(route.kind == "extra" ? "Kilometraje extra · \(route.name)" : route.name).font(.headline)
                    Text("\(PayrollFormat.date(route.date)) · \(PayrollFormat.number(route.km)) km").font(.subheadline).foregroundStyle(.secondary)
                    ForEach(route.participants, id: \.employeeId) { driver in
                        Text("\(detail.employeeName(driver.employeeId)) · \(PayrollFormat.money(driver.rate))/km").font(.caption)
                    }
                }.padding(.vertical, 4)
            }
        }
        Section("Novedades y descuentos") {
            if detail.period.movements.isEmpty { Text("Sin novedades registradas.").foregroundStyle(.secondary) }
            ForEach(detail.period.movements) { movement in
                VStack(alignment: .leading, spacing: 5) {
                    Text(movement.concept).font(.headline)
                    Text(detail.employeeName(movement.employeeId)).font(.subheadline)
                    Text("\(PayrollFormat.number(movement.quantity)) × \(PayrollFormat.money(movement.amount))").font(.caption).foregroundStyle(.secondary)
                    if !movement.note.isEmpty { Text(movement.note).font(.caption).foregroundStyle(.secondary) }
                }.padding(.vertical, 4)
            }
        }
        Section("Horas y salarios") {
            if detail.period.hours.isEmpty { Text("Sin novedades de horas registradas.").foregroundStyle(.secondary) }
            ForEach(detail.period.hours, id: \.employeeId) { hours in
                NavigationLink {
                    List {
                        Section { LabeledContent("Días trabajados", value: PayrollFormat.number(hours.days)); AmountRow(title: "Vacaciones", value: hours.vacations) }
                        Section("Horas registradas") {
                            ForEach(Array(hours.counts.enumerated()), id: \.offset) { index, count in
                                LabeledContent(index < PayrollFormat.hourNames.count ? PayrollFormat.hourNames[index] : "Horas", value: PayrollFormat.number(count))
                            }
                        }
                        if !hours.note.isEmpty { Section("Nota") { Text(hours.note) } }
                    }.navigationTitle(detail.employeeName(hours.employeeId)).navigationBarTitleDisplayMode(.inline)
                } label: { Text(detail.employeeName(hours.employeeId)) }
            }
        }
    }

    private func load() async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        do { detail = try await store.client.detail(periodID: summary.id) }
        catch { self.error = error.localizedDescription; store.report(error) }
    }
}

struct AmountRow: View {
    let title: String
    let value: Double
    var body: some View {
        LabeledContent { Text(PayrollFormat.money(value)).monospacedDigit().multilineTextAlignment(.trailing) } label: { Text(title) }
    }
}
