import SwiftUI

enum PreparationKind: String, Decodable {
    case contract, payments, photos

    var module: String {
        switch self {
        case .contract: "Contratos"
        case .payments: "Conciliación"
        case .photos: "Fotografía"
        }
    }
    var symbol: String {
        switch self {
        case .contract: "doc.text"
        case .payments: "creditcard"
        case .photos: "folder"
        }
    }
}

enum PreparationStatus: String, Decodable {
    case pending, done, waiting, na

    var title: String {
        switch self {
        case .pending: "Pendiente"
        case .done: "Completado"
        case .waiting: "Por vincular"
        case .na: "No aplica"
        }
    }
    var isOpen: Bool { self == .pending || self == .waiting }
}

struct PreparationFolder: Decodable, Identifiable {
    let id, name, parentName: String
    var path: String { parentName.isEmpty ? name : parentName + " / " + name }
}
struct PreparationMember: Decodable, Identifiable {
    let id, name, username: String
    let crm, media: Bool
}
struct PreparationFeed: Decodable {
    struct Week: Decodable { let from, to, today: String }
    let week: Week
    let tasks: [PreparationTask]
    let members: [PreparationMember]
}
struct PreparationTask: Decodable, Identifiable {
    let id, showId, showTitle, showDate, municipality: String
    let kind: PreparationKind
    let status: PreparationStatus
    let assigneeId, assigneeName, dueDate, effectiveDueDate: String
    let version: Int
    let folderId: String
    let folder: PreparationFolder?
    let pendingPayments, linkedPayments: Int
    let canComplete: Bool
    let href: String?

    var title: String {
        switch kind {
        case .contract: "Confirmar firma del contrato"
        case .payments: pendingPayments == 1 ? "Identificar un abono" : "Identificar abonos"
        case .photos: "Confirmar entrega de fotos"
        }
    }
    var note: String {
        switch kind {
        case .contract:
            if status == .done { return "Firma confirmada en la preparación del show." }
            if status == .na { return "La firma está marcada como no aplicable en la ficha del show." }
            return href == nil ? "Confirma la firma cuando tengas el contrato firmado." : "El contrato está guardado en el CRM. Confirma cuando esté firmado."
        case .payments:
            if pendingPayments == 1 { return "Hay un abono pendiente de identificar para este show." }
            if pendingPayments > 1 { return "\(pendingPayments) abonos pendientes de identificar para este show." }
            return linkedPayments == 0 ? "Aún no hay abonos vinculados a este show." : "Todos los abonos vinculados están identificados."
        case .photos:
            if status == .done { return "Entrega confirmada." }
            return folder == nil ? "Vincula la carpeta de fotos del show." : "Confirma cuando hayas entregado las fotos del show."
        }
    }
    var confirmation: String { status == .done ? "Reabrir tarea" : kind == .contract ? "Confirmar firma" : "Confirmar entrega" }
}

private func prepDate(_ value: String) -> String {
    guard let day = CalendarClock.date(value) else { return value }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "es_CO")
    formatter.timeZone = CalendarClock.calendar.timeZone
    formatter.dateFormat = "d MMM"
    return formatter.string(from: day)
}

