import SwiftUI

struct CalendarView: View {
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.scenePhase) private var phase
    let user: PayrollUser
    @State private var month = CalendarClock.month(Date())
    @State private var day = CalendarClock.day(Date())
    @State private var feed: AgendaData?
    @State private var byDay: [String: [AgendaEvent]] = [:]
    @State private var mode = "Mes"
    @State private var loading = false
    @State private var error: String?
    @State private var settings = false
    @State private var event: AgendaEvent?
    @State private var requestID = UUID()
    @State private var refreshedAt = Date.distantPast
    private var visible: AgendaData? { feed?.month == month ? feed : nil }
    var body: some View {
        NavigationStack {
            List {
                if let error { Section { InlineError(message: error); Button("Reintentar") { Task { await refresh() } } } }
                if let connection = feed?.connection {
                    Section {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(connection.selected?.name ?? "Agenda de Jhon Alex").font(.headline)
                            Text(connection.connected ? "Google Calendar · Hora de Colombia" : "Conecta Google y selecciona el calendario de Jhon Alex.").font(.caption).foregroundStyle(.secondary)
                        }
                        if !connection.connected || connection.selected == nil {
                            if user.isOwner { Button("Preparar conexión") { settings = true }.accessibilityIdentifier("agenda.configure") }
                            else { Text("Camilo prepara la agenda compartida para el equipo.").font(.footnote).foregroundStyle(.secondary) }
                        }
                    }
                }
                if loading && visible == nil { Section { ProgressView("Consultando agenda…") } }
                if let visible, visible.connection.connected, visible.connection.selected != nil {
                    Section { Picker("Vista de agenda", selection: $mode) { Text("Mes").tag("Mes"); Text("Próximos").tag("Próximos") }.pickerStyle(.segmented).accessibilityIdentifier("agenda.mode") }
                    if mode == "Mes" {
                        Section {
                            HStack {
                                Button { shift(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Mes anterior")
                                Spacer(); Text(visible.monthLabel.capitalized).font(.headline); Spacer()
                                Button { shift(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Mes siguiente")
                            }.buttonStyle(.borderless)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 5) {
                                ForEach(["L", "M", "X", "J", "V", "S", "D"], id: \.self) { Text($0).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                                ForEach(visible.days, id: \.self) { date in
                                    let count = byDay[date]?.count ?? 0
                                    Button { day = date } label: {
                                        VStack(spacing: 4) {
                                            Text(String(Int(date.suffix(2)) ?? 0)).font(.subheadline.weight(day == date ? .bold : .regular))
                                            HStack(spacing: 2) { ForEach(0..<min(count, 3), id: \.self) { _ in Circle().fill(Color.accentColor).frame(width: 4, height: 4) } }.frame(height: 4)
                                        }.frame(maxWidth: .infinity, minHeight: 42).background(day == date ? Color.accentColor.opacity(0.17) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                            .foregroundStyle(date.hasPrefix(month) ? Color.primary : .secondary)
                                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(date == visible.today ? Color.accentColor : .clear, lineWidth: 1))
                                    }.buttonStyle(.plain).accessibilityLabel(CalendarClock.dayLabel(date) + ", \(count) eventos").accessibilityAddTraits(day == date ? .isSelected : []).accessibilityIdentifier("agenda.day.\(date)")
                                }
                            }
                            Button("Hoy") { month = CalendarClock.month(Date()); day = CalendarClock.day(Date()) }.buttonStyle(.borderless)
                        }
                        Section(CalendarClock.dayLabel(day).capitalized) {
                            let events = byDay[day] ?? []
                            if events.isEmpty { Text("No hay eventos para este día.").foregroundStyle(.secondary) }
                            ForEach(events) { item in Button { event = item } label: { AgendaEventRow(event: item) }.buttonStyle(.plain).accessibilityIdentifier("agenda.event.\(item.id)") }
                        }
                    } else {
                        Section {
                            Text("Próximos 90 días · hasta " + CalendarClock.dayLabel(visible.upcomingUntil)).font(.caption).foregroundStyle(.secondary)
                            if visible.upcoming.isEmpty { Text("No hay eventos programados en los próximos 90 días.").foregroundStyle(.secondary) }
                            ForEach(visible.upcoming) { item in Button { event = item } label: { AgendaEventRow(event: item, showsDay: true) }.buttonStyle(.plain).accessibilityIdentifier("agenda.upcoming.\(item.id)") }
                        }
                    }
                    Section { Text("Actualizado " + CalendarClock.time(CalendarClock.instant(visible.updatedAt) ?? Date())).font(.caption).foregroundStyle(.secondary) }
                }
            }.navigationTitle("Agenda").refreshable { await refresh() }
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { Task { await refresh() } } label: { if loading { ProgressView() } else { Image(systemName: "arrow.clockwise") } }.accessibilityLabel("Actualizar agenda").disabled(loading)
                        if user.isOwner { Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Conexión de Agenda").accessibilityIdentifier("agenda.configure").disabled(feed == nil) }
                    }
                }
                .task(id: month) { await refresh() }
                .onChange(of: phase) { _, value in if value == .active && Date().timeIntervalSince(refreshedAt) > 30 { Task { await refresh() } } }
                .sheet(isPresented: $settings) { if let connection = feed?.connection { CalendarConnectionView(connection: connection, user: user) { await refresh() } } }
                .sheet(item: $event) { AgendaEventDetail(event: $0) }
        }
    }
    private func shift(_ offset: Int) {
        if let next = CalendarClock.shift(month, by: offset) { month = next; day = next + "-01" }
    }
    private func refresh() async {
        let id = UUID(); requestID = id; let currentMonth = month
        loading = true; error = nil
        defer { if requestID == id { loading = false } }
        do { let result = try await store.client.agenda(month: currentMonth); guard requestID == id, month == currentMonth else { return }; byDay = CalendarClock.eventsByDay(result.events, days: result.days); feed = result; refreshedAt = Date() }
        catch is CancellationError { }
        catch { if requestID == id { self.error = error.localizedDescription; store.report(error) } }
    }
}
struct AgendaEventRow: View {
    let event: AgendaEvent
    var showsDay = false
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if showsDay { Text(CalendarClock.dayLabel(event.firstDay).capitalized).font(.caption).foregroundStyle(.tint) }
            Text(event.title).font(.headline)
            Label(event.timeLabel, systemImage: "clock").font(.subheadline).foregroundStyle(.secondary)
            if !event.location.isEmpty { Label(event.location, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 4)
    }
}
struct AgendaEventDetail: View {
    @Environment(\.dismiss) private var dismiss
    let event: AgendaEvent
    var body: some View {
        NavigationStack {
            List {
                Section { Text(event.title).font(.title2.bold()); Label(CalendarClock.dayLabel(event.firstDay).capitalized, systemImage: "calendar"); Label(event.timeLabel, systemImage: "clock"); Text("Hora de Colombia").font(.caption).foregroundStyle(.secondary) }
                if event.allDay, let last = CalendarClock.date(event.end), let end = CalendarClock.calendar.date(byAdding: .day, value: -1, to: last), CalendarClock.day(end) != event.start { Section { Text("Hasta " + CalendarClock.dayLabel(CalendarClock.day(end))) } }
                if !event.location.isEmpty { Section("Lugar") { Text(event.location).textSelection(.enabled) } }
                if !event.description.isEmpty { Section("Descripción") { Text(event.description).textSelection(.enabled) } }
                if let url = event.googleURL { Section { Link("Ver en Google Calendar", destination: url) } }
            }.navigationTitle("Evento").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
        }
    }
}
struct CalendarConnectionView: View {
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.dismiss) private var dismiss
    let user: PayrollUser
    let onUpdate: () async -> Void
    @State private var connection: AgendaConnection
    @State private var calendars: [AgendaCalendar] = []
    @State private var selection = ""
    @State private var loading = false
    @State private var error: String?
    @State private var confirmDisconnect = false
    @StateObject private var authorizer = CalendarAuthorizerHolder()
    init(connection: AgendaConnection, user: PayrollUser, onUpdate: @escaping () async -> Void) { _connection = State(initialValue: connection); self.user = user; self.onUpdate = onUpdate }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("jacmusicestudios@gmail.com").font(.headline)
                    Text("Elige el calendario de Jhon Alex para compartir su agenda con los usuarios activos de JAC.").font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Section { InlineError(message: error); Button("Reintentar") { Task { await loadCalendars() } } } }
                if !connection.configured { Section { Text("Prepara primero la conexión de Google en Correos."); NavigationLink("Abrir Correos y Gmail") { MailView(user: user) } } }
                else {
                    Section {
                        Link("Activar Google Calendar API", destination: URL(string: "https://console.cloud.google.com/apis/library/calendar-json.googleapis.com")!)
                        Text("Actívala en el proyecto de Google que utilizas para JAC y autoriza la lectura de la agenda.").font(.footnote).foregroundStyle(.secondary)
                        Button(connection.connected ? "Volver a autorizar Google" : "Conectar Google") { Task { await connect() } }.disabled(loading || store.hasPending).accessibilityIdentifier("agenda.connect")
                        if store.hasPending { Text("Resuelve los cambios de nómina pendientes antes de abrir Google.").font(.footnote).foregroundStyle(.secondary) }
                    }
                    if connection.connected {
                        Section("Calendario de la agenda") {
                            if loading { ProgressView() }
                            if !calendars.isEmpty { Picker("Calendario", selection: $selection) { ForEach(calendars) { calendar in Text(calendar.name + (calendar.primary ? " · Principal" : "")).tag(calendar.id) } } }
                            Button("Usar este calendario") { Task { await select() } }.disabled(loading || selection.isEmpty)
                        }
                        Section { Button("Desconectar Agenda", role: .destructive) { confirmDisconnect = true }.disabled(loading) }
                    }
                }
            }.navigationTitle("Conexión de Agenda").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
                .task { await loadCalendars() }
                .confirmationDialog("El equipo dejará de consultar este calendario desde JAC. Los eventos continúan en Google Calendar.", isPresented: $confirmDisconnect, titleVisibility: .visible) { Button("Desconectar Agenda", role: .destructive) { Task { await disconnect() } } }
        }
    }
    private func loadCalendars() async {
        guard connection.connected else { return }; loading = true; error = nil; defer { loading = false }
        do { calendars = try await store.client.agendaCalendars(); selection = connection.selected?.id ?? calendars.first?.id ?? "" }
        catch { self.error = error.localizedDescription; store.report(error) }
    }
    private func connect() async {
        loading = true; error = nil
        do {
            let start = try await store.client.startAgenda()
            try await authorizer.value.authorize(start)
            connection = try await store.client.agenda(month: CalendarClock.month(Date())).connection
            loading = false; await onUpdate(); await loadCalendars()
        } catch { loading = false; self.error = error.localizedDescription; store.report(error) }
    }
    private func select() async {
        loading = true; error = nil; defer { loading = false }
        do { let result = try await store.client.agendaOperation(action: "select", revision: connection.revision, calendarID: selection); connection = result.connection; await onUpdate(); dismiss() }
        catch { self.error = error.localizedDescription; store.report(error) }
    }
    private func disconnect() async {
        loading = true; error = nil; defer { loading = false }
        do { let result = try await store.client.agendaOperation(action: "disconnect", revision: connection.revision); connection = result.connection; await onUpdate(); dismiss() }
        catch { self.error = error.localizedDescription; store.report(error) }
    }
}
@MainActor private final class CalendarAuthorizerHolder: ObservableObject { let value = CalendarAuthorizer() }
