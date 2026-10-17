import SwiftUI

struct CalendarView: View {
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.scenePhase) private var phase
    let user: PayrollUser
    @StateObject private var connectivity = AgendaConnectivity()
    @State private var month = CalendarClock.month(Date())
    @State private var day = CalendarClock.day(Date())
    @State private var feed: AgendaData?
    @State private var mode = "Mes"
    @State private var loading = false
    @State private var error: String?
    @State private var settings = false
    @State private var event: AgendaEvent?
    @State private var editor: AgendaEditorSession?
    @State private var editAfterDetail: AgendaEvent?
    @State private var notice: String?
    @State private var requestID = UUID()
    @State private var refreshedAt = Date.distantPast
    @State private var liveMonth: String?
    @State private var contentWidth: CGFloat = 0
    private var wideTablet: Bool { JACDevice.isPad && contentWidth >= 820 }
    @State private var offlineMessage: String?
    init(user: PayrollUser, initialMonth: String? = nil) {
        self.user = user
        let month = initialMonth ?? CalendarClock.month(Date())
        _month = State(initialValue: month)
        _day = State(initialValue: month == CalendarClock.month(Date()) ? CalendarClock.day(Date()) : month + "-01")
    }
    private var visible: AgendaData? { (feed?.month == month ? feed : nil) ?? store.cachedAgenda(month: month, userID: user.id)?.data ?? store.client.cached(AgendaData.self, path: "api/calendar", query: [URLQueryItem(name: "month", value: month)]) }
    private var live: Bool { liveMonth == month && !store.isAgendaOnly && connectivity.connected != false && !store.isOffline }
    var body: some View {
        let byDay = visible.map { CalendarClock.eventsByDay($0.events, days: $0.days) } ?? [:]
        return NavigationStack {
            AgendaPage {
                if let notice { AgendaSection { Label(notice, systemImage: "checkmark.circle").foregroundStyle(JACTheme.action) } }
                if let error { AgendaSection { InlineError(message: error); Button("Reintentar") { Task { await refresh() } } } }
                if visible == nil, let offlineMessage {
                    AgendaSection {
                        ContentUnavailableView("Mes sin descargar", systemImage: "wifi.slash", description: Text(offlineMessage))
                        if store.savedAgenda != nil { Button("Volver a la agenda descargada") { month = store.preferredAgendaMonth; day = month == CalendarClock.month(Date()) ? CalendarClock.day(Date()) : month + "-01" } }
                    }
                }
                if let connection = visible?.connection, !connection.connected || connection.selected == nil {
                    AgendaSection {
                        Text("Conecta Google y selecciona el calendario de Jhon Alex.").font(.footnote).foregroundStyle(.secondary)
                        if live {
                            if user.isOwner { Button("Preparar conexión") { settings = true }.accessibilityIdentifier("agenda.configure") }
                            else { Text("Camilo prepara la agenda compartida para el equipo.").font(.footnote).foregroundStyle(.secondary) }
                        }
                    }
                }
                if loading && visible == nil { AgendaSection { ProgressView("Consultando agenda…") } }
                if visible == nil || visible?.connection.connected != true || visible?.connection.selected == nil {
                    AgendaSection { agendaActions }
                }
                if let visible, visible.connection.connected, visible.connection.selected != nil {
                    AgendaSection { Picker("Vista de agenda", selection: $mode) { Text("Mes").tag("Mes"); Text("Próximos").tag("Próximos") }.pickerStyle(.segmented).accessibilityIdentifier("agenda.mode") }
                    if mode == "Mes" {
                        if wideTablet {
                            AgendaSection {
                                HStack(alignment: .top, spacing: 28) {
                                    VStack(spacing: 12) { monthPanel(visible, byDay: byDay) }.frame(minWidth: 350, maxWidth: 490)
                                    VStack(alignment: .leading, spacing: 18) {
                                        Text(CalendarClock.dayLabel(day).capitalized).font(.headline)
                                        dayEvents(byDay)
                                    }.frame(maxWidth: .infinity, alignment: .topLeading).padding(.top, 8)
                                }.padding(.vertical, 8).accessibilityElement(children: .contain).accessibilityIdentifier("ipad.agenda.columns")
                            }
                        } else {
                            AgendaSection { monthPanel(visible, byDay: byDay) }
                            AgendaSection(title:CalendarClock.dayLabel(day).capitalized) { dayEvents(byDay) }
                        }
                    } else {
                        AgendaSection { agendaActions }
                        AgendaSection {
                            Text("Próximos 90 días · hasta " + CalendarClock.dayLabel(visible.upcomingUntil)).font(.caption).foregroundStyle(.secondary)
                            if visible.upcoming.isEmpty { Text("No hay eventos programados en los próximos 90 días.").foregroundStyle(.secondary) }
                            ForEach(visible.upcoming) { item in Button { event = item } label: { AgendaEventRow(event: item, showsDay: true) }.buttonStyle(.plain).accessibilityIdentifier("agenda.upcoming.\(item.id)") }
                        }
                    }
                    if offlineMessage != nil || store.isOffline {
                        AgendaSection { Label(offlineMessage ?? "Sin conexión · Copia guardada", systemImage: "wifi.slash").font(.footnote).accessibilityIdentifier("agenda.offline") }
                    }
                    if let warning = store.agendaStorageWarning {
                        AgendaSection { Text(warning).font(.footnote).foregroundStyle(.secondary) }
                    }
                    if live && user.isOwner && visible.canEditEvents != true {
                        AgendaSection { Text(visible.connection.writeAuthorized == true ? "Este calendario permite consultar. Elige en Conexión uno que puedas editar." : "Abre Conexión y vuelve a autorizar Google para crear y editar eventos.").font(.footnote).foregroundStyle(.secondary) }
                    }
                }
            }.background { GeometryReader { geometry in Color.clear.onAppear { contentWidth = geometry.size.width }.onChange(of: geometry.size.width) { _, width in contentWidth = width } }.allowsHitTesting(false) }.jacSurface().navigationTitle("Agenda").jacInlineTitle().refreshable { await refresh() }.jacRefreshCommand { Task { await refresh() } }
                .toolbar {
                    if user.isOwner { ToolbarItem(placement:.jacTrailing) { Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Conexión de Agenda").accessibilityIdentifier("agenda.configure").disabled(!live) } }
                }
                .task(id: month) {
                    await refresh()
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(30)) } catch { return }
                        if phase == .active && connectivity.connected != false { await refresh() }
                    }
                }
                .onChange(of: phase) { _, value in if value == .active { Task { await refresh() } } }
                .onChange(of: connectivity.connected) { old, new in if old == false && new == true { Task { await refresh() } } }
                .sheet(isPresented: $settings) { if let connection = feed?.connection { CalendarConnectionView(connection: connection, user: user) { await refresh() } } }
                .sheet(item: $event, onDismiss: { if let item = editAfterDetail, let visible { editor = AgendaEditorSession(event: item, day: day, revision: visible.connection.revision); editAfterDetail = nil } }) { item in
                    AgendaEventDetail(event: item, onEdit: live && visible?.canEditEvents == true && item.editable == true ? { editAfterDetail = item; event = nil } : nil)
                }
                .sheet(item: $editor) { session in AgendaEventEditor(session: session) { result in notice = result.notice; await refresh() } }
        }
    }
    private func monthPanel(_ visible: AgendaData, byDay: [String: [AgendaEvent]]) -> some View {
        Group {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Mes anterior")
                Spacer(); Text(visible.monthLabel.capitalized).font(.headline); Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Mes siguiente")
            }.buttonStyle(JACSecondaryButtonStyle(tone:.teal))
            .padding(.vertical,4)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 5) {
                ForEach(["L", "M", "X", "J", "V", "S", "D"], id: \.self) { Text($0).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                ForEach(visible.days, id: \.self) { date in
                    let count = byDay[date]?.count ?? 0
                    Button { day = date } label: {
                        VStack(spacing: 4) {
                            Text(String(Int(date.suffix(2)) ?? 0)).font(.subheadline.weight(day == date ? .bold : .regular))
                            HStack(spacing: 2) { ForEach(0..<min(count, 3), id: \.self) { _ in Circle().fill(day == date ? Color.white : JACTone.teal.color).frame(width: 4, height: 4) } }.frame(height: 4)
                        }.frame(maxWidth: .infinity, minHeight: JACDevice.isPad ? 56 : 42).background(day == date ? JACTheme.primary : .clear, in: RoundedRectangle(cornerRadius: 13))
                            .foregroundStyle(day == date ? .white : date.hasPrefix(month) ? JACTheme.ink : .secondary)
                            .overlay(RoundedRectangle(cornerRadius: 13).stroke(date == visible.today ? JACTone.teal.color : .clear, lineWidth: 1))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(CalendarClock.dayLabel(date) + ", \(count) eventos").accessibilityValue(day == date ? "Seleccionado":"").accessibilityAddTraits(day == date ? .isSelected : []).accessibilityIdentifier("agenda.day.\(date)")
                }
            }
            ViewThatFits(in:.horizontal) {
                HStack { todayButton; Spacer(); agendaActions }
                VStack(alignment:.leading,spacing:10) { todayButton; agendaActions }
            }.padding(.top,10)
        }
    }
    @ViewBuilder private func dayEvents(_ byDay: [String: [AgendaEvent]]) -> some View {
            let events = byDay[day] ?? []
            if events.isEmpty { Text("No hay eventos para este día.").foregroundStyle(.secondary) }
            ForEach(events) { item in Button { event = item } label: { AgendaEventRow(event: item) }.buttonStyle(.plain).accessibilityIdentifier("agenda.event.\(item.id)") }
    }
    private var todayButton: some View {
        Button("Hoy") { month = CalendarClock.month(Date()); day = CalendarClock.day(Date()) }.buttonStyle(JACSecondaryButtonStyle(tone:.teal))
    }
    private var agendaActions: some View {
        HStack(spacing:10) {
            Button { Task { await refresh() } } label: { if loading { ProgressView() } else { Image(systemName:"arrow.clockwise") } }
                .buttonStyle(JACSecondaryButtonStyle(tone:.teal)).accessibilityLabel("Actualizar agenda").accessibilityIdentifier(loading ? "agenda.updating":"agenda.refresh").disabled(loading)
            if live, let visible, visible.canEditEvents == true {
                Button { editor = AgendaEditorSession(event:nil,day:day,revision:visible.connection.revision) } label: { Label("Nuevo evento",systemImage:"plus") }
                    .buttonStyle(JACPrimaryButtonStyle()).accessibilityLabel("Crear evento").accessibilityIdentifier("agenda.create").disabled(loading)
            }
        }
    }
    private func shift(_ offset: Int) {
        if let next = CalendarClock.shift(month, by: offset) { month = next; day = next + "-01" }
    }
    private func refresh() async {
        let id = UUID(); requestID = id; let currentMonth = month
        loading = true; error = nil; offlineMessage = nil
        defer { if requestID == id { loading = false } }
        do {
            if store.isAgendaOnly { try await store.refreshAutomatically() }
            guard let scope = try store.client.agendaScope() else { throw APIError.unauthorized }
            let result = try await store.client.agenda(month: currentMonth)
            guard requestID == id, month == currentMonth else { return }
            try store.rememberAgenda(result, userID: user.id, scope: scope)
            feed = result; liveMonth = currentMonth; refreshedAt = Date()
        } catch {
            guard requestID == id else { return }
            liveMonth = nil
            if let api = error as? APIError {
                switch api {
                case .unauthorized, .forbidden: store.forgetAgenda(); feed = nil
                default: break
                }
            }
            if AgendaOfflineCache.isUnavailable(error) || store.isOffline { offlineMessage = visible != nil ? "Sin conexión. Puedes consultar la última agenda descargada." : "Necesitas conexión para descargar este mes. Los meses guardados siguen disponibles." }
            else { self.error = store.reportReadFailure(error) }
        }
    }
}
struct AgendaEventRow: View {
    let event: AgendaEvent
    var showsDay = false
    var body: some View {
        HStack(alignment:.top,spacing:14) {
            RoundedRectangle(cornerRadius:3).fill(JACTone.teal.color).frame(width:4)
            VStack(alignment:.leading,spacing:9) {
                if showsDay { JACBadge(title:CalendarClock.dayLabel(event.firstDay).capitalized,tone:.teal) }
                Text(event.title).font(.system(.headline,design:.rounded))
                Label(event.timeLabel,systemImage:"clock").font(.subheadline).foregroundStyle(JACTone.teal.color)
                if !event.location.isEmpty { Label(event.location,systemImage:"mappin.and.ellipse").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength:0)
            Image(systemName:"arrow.up.right").font(.caption).foregroundStyle(JACTone.teal.color).accessibilityHidden(true)
        }.padding(.vertical,10).fixedSize(horizontal:false,vertical:true)
    }
}
struct AgendaEventDetail: View {
    @Environment(\.dismiss) private var dismiss
    let event: AgendaEvent
    var onEdit: (() -> Void)? = nil
    var body: some View {
        NavigationStack {
            AgendaPage {
                AgendaSection { Text(event.title).font(.title2.bold()); Label(CalendarClock.dayLabel(event.firstDay).capitalized, systemImage: "calendar"); Label(event.timeLabel, systemImage: "clock"); Text("Hora de Colombia").font(.caption).foregroundStyle(.secondary) }
                if event.allDay, let last = CalendarClock.date(event.end), let end = CalendarClock.calendar.date(byAdding: .day, value: -1, to: last), CalendarClock.day(end) != event.start { AgendaSection { Text("Hasta " + CalendarClock.dayLabel(CalendarClock.day(end))) } }
                if !event.location.isEmpty { AgendaSection(title:"Lugar") { Text(event.location).textSelection(.enabled) } }
                if !event.description.isEmpty { AgendaSection(title:"Descripción") { Text(event.description).textSelection(.enabled) } }
                if let onEdit { AgendaSection { Button("Editar evento", action: onEdit).buttonStyle(JACPrimaryButtonStyle()).accessibilityIdentifier("agenda.edit") } }
                if let url = event.googleURL { AgendaSection { Link("Ver en Google Calendar", destination: url) } }
            }.jacSurface().navigationTitle("Evento").jacInlineTitle().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
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
                        Text("Actívala en el proyecto de Google que utilizas para JAC. Autoriza consultar calendarios y editar eventos. La selección actual se conserva al volver a autorizar.").font(.footnote).foregroundStyle(.secondary)
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
            }.jacSurface().navigationTitle("Conexión de Agenda").jacInlineTitle()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
                .task { await loadCalendars() }
                .confirmationDialog("El equipo dejará de consultar este calendario desde JAC. Los eventos continúan en Google Calendar.", isPresented: $confirmDisconnect, titleVisibility: .visible) { Button("Desconectar Agenda", role: .destructive) { Task { await disconnect() } } }
        }
    }
    private func loadCalendars() async {
        guard connection.connected else { return }; loading = true; error = nil; defer { loading = false }
        do { calendars = try await store.client.agendaCalendars(); selection = connection.selected?.id ?? calendars.first?.id ?? "" }
        catch { self.error = store.reportReadFailure(error) }
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

struct AgendaEditorSession: Identifiable {
    let id = UUID()
    let event: AgendaEvent?
    let day: String
    let revision: Int
}
struct AgendaEventEditor: View {
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.dismiss) private var dismiss
    let session: AgendaEditorSession
    let onSaved: (AgendaEventMutation) async -> Void
    @State private var title: String
    @State private var location: String
    @State private var description: String
    @State private var allDay: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var busy = false
    @State private var error: String?
    init(session: AgendaEditorSession, onSaved: @escaping (AgendaEventMutation) async -> Void) {
        self.session = session; self.onSaved = onSaved
        let event = session.event, day = CalendarClock.date(session.day) ?? Date()
        _title = State(initialValue: event?.title ?? ""); _location = State(initialValue: event?.location ?? ""); _description = State(initialValue: event?.description ?? "")
        _allDay = State(initialValue: event?.allDay ?? false)
        let from = event.map { $0.allDay ? CalendarClock.date($0.start) : CalendarClock.instant($0.start) } ?? nil
        let to = event.map { item -> Date? in
            if item.allDay, let exclusive = CalendarClock.date(item.end) { return CalendarClock.calendar.date(byAdding: .day, value: -1, to: exclusive) }
            return CalendarClock.instant(item.end)
        } ?? nil
        _start = State(initialValue: from ?? CalendarClock.calendar.date(bySettingHour: 19, minute: 0, second: 0, of: day)!)
        _end = State(initialValue: to ?? CalendarClock.calendar.date(bySettingHour: 21, minute: 0, second: 0, of: day)!)
    }
    var body: some View {
        NavigationStack {
            Form {
                if let error { Section { InlineError(message: error); Text("Tus datos siguen en el formulario. Si otra persona cambió el evento, cancela y abre la versión actual desde Agenda.").font(.footnote).foregroundStyle(.secondary) } }
                if session.event?.recurring == true { Section { Text("Editarás solo esta ocurrencia. Los demás eventos de la serie se conservan.").font(.footnote) } }
                Section {
                    TextField("Título", text: $title).accessibilityIdentifier("agenda.editor.title")
                    Toggle("Todo el día", isOn: $allDay).accessibilityIdentifier("agenda.editor.allDay")
                    JACDatePicker("Inicio", selection: $start, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute]).accessibilityIdentifier("agenda.editor.start")
                    JACDatePicker(allDay ? "Último día" : "Fin", selection: $end, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute]).accessibilityIdentifier("agenda.editor.end")
                } header: { Text("Evento") } footer: { Text("Hora de Colombia. Se guardará en el calendario seleccionado de Google.") }
                Section("Lugar y descripción") {
                    TextField("Lugar", text: $location).accessibilityIdentifier("agenda.editor.location")
                    TextField("Descripción", text: $description, axis: .vertical).lineLimit(4...10).accessibilityIdentifier("agenda.editor.description")
                }
                Section { Button(session.event == nil ? "Crear evento" : "Guardar evento") { Task { await save() } }.frame(maxWidth: .infinity).buttonStyle(JACPrimaryButtonStyle()).accessibilityIdentifier("agenda.editor.save") }
            }.jacSurface().navigationTitle(session.event == nil ? "Crear evento" : "Editar evento").jacInlineTitle()
                .environment(\.timeZone, CalendarClock.calendar.timeZone).environment(\.locale, Locale(identifier: "es_CO"))
                .disabled(busy).scrollDismissesKeyboard(.interactively)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(busy) }; ToolbarItem(placement: .confirmationAction) { if busy { ProgressView() } } }
        }.interactiveDismissDisabled(busy)
    }
    private func save() async {
        guard !busy else { return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 300, location.count <= 1024, description.count <= 8192, allDay ? CalendarClock.day(end) >= CalendarClock.day(start) : end > start else { error = "Revisa el título, las fechas y la longitud de los campos."; return }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let draft = AgendaEventDraft(title: name, start: allDay ? CalendarClock.day(start) : iso.string(from: start), end: allDay ? CalendarClock.day(CalendarClock.calendar.date(byAdding: .day, value: 1, to: end)!) : iso.string(from: end), allDay: allDay, location: location, description: description)
        busy = true; error = nil
        defer { busy = false }
        do { let result = try await store.client.saveAgendaEvent(draft, revision: session.revision, event: session.event, requestID: session.id); dismiss(); await onSaved(result) }
        catch is CancellationError { }
        catch { self.error = error.localizedDescription; store.report(error) }
    }
}

private struct AgendaPage<Content:View>:View {
    private let content:Content
    init(@ViewBuilder content:()->Content){self.content=content()}
    var body:some View {
        #if os(iOS)
        ScrollView {LazyVStack(alignment:.leading,spacing:18){content}.padding(18).frame(maxWidth:1160).frame(maxWidth:.infinity)}
        #else
        List {content}
        #endif
    }
}
private struct AgendaSection<Content:View>:View {
    private let title:String?
    private let content:Content
    init(title:String?=nil,@ViewBuilder content:()->Content){self.title=title;self.content=content()}
    var body:some View {
        #if os(iOS)
        VStack(alignment:.leading,spacing:14) {
            if let title {Text(title).font(.headline)}
            content
        }.frame(maxWidth:.infinity,alignment:.leading).padding(18).background(JACTheme.card,in:RoundedRectangle(cornerRadius:18))
        #else
        if let title {Section(title){content}}else{Section{content}}
        #endif
    }
}