struct PreparationView: View {
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.scenePhase) private var phase
    @Environment(\.isWorkspaceActive) private var active
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var day = CalendarClock.day(Date())
    @State private var feed: PreparationFeed?
    @State private var selected: String?
    @State private var setup: PreparationTask?
    @State private var completed = false
    @State private var busy = false
    @State private var loading = false
    @State private var error: String?
    @State private var notice: String?
    @State private var folder: MediaNotificationDestination?
    @State private var request = UUID()
    let weekly: Bool

    private var tasks: [PreparationTask] { feed?.tasks ?? [] }
    private var today: String { feed?.week.today ?? CalendarClock.day(Date()) }
    private var pending: Int { tasks.filter { $0.status.isOpen }.count }
    private var visible: Bool { active && phase == .active && !store.isOffline }
    private var readID: String { "\(store.overview?.user.id ?? "")|\(day)|\(visible)" }
    private var showIDs: [String] {
        tasks.reduce(into: []) { ids, task in
            if ids.last != task.showId { ids.append(task.showId) }
        }
    }

    var body: some View {
        Group {
            if store.isOffline {
                ContentUnavailableView("Conéctate para ver tus tareas", systemImage:"wifi.slash")
            } else {
                GeometryReader { geometry in
                    ScrollViewReader { scroll in
                        ScrollView {
                            content(wide: geometry.size.width >= 780 && !typeSize.isAccessibilitySize, scroll: scroll)
                                .padding(.horizontal, geometry.size.width >= 780 ? 24 : 16)
                                .padding(.vertical, 16)
                                .frame(maxWidth: 1240)
                                .frame(maxWidth: .infinity)
                        }
                        .refreshable { if !busy && setup == nil { await load() } }
                    }
                }
            }
        }
        .background(JACTheme.canvas)
        .task(id: readID) {
            guard visible else { return }
            await load()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(15))
                    if setup == nil && !busy { await load() }
                } catch { break }
            }
        }
        .onChange(of: store.overview?.user.id) { _, _ in
            feed = nil; setup = nil; folder = nil; error = nil; notice = nil
        }
        .sheet(item: $setup) { task in
            PreparationSetup(task: task, members: feed?.members ?? []) { fields in
                await save(task, fields: fields)
            }
        }
        .sheet(item: $folder) { destination in
            if let user = store.overview?.user, user.canReadMedia,
               destination.stamp == (try? store.client.mediaAccessStamp()) {
                NavigationStack {
                    MediaGalleryView(user:user,notificationFolder:destination.feed)
                        .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Listo") { folder = nil } } }
                }
            }
        }
    }

    private func content(wide: Bool, scroll: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let error { InlineError(message:error) }
            if let notice {
                Label(notice, systemImage:"checkmark.circle").font(.subheadline).foregroundStyle(JACTheme.action)
                    .accessibilityIdentifier("preparation.notice")
            }
            if feed == nil && loading { ProgressView("Consultando tareas…").padding(.vertical, 20) }
            if feed != nil {
                if weekly { board(wide:wide,scroll:scroll) }
                else { personal }
            }
        }
        .frame(maxWidth:.infinity,alignment:.leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !weekly, let user = store.overview?.user { Text(user.displayName).font(.subheadline).foregroundStyle(JACTheme.muted) }
            Text(weekly ? "Preparación semanal" : "Mis pendientes").font(.system(.title,design:.rounded,weight:.bold))
                .foregroundStyle(JACTheme.ink).accessibilityAddTraits(.isHeader)
            if let week=feed?.week {
                Label(prepDate(week.from) + " – " + prepDate(week.to),systemImage:"calendar")
                    .font(.subheadline).foregroundStyle(JACTheme.muted)
            }
            ViewThatFits(in:.horizontal) {
                HStack(spacing:10) { count; Spacer(minLength:0); weekControls }
                VStack(alignment:.leading,spacing:8) { count; weekControls }
            }
        }
    }
    @ViewBuilder private var count: some View {
        if feed != nil {
            Text(pending == 1 ? "1 pendiente" : "\(pending) pendientes")
                .font(.subheadline.weight(.semibold)).foregroundStyle(JACTheme.ink)
                .padding(.horizontal,11).padding(.vertical,7)
                .background(JACTheme.action.opacity(0.12),in:RoundedRectangle(cornerRadius:9))
        }
    }
    private var weekControls: some View {
        HStack(spacing:4) {
            Button { move(-7) } label: { Image(systemName:"chevron.left").frame(minWidth:36,minHeight:34) }.accessibilityLabel("Semana anterior")
            Button("Hoy") { changeDay(today) }.disabled(day == today)
            Button { move(7) } label: { Image(systemName:"chevron.right").frame(minWidth:36,minHeight:34) }.accessibilityLabel("Semana siguiente")
            Button { Task { await load() } } label: { Image(systemName:"arrow.clockwise").frame(minWidth:36,minHeight:34) }.accessibilityLabel("Actualizar tareas")
        }.buttonStyle(.borderless).tint(JACTheme.action).disabled(busy || loading || setup != nil)
    }

    @ViewBuilder private func board(wide: Bool, scroll: ScrollViewProxy) -> some View {
        if tasks.isEmpty {
            Text("No hay shows ni tareas programadas para esta semana.").foregroundStyle(JACTheme.muted).prepCard()
        } else {
            let layout = wide ? AnyLayout(HStackLayout(alignment:.top,spacing:16)) : AnyLayout(VStackLayout(alignment:.leading,spacing:14))
            layout {
                VStack(alignment:.leading,spacing:12) {
                    ForEach(showIDs,id:\.self) { id in
                        let group=tasks.filter { $0.showId == id }
                        if let show=group.first {
                            VStack(spacing:0) {
                                VStack(alignment:.leading,spacing:3) {
                                    Text(show.showTitle).font(.headline).foregroundStyle(JACTheme.ink)
                                    Text([show.municipality,prepDate(show.showDate)].filter { !$0.isEmpty }.joined(separator:" · "))
                                        .font(.caption).foregroundStyle(JACTheme.muted)
                                }.frame(maxWidth:.infinity,alignment:.leading).padding(14)
                                ForEach(group) { task in
                                    Divider().overlay(JACTheme.border)
                                    queueRow(task) {
                                        selected=task.id
                                        if !wide { withAnimation { scroll.scrollTo("preparation.detail",anchor:.top) } }
                                    }
                                }
                            }.prepCard(padding:0)
                        }
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
                if let task=tasks.first(where:{ $0.id == selected }) {
                    detail(task).frame(maxWidth:.infinity,alignment:.leading).id("preparation.detail")
                }
            }
        }
    }

    private var personal: some View {
        VStack(alignment:.leading,spacing:12) {
            if tasks.contains(where:{ !$0.status.isOpen }) {
                Toggle("Mostrar tareas completadas",isOn:$completed).font(.subheadline)
            }
            let personalTasks=tasks.filter { completed || $0.status.isOpen }.sorted { $0.effectiveDueDate < $1.effectiveDueDate }
            if personalTasks.isEmpty {
                Text("Estás al día. Aquí aparecerán las tareas que te asignen.").foregroundStyle(JACTheme.muted).prepCard()
            }
            ForEach(personalTasks) { task in detail(task) }
        }.frame(maxWidth:650,alignment:.leading)
    }

    private func queueRow(_ task: PreparationTask, select: @escaping () -> Void) -> some View {
        Button(action:select) {
            HStack(spacing:10) {
                prepIcon(task.kind.symbol)
                VStack(alignment:.leading,spacing:3) {
                    Text(task.title).font(.subheadline.weight(.semibold)).foregroundStyle(JACTheme.ink)
                    Text(responsible(task) + " · " + deadline(task)).font(.caption).foregroundStyle(JACTheme.muted)
                }
                Spacer(minLength:0)
                PreparationStatusBadge(status:task.status)
            }.padding(.vertical,10).padding(.horizontal,14)
                .background(selected == task.id ? JACTheme.action.opacity(0.12) : .clear)
                .overlay(alignment:.leading) {
                    if selected == task.id { Rectangle().fill(JACTheme.action).frame(width:4) }
                }
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected == task.id ? .isSelected:[]).disabled(busy)
    }
    private func detail(_ task: PreparationTask) -> some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text(task.kind.module).font(.subheadline.weight(.semibold)).foregroundStyle(JACTheme.action)
                Spacer(minLength:0)
                PreparationStatusBadge(status:task.status)
            }
            VStack(alignment:.leading,spacing:5) {
                Text(task.title).font(.system(.title2,design:.rounded,weight:.bold)).foregroundStyle(JACTheme.ink)
                Text(task.showTitle + " · " + prepDate(task.showDate)).font(.subheadline).foregroundStyle(JACTheme.muted)
            }
            if let item=task.folder {
                Button { Task { await openFolder(item) } } label: {
                    HStack(spacing:10) {
                        prepIcon("folder")
                        VStack(alignment:.leading,spacing:3) {
                            Text(item.name).font(.subheadline.weight(.semibold))
                            Text(item.parentName.isEmpty ? "Carpeta vinculada" : item.parentName).font(.caption).foregroundStyle(JACTheme.muted)
                        }
                        Spacer(minLength:0)
                        Image(systemName:"chevron.right").font(.caption).foregroundStyle(JACTheme.action)
                    }.foregroundStyle(JACTheme.ink).padding(10)
                        .background(JACTheme.action.opacity(0.10),in:RoundedRectangle(cornerRadius:10))
                }.buttonStyle(.plain).disabled(busy).accessibilityHint("Abrir carpeta de Fotografía")
            }
            Text(task.note).font(.subheadline).foregroundStyle(JACTheme.muted)
            Divider()
            ViewThatFits(in:.horizontal) {
                HStack(alignment:.top,spacing:24) { facts(task) }
                VStack(alignment:.leading,spacing:8) { facts(task) }
            }
            ViewThatFits(in:.horizontal) {
                HStack(spacing:8) { actions(task) }
                VStack(alignment:.leading,spacing:8) { actions(task) }
            }.disabled(busy || loading)
        }.prepCard()
    }
    @ViewBuilder private func facts(_ task: PreparationTask) -> some View {
        if weekly { fact("Responsable",responsible(task)) }
        fact(task.status.isOpen && task.effectiveDueDate < today ? "Venció" : "Fecha límite", deadline(task))
    }
    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment:.leading,spacing:4) {
            Text(title).font(.caption).foregroundStyle(JACTheme.muted)
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(JACTheme.ink)
        }
    }
    @ViewBuilder private func actions(_ task: PreparationTask) -> some View {
        if task.canComplete {
            Button(task.confirmation) {
                Task { _ = await save(task,fields:["action":.string("complete"),"done":.bool(task.status != .done)]) }
            }.buttonStyle(.borderedProminent).tint(JACTheme.primary).controlSize(.large)
        }
        if task.kind != .photos, let path=task.href, path.hasPrefix("/crm?") || path.hasPrefix("/crm/reconciliation?"),
           let url=URL(string:path,relativeTo:store.client.baseURL)?.absoluteURL {
            Link(destination:url) { Label(task.kind == .contract ? "Abrir contratos" : "Abrir en Conciliación",systemImage:"arrow.up.right") }
                .buttonStyle(.bordered).tint(JACTheme.action).controlSize(.large)
        }
        if weekly {
            Button(task.version == 0 ? "Asignar tarea" : "Editar asignación") { setup=task }
                .buttonStyle(.bordered).tint(JACTheme.action).controlSize(.large)
        }
    }
    private func responsible(_ task: PreparationTask) -> String { task.assigneeName.isEmpty ? "Sin asignar" : task.assigneeName }
    private func deadline(_ task: PreparationTask) -> String {
        if task.effectiveDueDate == today { return "Hoy" }
        if let date=CalendarClock.date(today), let tomorrow=CalendarClock.calendar.date(byAdding:.day,value:1,to:date),
           task.effectiveDueDate == CalendarClock.day(tomorrow) { return "Mañana" }
        return prepDate(task.effectiveDueDate)
    }
    private func move(_ offset: Int) {
        guard let date=CalendarClock.date(day), let next=CalendarClock.calendar.date(byAdding:.day,value:offset,to:date) else { return }
        changeDay(CalendarClock.day(next))
    }
    private func changeDay(_ value: String) { day=value; feed=nil; notice=nil; error=nil }

    private func load(keepError: Bool = false) async {
        guard let owner=store.overview?.user.id, !store.isOffline else { return }
        let id=UUID(), requestedDay=day
        request=id; loading=true
        defer { if request == id { loading=false } }
        do {
            let value=try await store.client.preparation(weekly:weekly,day:requestedDay)
            guard !Task.isCancelled, request == id, day == requestedDay, store.overview?.user.id == owner else { return }
            feed=value
            if !value.tasks.contains(where:{ $0.id == selected }) { selected=(value.tasks.first(where:{ $0.status.isOpen }) ?? value.tasks.first)?.id }
            if !keepError { error=nil }
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled, request == id, store.overview?.user.id == owner else { return }
            report(error)
        }
    }
    private func save(_ task: PreparationTask,fields: [String:JSONValue]) async -> Bool {
        guard !busy, !store.isOffline, let owner=store.overview?.user.id else { return false }
        busy=true; request=UUID(); loading=false; error=nil; notice=nil
        defer { busy=false }
        do {
            try await store.client.updatePreparation(task,fields:fields)
            guard store.overview?.user.id == owner else { return false }
            setup=nil; notice="Tarea actualizada."
            await load()
            return true
        } catch {
            guard store.overview?.user.id == owner else { return false }
            report(error)
            if setup == nil { await load(keepError:true) }
            return false
        }
    }
    private func openFolder(_ item: PreparationFolder) async {
        guard !busy, !store.isOffline, store.overview?.user.canReadMedia == true else { return }
        busy=true
        defer { busy=false }
        do {
            guard let stamp=try store.client.mediaAccessStamp() else { throw APIError.unauthorized }
            let value=try await store.client.media(folder:item.id,forceNetwork:true)
            guard stamp == (try store.client.mediaAccessStamp()), store.overview?.user.canReadMedia == true else { throw CancellationError() }
            guard value.connected, value.canRead, value.folder?.id == item.id else { throw APIError.message("La carpeta vinculada ya no está disponible.") }
            folder=MediaNotificationDestination(id:UUID(),stamp:stamp,feed:value)
        } catch is CancellationError {
        } catch { report(error) }
    }
    private func report(_ failure: Error) {
        if let api=failure as? APIError {
            switch api {
            case .unauthorized,.forbidden: feed=nil; setup=nil; folder=nil
            default: break
            }
        }
        error=failure.localizedDescription
    }
}

