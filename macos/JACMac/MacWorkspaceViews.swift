import SwiftUI
import AppKit

struct MacRefreshActionKey: FocusedValueKey { typealias Value = () -> Void }
extension FocusedValues {
    var macRefresh: (() -> Void)? {
        get { self[MacRefreshActionKey.self] }
        set { self[MacRefreshActionKey.self] = newValue }
    }
}

struct MacPageHeader: View {
    let title: String
    let subtitle: String
    var symbol = "briefcase"
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 24, weight: .medium))
                .foregroundStyle(JACTheme.action).frame(width: 46, height: 46)
                .background(JACTheme.action.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(.title2, weight: .semibold))
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
    }
}

enum MacSettingsRoute: String, CaseIterable, Identifiable {
    case expenses, alerts, notifications, connections, employees, concepts, archive, mail, users
    var id: String { rawValue }
    var title: String {
        switch self {
        case .expenses: "Gastos de viaje"; case .alerts: "Alertas"; case .notifications: "Notificaciones"
        case .connections: "Servicios conectados"; case .employees: "Personal"; case .concepts: "Conceptos y reglas"
        case .archive: "Archivo"; case .mail: "Correos"; case .users: "Usuarios y permisos"
        }
    }
    var subtitle: String {
        switch self {
        case .expenses: "Facturas, borradores y reintegros"; case .alerts: "Avisos y publicaciones del equipo"
        case .notifications: "Preferencias de este Mac"; case .connections: "Calendar, Slack y Google Sheets"
        case .employees: "Personas, condiciones y tarifas"; case .concepts: "Parámetros de la liquidación"
        case .archive: "Quincenas cerradas y documentos"; case .mail: "Gmail y desprendibles de pago"
        case .users: "Cuentas y permisos de acceso"
        }
    }
    var symbol: String {
        switch self {
        case .expenses: "receipt"; case .alerts: "bell.badge"; case .notifications: "bell"
        case .connections: "point.3.connected.trianglepath.dotted"; case .employees: "person.2"
        case .concepts: "slider.horizontal.3"; case .archive: "archivebox"; case .mail: "envelope"
        case .users: "person.badge.key"
        }
    }
    var identifier: String {
        switch self {
        case .alerts: "notices.alerts"; case .concepts: "Conceptos y reglas"
        case .users: "Usuarios y permisos"; case .mail: "Correos y Gmail"
        default: "management." + rawValue
        }
    }
    func allowed(_ user: PayrollUser) -> Bool {
        switch self {
        case .expenses, .alerts, .notifications: true
        case .connections, .users: user.isOwner && user.itinerariesOnly != true
        default: user.itinerariesOnly != true
        }
    }
}

struct MacManagementView: View {
    @EnvironmentObject private var store: PayrollStore
    let user: PayrollUser
    @State private var route: MacSettingsRoute?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    MacPageHeader(title: "Configuración general", subtitle: "Las herramientas de tu equipo, en un solo lugar.", symbol: "gearshape")
                    if store.error != nil || store.pending != nil || store.notice != nil || store.isOffline {
                        VStack(alignment: .leading, spacing: 10) { OperationStatusSection() }
                    }
                    settingsGroup("Trabajo diario", items: [.expenses, .alerts])
                    settingsGroup("Administración", items: [.employees, .concepts, .archive, .mail])
                    settingsGroup("Preferencias y acceso", items: [.notifications, .connections, .users])
                }.padding(24).frame(maxWidth: 1120, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
            }.jacSurface().navigationTitle("Configuración")
                .navigationDestination(item: $route) { item in
                    if item.allowed(user) {
                        switch item {
                        case .expenses: TravelExpensesView()
                        case .alerts: NoticesView(user: user, kind: "alert")
                        case .notifications: NotificationSettingsView()
                        case .connections: MacConnectionsView()
                        case .employees: if let overview = store.overview { EmployeesView(overview: overview, embedded: true) }
                        case .concepts: ConceptsRulesView(user: user)
                        case .archive: if let overview = store.overview { PeriodsView(overview: overview, archive: true, embedded: true) }
                        case .mail: MailView(user: user)
                        case .users: UsersView()
                        }
                    }
                }
        }
    }
    @ViewBuilder private func settingsGroup(_ title: String, items: [MacSettingsRoute]) -> some View {
        let visible = items.filter { $0.allowed(user) }
        if !visible.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.headline).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 245), spacing: 14)], spacing: 14) {
                    ForEach(visible) { item in
                        Button { route = item } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.symbol).font(.system(size: 20)).foregroundStyle(JACTheme.action).frame(width: 28)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                                    Text(item.subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 2)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }.frame(maxWidth: .infinity, minHeight: 58, alignment: .leading).padding(14)
                                .background(JACTheme.card, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary, lineWidth: 1))
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).help(item.subtitle).accessibilityLabel(item.title).accessibilityIdentifier(item.identifier)
                    }
                }
            }
        }
    }
}

