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
        guard user.mediaOnly != true else { return false }
        return switch self {
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
    @State private var presentation = "cards"
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
                    VStack(alignment: .leading, spacing: 14) {
                        hero
                        HStack(spacing:6) {
                            sectionButton("Shows", symbol:"music.mic", value:"shows")
                            sectionButton("Semana", symbol:"calendar", value:"weekly")
                            sectionButton("Empresarios", symbol:"person.2", value:"contacts")
                            Spacer()
                            if busy { ProgressView().controlSize(.small).accessibilityLabel("Actualizando CRM") }
                            if store.isOffline { Label("Copia sin conexión",systemImage:"wifi.slash").font(.caption).foregroundStyle(.secondary) }
                        }.accessibilityIdentifier("crm.sections")
                        if let error { HStack { InlineError(message: error); Spacer(); Button("Reintentar") { Task { await load() } } } }
                    }.padding(.horizontal,24).padding(.top,22).padding(.bottom,14)
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
    private var allShows:[MacCRMRow] { MacCRMRow.visible(feed["shows"].elements,today:BoardingClock.today(),query:"",filter:.all) }
    private var hero:some View {
        HStack(alignment:.center,spacing:24) {
            VStack(alignment:.leading,spacing:10) {
                Text("JAC MUSIC  /  CRM").font(.system(size:10,weight:.bold)).tracking(2.2).foregroundStyle(JACTheme.highlight)
                Text("Shows y abonos").font(.system(size:28,weight:.semibold,design:.rounded)).foregroundStyle(.white)
                HStack(spacing:16) {
                    heroCount("\(allShows.count) shows",symbol:"music.mic")
                    heroCount("\(allShows.filter{$0.balance>0}.count) con saldo",symbol:"circle.lefthalf.filled")
                    heroCount("\(allShows.filter{$0.sale<0}.count) sin precio",symbol:"pencil.line")
                }.foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength:0)
            Image(systemName:"waveform").font(.system(size:62,weight:.ultraLight)).foregroundStyle(JACTheme.highlight.opacity(0.5)).accessibilityHidden(true)
        }.padding(.horizontal,24).padding(.vertical,21).frame(maxWidth:.infinity,alignment:.leading)
            .background(LinearGradient(colors:[JACTheme.navy,Color(red:0.02,green:0.30,blue:0.47)],startPoint:.leading,endPoint:.trailing),in:RoundedRectangle(cornerRadius:20))
            .overlay(RoundedRectangle(cornerRadius:20).stroke(.white.opacity(0.12),lineWidth:1))
            .accessibilityIdentifier("crm.hero")
    }
    private func heroCount(_ text:String,symbol:String)->some View {Label(text,systemImage:symbol).font(.system(size:12,weight:.medium))}
    private func sectionButton(_ title:String,symbol:String,value:String)->some View {
        Button {section=value} label: {
            Label(title,systemImage:symbol).font(.system(size:13,weight:.semibold)).padding(.horizontal,14).padding(.vertical,10)
                .foregroundStyle(section==value ? JACTheme.action:Color.secondary)
                .background(section==value ? JACTheme.action.opacity(0.1):Color.clear,in:RoundedRectangle(cornerRadius:10))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("crm.section."+value).accessibilityAddTraits(section==value ? .isSelected:[])
    }
    private var shows:some View {
        VStack(spacing:0) {
            HStack(spacing:12) {
                Picker("Mostrar",selection:$filter){ForEach(MacCRMFilter.allCases,id:\.self){Text($0.rawValue).tag($0)}}.labelsHidden().frame(width:140).accessibilityIdentifier("crm.filter")
                Menu {
                    Button("Fecha del show"){sort=[KeyPathComparator(\MacCRMRow.day)]}
                    Button("Nombre del show"){sort=[KeyPathComparator(\MacCRMRow.title)]}
                    Button("Empresario"){sort=[KeyPathComparator(\MacCRMRow.entrepreneur)]}
                    Button("Mayor venta"){sort=[KeyPathComparator(\MacCRMRow.sale,order:.reverse)]}
                    Button("Más abonos"){sort=[KeyPathComparator(\MacCRMRow.paid,order:.reverse)]}
                    Button("Mayor saldo"){sort=[KeyPathComparator(\MacCRMRow.balance,order:.reverse)]}
                } label:{Image(systemName:"arrow.up.arrow.down")}.help("Ordenar shows").fixedSize()
                Spacer(minLength:8)
                MacDatePicker("Desde el mes",selection:Binding(get:{ReceiptParser.civilDate(month+"-01") ?? Date()},set:{month=CalendarClock.month($0);selection=nil;Task{await load()}}),in:(ReceiptParser.civilDate(CalendarClock.month(Date())+"-01") ?? Date())...Date.distantFuture,displayedComponents:.date,monthOnly:true)
                    .fixedSize().disabled(busy).accessibilityIdentifier("crm.month")
                HStack(spacing:2) {
                    layoutButton("cards",symbol:"rectangle.grid.1x2",title:"Vista de fichas")
                    layoutButton("table",symbol:"tablecells",title:"Vista de tabla")
                }.padding(3).background(JACTheme.card,in:RoundedRectangle(cornerRadius:9))
            }.padding(.horizontal,24).padding(.bottom,14)
            if presentation == "table" {table.padding(.horizontal,24).padding(.bottom,16)}
            else {
                ScrollView {
                    LazyVStack(spacing:12) {
                        if rows.isEmpty {emptyShows.padding(.vertical,36)}
                        ForEach(rows){row in
                            Button {selection=row.id;openedShow=row.id} label:{MacCRMShowCard(row:row)}
                                .buttonStyle(.plain).accessibilityIdentifier("crm.card."+row.id)
                                .contextMenu {showMenu(row)}
                        }
                    }.padding(.horizontal,24).padding(.top,2).padding(.bottom,22).frame(maxWidth:1240).frame(maxWidth:.infinity)
                }.accessibilityIdentifier("crm.cards")
            }
            HStack(spacing:14) {
                Text("\(rows.count) \(rows.count == 1 ? "show":"shows")").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let url=URL(string:feed["sheets"]["url"].text),url.scheme=="https",url.host=="docs.google.com" {Link("Hoja de abonos",destination:url).font(.caption)}
                Label(feed["sheets"]["ready"].flag ? "Sheets conectado":"Sheets sin configurar",systemImage:feed["sheets"]["ready"].flag ? "checkmark.icloud":"icloud.slash").font(.caption).foregroundStyle(.secondary)
                if presentation == "table" {Button("Abrir show"){openedShow=selection}.disabled(selected==nil).accessibilityIdentifier("crm.openShow")}
            }.padding(.horizontal,24).padding(.vertical,12)
        }
    }
    private func layoutButton(_ value:String,symbol:String,title:String)->some View {
        Button {presentation=value} label:{Image(systemName:symbol).font(.system(size:13,weight:.medium)).frame(width:28,height:25)
            .foregroundStyle(presentation==value ? JACTheme.action:Color.secondary)
            .background(presentation==value ? JACTheme.action.opacity(0.1):Color.clear,in:RoundedRectangle(cornerRadius:6)).contentShape(Rectangle())}
            .buttonStyle(.plain).help(title).accessibilityLabel(title).accessibilityIdentifier("crm.layout."+value)
    }
    private var table:some View {
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
                .clipShape(RoundedRectangle(cornerRadius:14))
                .overlay(RoundedRectangle(cornerRadius:14).stroke(JACTheme.action.opacity(0.12),lineWidth:1))
    }
    @ViewBuilder private var emptyShows:some View {
        if feed.isNull && busy {ProgressView("Consultando shows…").frame(maxWidth:.infinity)}
        else {ContentUnavailableView(search.isEmpty ? "No hay shows en este filtro":"Sin resultados",systemImage:"music.mic",description:Text("Cambia la búsqueda, el filtro o el mes para ver otras fechas."))}
    }
    @ViewBuilder private func showMenu(_ row:MacCRMRow)->some View {
        Button("Abrir show"){openedShow=row.id}
        Button("Registrar abono"){editor=CRMEditorRequest(kind:.payment,record:row.value,feed:feed)}.disabled(!canWrite || !row.active || row.sale<0)
        Button("Editar precio y empresario"){editor=CRMEditorRequest(kind:.price,record:CRMFields.showRecord(row.value),feed:feed)}.disabled(!canWrite || !row.active)
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

private struct MacCRMShowCard:View {
    let row:MacCRMRow
    @State private var hovering=false
    var body:some View {
        ViewThatFits(in:.horizontal) {
            HStack(spacing:18) {dateBadge;identity.frame(minWidth:190,idealWidth:270,maxWidth:.infinity,alignment:.leading);metrics;arrow}
            VStack(alignment:.leading,spacing:18) {
                HStack(spacing:14){dateBadge;identity;Spacer(minLength:0);arrow}
                HStack{Spacer(minLength:0);metrics}
            }
        }.padding(18).frame(maxWidth:.infinity,alignment:.leading)
            .background(JACTheme.card,in:RoundedRectangle(cornerRadius:16))
            .overlay(RoundedRectangle(cornerRadius:16).stroke(hovering ? JACTheme.action.opacity(0.55):JACTheme.action.opacity(0.1),lineWidth:1))
            .shadow(color:JACTheme.navy.opacity(hovering ? 0.08:0.025),radius:hovering ? 9:4,x:0,y:2)
            .contentShape(RoundedRectangle(cornerRadius:16)).onHover{hovering=$0}
    }
    private var dateBadge:some View {
        VStack(spacing:3) {
            Text(datePart("MMM").uppercased()).font(.system(size:9,weight:.bold)).tracking(1)
            Text(datePart("d")).font(.system(size:25,weight:.semibold,design:.rounded))
            Text(datePart("EEE").capitalized).font(.system(size:10,weight:.medium))
        }.foregroundStyle(JACTheme.action).frame(width:54,height:76)
            .background(JACTheme.action.opacity(0.09),in:RoundedRectangle(cornerRadius:12))
            .accessibilityLabel(row.displayDate)
    }
    private var identity:some View {
        VStack(alignment:.leading,spacing:8) {
            Text(row.title).font(.system(size:15,weight:.semibold)).foregroundStyle(JACTheme.ink).lineLimit(2).fixedSize(horizontal:false,vertical:true)
            Label(row.entrepreneur.isEmpty ? "Empresario por registrar":row.entrepreneur,systemImage:"person.crop.circle").font(.system(size:12)).foregroundStyle(.secondary).lineLimit(1)
            if row.value["promotional"].flag {JACBadge(title:"Promocional",tone:.violet)}
            else if row.sale<0 {JACBadge(title:"Por cotizar",tone:.amber)}
            else if row.balance<=0 {JACBadge(title:"Al día",tone:.teal)}
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private var metrics:some View {
        HStack(spacing:16) {
            metric("Venta",value:row.value["sale"],highlight:false)
            metric("Abonos",value:row.value["paid"],highlight:false)
            Rectangle().fill(JACTheme.action.opacity(0.12)).frame(width:1,height:38)
            metric("Saldo",value:row.value["balance"],highlight:true)
        }.fixedSize(horizontal:true,vertical:false)
    }
    private func metric(_ title:String,value:JSONValue,highlight:Bool)->some View {
        VStack(alignment:.trailing,spacing:7) {
            Text(title).font(.system(size:11,weight:.medium)).foregroundStyle(.secondary)
            Text(value.isNull ? "Sin precio":CRMFields.money(value.number)).font(.system(size:highlight ? 16:13,weight:highlight ? .semibold:.medium,design:.rounded))
                .monospacedDigit().foregroundStyle(highlight ? JACTheme.action:JACTheme.ink)
        }.frame(minWidth:highlight ? 122:103,alignment:.trailing)
    }
    private var arrow:some View {Image(systemName:"chevron.right").font(.system(size:11,weight:.semibold)).foregroundStyle(JACTheme.action.opacity(hovering ? 1:0.45))}
    private func datePart(_ pattern:String)->String {
        guard let date=ReceiptParser.civilDate(row.day) else{return row.day}
        let f=DateFormatter();f.locale=Locale(identifier:"es_CO");f.timeZone=CalendarClock.calendar.timeZone;f.dateFormat=pattern;return f.string(from:date)
    }
}

private struct MacCRMSearch:ViewModifier {
    @Binding var text:String
    let enabled:Bool
    @ViewBuilder func body(content:Content)->some View {
        if enabled {content.searchable(text:$text,prompt:"Buscar show o empresario")}
        else {content}
    }
}