private func prepIcon(_ name: String) -> some View {
    Image(systemName:name).font(.subheadline.weight(.semibold)).foregroundStyle(JACTheme.action)
        .frame(width:36,height:36).background(JACTheme.action.opacity(0.11),in:RoundedRectangle(cornerRadius:9))
        .accessibilityHidden(true)
}
private extension View {
    func prepCard(padding: CGFloat = 16) -> some View {
        self.padding(padding).frame(maxWidth:.infinity,alignment:.leading)
            .background(JACTheme.card).clipShape(RoundedRectangle(cornerRadius:15))
            .overlay(RoundedRectangle(cornerRadius:15).strokeBorder(JACTheme.border,lineWidth:1).allowsHitTesting(false))
    }
}
private struct PreparationStatusBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let status: PreparationStatus
    private var tint: Color {
        switch status {
        case .done: colorScheme == .dark ? Color(red:0.66,green:0.89,blue:0.74) : Color(red:0.13,green:0.38,blue:0.24)
        case .pending: colorScheme == .dark ? Color(red:1,green:0.88,blue:0.65) : Color(red:0.47,green:0.32,blue:0.05)
        case .waiting,.na: JACTheme.muted
        }
    }
    var body: some View {
        Text(status.title).font(.caption.weight(.semibold)).foregroundStyle(tint)
            .padding(.horizontal,8).padding(.vertical,5)
            .background(tint.opacity(colorScheme == .dark ? 0.22:0.13),in:RoundedRectangle(cornerRadius:7))
    }
}