private struct MacConnectionsView: View {
    @EnvironmentObject private var store: PayrollStore
    var body: some View {
        Form {
            Section("Conexiones compartidas") {
                Text("JAC utiliza las conexiones existentes del equipo. Su configuración se administra desde el sitio con tu cuenta autorizada.").foregroundStyle(.secondary)
                Link("Abrir Servicios conectados…", destination: PayrollClient.productionURL.appendingPathComponent("configuracion/conexiones"))
                Link("Administrar Google Sheets en el CRM…", destination: PayrollClient.productionURL.appendingPathComponent("crm"))
            }
            Section("Correo") { Text("La conexión de Gmail está disponible en Configuración → Correos.").foregroundStyle(.secondary) }
        }.jacSurface().navigationTitle("Servicios conectados")
    }
}

struct MacCRMRow: Identifiable {
    let value: JSONValue
    var id: String { value["id"].text }
    var title: String { value["title"].text }
    var day: String { value["showDate"].text }
    var displayDate:String {
        guard let date=ReceiptParser.civilDate(day) else{return day}
        let f=DateFormatter();f.locale=Locale(identifier:"es_CO");f.timeZone=CalendarClock.calendar.timeZone;f.dateFormat="d MMM yyyy"
        return f.string(from:date)
    }
    var entrepreneur: String { value["entrepreneur"].text }
    var sale: Double { value["sale"].isNull ? -1 : value["sale"].number }
    var paid: Double { value["paid"].number }
    var balance: Double { value["balance"].isNull ? -1 : value["balance"].number }
    var active: Bool { value["status"].text == "active" && !["deleted", "deleting"].contains(value["sourceState"].text) }
    static func visible(_ values: [JSONValue], today: String, query: String, filter: MacCRMFilter) -> [MacCRMRow] {
        values.map(Self.init).filter { row in
            row.day >= today && row.value["status"].text != "ignored" && !["deleted", "deleting"].contains(row.value["sourceState"].text) &&
            (query.isEmpty || (row.title + " " + row.entrepreneur).localizedStandardContains(query)) &&
            (filter == .all || (filter == .pending && row.balance > 0) || (filter == .unpriced && row.value["sale"].isNull))
        }
    }
}
enum MacCRMFilter: String, CaseIterable { case all = "Todos", pending = "Con saldo", unpriced = "Sin precio" }