private struct PreparationSetup: View {
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.dismiss) private var dismiss
    @State private var assignee: String
    @State private var folderID: String
    @State private var due: Date
    @State private var useDue: Bool
    @State private var search = ""
    @State private var folders: [PreparationFolder] = []
    @State private var folderError: String?
    @State private var saveError = false
    @State private var busy = false
    let task: PreparationTask
    let members: [PreparationMember]
    let commit: ([String:JSONValue]) async -> Bool

    init(task: PreparationTask,members: [PreparationMember],commit: @escaping ([String:JSONValue]) async -> Bool) {
        self.task=task; self.members=members; self.commit=commit
        _assignee=State(initialValue:task.assigneeId); _folderID=State(initialValue:task.folderId)
        _due=State(initialValue:CalendarClock.date(task.effectiveDueDate) ?? Date())
        _useDue=State(initialValue:!task.dueDate.isEmpty)
    }
    private var eligible: [PreparationMember] { members.filter { task.kind == .photos ? $0.media : $0.crm } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(task.title).font(.headline)
                    Text(task.showTitle).foregroundStyle(JACTheme.muted)
                }
                Picker("Responsable",selection:$assignee) {
                    Text("Sin asignar").tag("")
                    if !assignee.isEmpty && !eligible.contains(where:{$0.id == assignee}) { Text("Cuenta sin acceso a esta área").tag(assignee) }
                    ForEach(eligible) { member in Text(member.name + " · " + member.username).tag(member.id) }
                }
                Toggle("Cambiar fecha límite",isOn:$useDue)
                if useDue { DatePicker("Fecha límite",selection:$due,displayedComponents:.date).environment(\.timeZone,CalendarClock.calendar.timeZone) }
                if task.kind == .photos {
                    Section("Carpeta de Fotografía") {
                        TextField("Buscar carpeta",text:$search)
                        Picker("Carpeta",selection:$folderID) {
                            Text("Sin carpeta vinculada").tag("")
                            if !folderID.isEmpty && !folders.contains(where:{$0.id == folderID}) {
                                Text(task.folder?.id == folderID ? task.folder?.path ?? folderID : "Carpeta no disponible").tag(folderID)
                            }
                            ForEach(folders) { item in Text(item.path).tag(item.id) }
                        }
                        if let folderError { InlineError(message:folderError) }
                    }
                }
                if saveError { InlineError(message:"No se confirmó el guardado. Revisa la tarea actualizada antes de reintentar.") }
            }.jacSurface().navigationTitle("Asignar tarea").jacInlineTitle().disabled(busy)
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("Cancelar") { dismiss() }.disabled(busy) }
                    ToolbarItem(placement:.confirmationAction) { Button(busy ? "Guardando…" : "Guardar") { Task { await save() } }.disabled(busy) }
                }
        }.task(id:search) {
            guard task.kind == .photos else { return }
            do {
                try await Task.sleep(for:.milliseconds(200))
                let result=try await store.client.preparationFolders(search:String(search.prefix(120)))
                try Task.checkCancellation()
                folders=result; folderError=nil
            } catch is CancellationError {
            } catch { folderError=error.localizedDescription }
        }
        #if os(macOS)
        .frame(minWidth:520,minHeight:380)
        #endif
    }
    private func save() async {
        guard !busy else { return }
        busy=true; saveError=false
        defer { busy=false }
        let saved=await commit(["action":.string("configure"),"assigneeId":.string(assignee),
                                "dueDate":.string(useDue ? CalendarClock.day(due):""),"folderId":.string(folderID)])
        if saved { dismiss() } else { saveError=true }
    }
}