struct MacCRMHomeView: View {
    @EnvironmentObject private var store: PayrollStore
    @StateObject private var crm: CRMStore
    @State private var section = "shows"
    @State private var month = CalendarClock.month(Date())
    @State private var search = ""
    @State private var filter = MacCRMFilter.all
    @State private var selection: String?
    @State private var openedShow: String?
    @State private var sort = [KeyPathComparator(\MacCRMRow.day)]
    @State private var editor: CRMEditorRequest?
    @State private var error: String?
    @State private var busy = false
    @State private var lastSync = Date.distantPast
    @State private var queuedReload = false
    @State private var queuedSync = false
    init(client: PayrollClient) { _crm = StateObject(wrappedValue: CRMStore(client)) }
    private var feed: JSONValue { crm.feed }
    private var rows: [MacCRMRow] { MacCRMRow.visible(feed["shows"].elements, today: BoardingClock.today(), query: search, filter: filter).sorted(using: sort) }
    private var selected: MacCRMRow? { rows.first { $0.id == selection } }
    private var canWrite: Bool { !store.isOffline && !busy && !feed.isNull && !crm.denied }
    var body: some View {
        Group {
            if crm.denied || store.overview?.user.isOwner != true || store.overview?.user.itinerariesOnly == true {
                ContentUnavailableView("CRM no disponible", systemImage: "lock", description: Text("Solo administradores de JAC."))
            } else {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 18) {
                        MacPageHeader(title: "Shows y abonos", subtitle: "Ventas, comprobantes y preparación de cada fecha.")
                        HStack {
                            Picker("Sección", selection: $section) { Text("Shows").tag("shows"); Text("Semana").tag("weekly"); Text("Empresarios").tag("contacts") }
                                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 350).accessibilityIdentifier("crm.sections")
                            Spacer()
                            if busy { ProgressView().controlSize(.small).accessibilityLabel("Actualizando CRM") }
                        }
                        if let error { HStack { InlineError(message: error); Spacer(); Button("Reintentar") { Task { await load() } } } }
                        if store.isOffline { Label("Sin conexión · Consultando lo descargado", systemImage: "wifi.slash").font(.callout).foregroundStyle(.secondary) }
                    }.padding(22)
                    if section == "shows" { shows }
                    else { List { if section == "weekly" { CRMWeeklyView() } else { CRMContactsView() } }.jacSurface() }
                }.background(JACTheme.canvas).navigationTitle("CRM")
                    .modifier(MacCRMSearch(text:$search,enabled:section == "shows"))
                    .toolbar {
                        ToolbarItemGroup(placement: .primaryAction) {
                            Button { editor = CRMEditorRequest(kind: .payment, record: .null, feed: feed) } label: { Label("Registrar abono", systemImage: "plus.circle") }
                                .labelStyle(.titleAndIcon).disabled(!canWrite).accessibilityIdentifier("crm.quickPayment")
                            Button { editor = CRMEditorRequest(kind: .create, record: .null, feed: feed) } label: { Label("Nuevo show", systemImage: "plus") }
                                .labelStyle(.titleAndIcon).buttonStyle(.borderedProminent).tint(JACTheme.primary).disabled(!canWrite).accessibilityIdentifier("crm.create")
                            Menu {
                                Button("Actualizar shows de Calendar") { Task { await load(sync: true) } }.disabled(!canWrite)
                                Button("Sincronizar abonos pendientes") { Task { await syncSheets() } }.disabled(!canWrite || !feed["sheets"]["ready"].flag)
                            } label: { Image(systemName: "ellipsis.circle") }.help("Más opciones del CRM").accessibilityIdentifier("crm.add")
                        }
                    }
                    .focusedSceneValue(\.macRefresh, { Task { await load(sync: !store.isOffline) } })
                    .task {
                        await load(sync: !store.isOffline)
                        while !Task.isCancelled { do { try await Task.sleep(for: .seconds(30)); await load(sync: !store.isOffline && Date().timeIntervalSince(lastSync) > 60) } catch { break } }
                    }
                    .onChange(of: openedShow) { old, new in if old != nil && new == nil { Task { await load() } } }
                    .onChange(of: section) { _, next in if next == "shows" { Task { await load() } } }
                    .onChange(of: store.cacheRevision) { _, _ in if store.isOffline { restoreCached() } }
                    .onChange(of: crm.denied) { _, denied in if denied { editor = nil; openedShow = nil; selection = nil; crm.feed = .null } }
                    .sheet(item: $editor, onDismiss: { Task { await load() } }) { CRMEditor(request: $0).environmentObject(crm) }
                    .navigationDestination(item: $openedShow) { id in CRMShowView(id: id, contacts: feed["contacts"], feed: feed).environmentObject(crm) }
            }
        }.environmentObject(crm)
    }
    private var shows: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Picker("Mostrar", selection: $filter) { ForEach(MacCRMFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 180).accessibilityIdentifier("crm.filter")
                Spacer()
                DatePicker("Desde el mes", selection: Binding(get: { ReceiptParser.civilDate(month + "-01") ?? Date() }, set: { month = CalendarClock.month($0); selection = nil; Task { await load() } }), in: (ReceiptParser.civilDate(CalendarClock.month(Date()) + "-01") ?? Date())..., displayedComponents: .date)
                    .fixedSize().disabled(busy).accessibilityIdentifier("crm.month")
            }.padding(.horizontal, 22).padding(.bottom, 16)
            Divider()
            Table(rows, selection: $selection, sortOrder: $sort) {
                TableColumn("Show", value: \MacCRMRow.title) { row in
                    VStack(alignment: .leading, spacing: 3) { Text(row.title).fontWeight(.medium); if row.value["promotional"].flag { Text("Promocional").font(.caption).foregroundStyle(.secondary) } }
                        .accessibilityIdentifier("crm.show." + row.id)
                }.width(min: 130, ideal: 160)
                TableColumn("Fecha", value: \MacCRMRow.day) { row in Text(row.displayDate) }.width(min: 85, ideal: 90, max: 110)
                TableColumn("Empresario", value: \MacCRMRow.entrepreneur) { row in Text(row.entrepreneur.isEmpty ? "Sin registrar" : row.entrepreneur).foregroundStyle(row.entrepreneur.isEmpty ? .secondary : .primary) }.width(min: 90, ideal: 100)
                TableColumn("Venta", value: \MacCRMRow.sale) { row in money(row.value["sale"]) }.width(min: 110, ideal: 120).alignment(.trailing)
                TableColumn("Abonos", value: \MacCRMRow.paid) { row in money(row.value["paid"]) }.width(min: 100, ideal: 110).alignment(.trailing)
                TableColumn("Saldo", value: \MacCRMRow.balance) { row in money(row.value["balance"]).foregroundStyle(row.balance > 0 ? JACTheme.action : .primary) }.width(min: 110, ideal: 120).alignment(.trailing)
            }.tableStyle(.inset(alternatesRowBackgrounds:false)).accessibilityIdentifier("crm.table")
                .contextMenu(forSelectionType: String.self) { ids in
                    if let id = ids.first, let row = rows.first(where: { $0.id == id }) {
                        Button("Abrir show") { openedShow = id }
                        Button("Registrar abono") { editor = CRMEditorRequest(kind: .payment, record: row.value, feed: feed) }.disabled(!canWrite || !row.active || row.sale < 0)
                        Button("Editar precio y empresario") { editor = CRMEditorRequest(kind: .price, record: CRMFields.showRecord(row.value), feed: feed) }.disabled(!canWrite || !row.active)
                    }
                } primaryAction: { ids in if let id = ids.first { openedShow = id } }
                .overlay { if rows.isEmpty { if feed.isNull && busy { ProgressView("Consultando shows…") } else { ContentUnavailableView(search.isEmpty ? "No hay shows en este filtro" : "Sin resultados", systemImage: "music.mic", description: Text("Cambia la búsqueda, el filtro o el mes para ver otras fechas.")) } } }
            Divider()
            HStack(spacing: 16) {
                Text("\(rows.count) shows").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let url = URL(string: feed["sheets"]["url"].text), url.scheme == "https", url.host == "docs.google.com" { Link("Hoja de abonos", destination: url).font(.caption) }
                Label(feed["sheets"]["ready"].flag ? "Sheets conectado" : "Sheets sin configurar", systemImage: feed["sheets"]["ready"].flag ? "checkmark.icloud" : "icloud.slash").font(.caption).foregroundStyle(.secondary)
                Button("Abrir show") { openedShow = selection }.disabled(selected == nil).accessibilityIdentifier("crm.openShow")
            }.padding(.horizontal, 20).padding(.vertical, 12)
        }
    }
    private func money(_ value: JSONValue) -> some View { Text(value.isNull ? "Sin precio" : CRMFields.money(value.number)).monospacedDigit() }
    private func restoreCached() { if let saved = crm.cached(["month": month]) { crm.feed = saved } }
    private func load(sync: Bool = false) async {
        guard !crm.denied else { return }
        guard !busy else { queuedReload=true;queuedSync = queuedSync || sync;return }
        busy = true
        defer {
            busy = false
            if queuedReload && !crm.denied {
                let sync=queuedSync;queuedReload=false;queuedSync=false
                Task { await load(sync:sync && !store.isOffline) }
            }
        }
        if feed.isNull { restoreCached() }
        do {
            if sync { lastSync = Date(); for offset in 0..<6 { let date = CalendarClock.calendar.date(byAdding: .month, value: offset, to: ReceiptParser.civilDate(month + "-01") ?? Date())!; _ = try await crm.command("syncCalendar", month: CalendarClock.month(date)) } }
            crm.feed = try await crm.read(["month": month]); error = nil
            if let selection, !rows.contains(where: { $0.id == selection }) { self.selection = nil }
        } catch { if error is CancellationError { queuedReload=true } else { self.error = store.reportReadFailure(error) } }
    }
    private func syncSheets() async { do { _ = try await crm.command("syncSheets"); await load() } catch { self.error = error.localizedDescription } }
}

private struct MacCRMSearch:ViewModifier {
    @Binding var text:String
    let enabled:Bool
    @ViewBuilder func body(content:Content)->some View {
        if enabled {content.searchable(text:$text,prompt:"Buscar show o empresario")}
        else {content}
    }
}
