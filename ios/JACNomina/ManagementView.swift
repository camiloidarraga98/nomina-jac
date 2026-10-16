import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct ManagementView: View {
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.dynamicTypeSize) private var typeSize
    let user: PayrollUser
    @State private var destination: Destination?
    private enum Destination: String, Identifiable {
        case expenses, alerts, crm, archive, employees, mail, notifications, concepts, users
        var id:String { rawValue }
        var title:String {
            switch self {
            case .expenses:return "Gastos de viaje";case .alerts:return "Alertas";case .crm:return "CRM · Shows y abonos"
            case .archive:return "Archivo";case .employees:return "Equipo";case .mail:return "Correos y Gmail"
            case .notifications:return "Notificaciones";case .concepts:return "Conceptos y reglas";case .users:return "Usuarios y permisos"
            }
        }
        var subtitle:String {
            switch self {
            case .expenses:return "Facturas y reintegros";case .alerts:return "Avisos del equipo";case .crm:return "Ventas y preparación"
            case .archive:return "Quincenas cerradas";case .employees:return "Personas y tarifas";case .mail:return "Documentos y envíos"
            default:return ""
            }
        }
        var symbol:String {
            switch self {
            case .expenses:return "receipt";case .alerts:return "bell.badge";case .crm:return "briefcase"
            case .archive:return "archivebox";case .employees:return "person.2";case .mail:return "envelope"
            case .notifications:return "bell";case .concepts:return "list.bullet.rectangle";case .users:return "person.badge.key"
            }
        }
        var tone:JACTone {
            switch self { case .expenses,.employees:return .teal;case .alerts:return .amber;case .archive:return .violet;default:return .blue }
        }
        var identifier:String {
            switch self { case .alerts:return "notices.alerts";case .concepts,.users,.mail:return title;default:return "management."+rawValue }
        }
    }
    private var columnCount:Int { typeSize.isAccessibilitySize ? 1:2 }
    private var administration:[Destination] {
        var items:[Destination]=[]
        if user.isOwner { items.append(.crm) }
        if store.overview != nil { items += [.archive,.employees] }
        return items + [.mail]
    }
    private var preferences:[Destination] {
        var items:[Destination]=[.notifications]
        if user.itinerariesOnly != true { items.append(.concepts);if user.isOwner {items.append(.users)} }
        return items
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    if store.isOffline || store.error != nil || store.notice != nil || store.pending != nil {
                        VStack(alignment:.leading,spacing:12) { OperationStatusSection() }.padding(18).background(JACTheme.card,in:RoundedRectangle(cornerRadius:20))
                    }
                    JACFeatureBanner(eyebrow:"JAC · Tu equipo",title:"Todo en su lugar.",subtitle:"Herramientas para lo que pasa antes y después del show.",symbol:"slider.horizontal.3",tone:.violet)
                    Text("Tu día a día").font(.system(.headline,design:.rounded))
                    cards([.expenses,.alerts])
                    if user.itinerariesOnly != true {
                        Text("Administración").font(.system(.headline,design:.rounded))
                        cards(administration)
                    }
                    Text("Preferencias y acceso").font(.system(.headline,design:.rounded))
                    VStack(spacing:0) {
                        ForEach(preferences) { target in
                            Button { destination=target } label: {
                                HStack(spacing:14) { JACIcon(symbol:target.symbol,tone:target.tone);Text(target.title).font(.subheadline.weight(.medium)).foregroundStyle(JACTheme.ink);Spacer(minLength:0);Image(systemName:"chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }.padding(16).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel(target.title).accessibilityIdentifier(target.identifier)
                            if target != preferences.last { Divider().padding(.leading,76) }
                        }
                    }.background(JACTheme.card,in:RoundedRectangle(cornerRadius:22))
                }.padding(18)
            }.jacSurface().navigationTitle("Gestión").jacInlineTitle()
                .navigationDestination(item:$destination) { target in
                    switch target {
                    case .expenses:TravelExpensesView()
                    case .alerts:NoticesView(user:user,kind:"alert")
                    case .crm:if user.isOwner && user.itinerariesOnly != true {CRMHomeView(client:store.client)}
                    case .archive:if user.itinerariesOnly != true,let overview=store.overview {PeriodsView(overview:overview,archive:true,embedded:true)}
                    case .employees:if user.itinerariesOnly != true,let overview=store.overview {EmployeesView(overview:overview,embedded:true)}
                    case .mail:if user.itinerariesOnly != true {MailView(user:user)}
                    case .notifications:NotificationSettingsView()
                    case .concepts:if user.itinerariesOnly != true {ConceptsRulesView(user:user)}
                    case .users:if user.isOwner && user.itinerariesOnly != true {UsersView()}
                    }
                }
        }
    }
    // These few cards stay instantiated while scrolling, including on compact
    // iPhones. List/LazyVGrid recycling must not drop a previously visible access.
    private func cards(_ items:[Destination]) -> some View {
        VStack(spacing:12) {
            ForEach(0..<((items.count+columnCount-1)/columnCount),id:\.self) { row in
                HStack(alignment:.top,spacing:12) {
                    ForEach(Array(items.dropFirst(row*columnCount).prefix(columnCount))) { target in
                        Button { destination=target } label: { JACAccessCard(title:target.title,subtitle:target.subtitle,symbol:target.symbol,tone:target.tone) }
                            .buttonStyle(.plain).accessibilityLabel(target.title).accessibilityIdentifier(target.identifier)
                    }
                    if columnCount == 2 && row*columnCount+1 >= items.count { Color.clear.frame(maxWidth:.infinity) }
                }
            }
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
        }.jacSurface().navigationTitle("Conceptos y reglas").jacInlineTitle()
            .refreshable { try? await store.refresh() }.sheet(item: $editor) { PayrollEditorView(session: $0) }
    }
}

struct TravelExpense: Decodable, Identifiable {
    let id:String;let userId:String;let name:String;let concept:String;let amount:Double;let expenseDate:String;let note:String;let status:String;let version:Int;let reviewNote:String;let periodId:String;let employeeId:String;let attachments:[NoticeAttachment]
    var statusLabel:String { status == "approved" ? "Aprobado e incorporado a nómina" : status == "rejected" ? "Rechazado" : "Pendiente de revisión" }
}
struct TravelExpenseFeed: Decodable { let expenses:[TravelExpense];let nextCursor:String;let reviewer:Bool;let employees:[NoticeUser];let periods:[NoticeUser] }
struct TravelExpensesView: View {
    @EnvironmentObject private var store:PayrollStore
    @State private var feed:TravelExpenseFeed?
    @State private var records:[TravelExpense]=[]
    @State private var error:String?
    @State private var editor=false
    @State private var detail:TravelExpense?
    @State private var hasDraft=false
    @State private var deleteDraft=false
    var body:some View {
        List {
            if let error { InlineError(message:error) }
            Section { Text("Adjunta tus comprobantes. Un administrador revisará el gasto antes de incorporarlo como reintegro.").font(.footnote).foregroundStyle(.secondary)
                Button { editor=true } label: { Label(hasDraft ? "Continuar borrador" : "Registrar gasto",systemImage:hasDraft ? "square.and.pencil" : "plus.viewfinder").frame(maxWidth:.infinity) }.buttonStyle(JACPrimaryButtonStyle()).accessibilityIdentifier("expenses.create")
                if hasDraft { Button("Eliminar borrador",role:.destructive) { deleteDraft=true }.accessibilityIdentifier("expenses.deleteDraft") }
                if store.isOffline { Text("Puedes escanear y guardar un borrador en este \(JACDevice.name). El envío necesita conexión.").font(.footnote).foregroundStyle(.secondary) } }
            Section("Gastos de viaje") {
                ForEach(records) { item in Button { detail=item } label: { VStack(alignment:.leading,spacing:8) {
                    Text(item.concept).font(.headline);Text(PayrollFormat.money(item.amount));Text(item.name+" · "+item.expenseDate).font(.caption).foregroundStyle(.secondary);Text(item.statusLabel).font(.caption)
                }.padding(.vertical,6) }.buttonStyle(.plain).accessibilityIdentifier("expense."+item.id) }
                if records.isEmpty { Text(feed == nil ? "Consultando…" : "Todavía no hay gastos registrados.").foregroundStyle(.secondary) }
                if let cursor=feed?.nextCursor,!cursor.isEmpty { Button("Ver anteriores") { Task { await load(cursor) } } }
            }
        }.jacSurface().navigationTitle("Gastos de viaje").jacInlineTitle()
            .task { await load() }.refreshable { await load() }
            .onChange(of: store.cacheRevision) { _, _ in if let saved = store.client.cachedExpenses() { feed = saved; if store.isOffline || records.isEmpty { records = saved.expenses } } }
            .sheet(isPresented:$editor,onDismiss:{ Task { await load() } }) { ExpenseComposer { await load() } }
            .sheet(item:$detail,onDismiss:{ Task { await load() } }) { item in ExpenseDetailView(item:item,feed:feed) }
            .confirmationDialog("¿Eliminar el borrador de este \(JACDevice.name)?",isPresented:$deleteDraft,titleVisibility:.visible) {
                Button("Eliminar borrador",role:.destructive) { do { if let scope=try store.client.offlineScope() { try store.client.removeExpenseDraft(scope:scope);hasDraft=false } } catch { self.error=error.localizedDescription } }
            }
    }
    private func load(_ cursor:String = "") async {
        hasDraft = store.client.expenseDraft() != nil
        if cursor.isEmpty, let saved = store.client.cachedExpenses() { feed = saved; if store.isOffline || records.isEmpty { records = saved.expenses } }
        do { let result=try await store.client.expenses(cursor:cursor);feed=result;if cursor.isEmpty { records=store.isOffline ? store.client.cachedExpenses()?.expenses ?? result.expenses : result.expenses } else { records += result.expenses.filter { item in !records.contains { $0.id == item.id } } };error=nil } catch { self.error=store.reportReadFailure(error) } }
}
struct ExpenseDetailView:View {
    @EnvironmentObject private var store:PayrollStore
    @Environment(\.dismiss) private var dismiss
    let item:TravelExpense;let feed:TravelExpenseFeed?
    @State private var employeeID=""
    @State private var periodID=""
    @State private var reason=""
    @State private var error:String?
    @State private var busy=false
    @State private var document:ExportedDocument?
    @State private var previousDocument:ExportedDocument?
    var body:some View {
        NavigationStack {
            Form {
                Section { Text(item.concept).font(.headline);LabeledContent("Valor",value:PayrollFormat.money(item.amount));Text(item.name+" · "+item.expenseDate);Text(item.statusLabel) }
                if let error { InlineError(message:error) }
                if !item.note.isEmpty { Section("Nota") { Text(item.note) } }
                if !item.reviewNote.isEmpty { Section("Revisión") { Text(item.reviewNote) } }
                Section("Comprobantes") { ForEach(item.attachments) { file in Button { Task { await open(file) } } label: { Label(file.filename,systemImage:"doc.text") }.disabled(busy) } }
                if let feed,feed.reviewer,item.status == "pending" {
                    Section("Incorporar a nómina") {
                        Picker("Persona",selection:$employeeID) { Text("Selecciona una persona").tag("");ForEach(feed.employees) { Text($0.name).tag($0.id) } }.accessibilityIdentifier("expenses.employee")
                        Picker("Quincena abierta",selection:$periodID) { Text("Selecciona una quincena").tag("");ForEach(feed.periods) { Text($0.name).tag($0.id) } }.accessibilityIdentifier("expenses.period")
                        TextField("Comentario de revisión",text:$reason,axis:.vertical).lineLimit(3...6).accessibilityIdentifier("expenses.reason")
                        if store.hasPending { Text("Resuelve primero los cambios pendientes de nómina.").font(.footnote).foregroundStyle(.secondary) }
                        Button("Aprobar e incorporar") { Task { await review(true) } }.disabled(busy || !store.canWrite || employeeID.isEmpty || periodID.isEmpty).accessibilityIdentifier("expenses.approve")
                        Button("Rechazar con motivo",role:.destructive) { Task { await review(false) } }.disabled(busy || reason.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || store.isOffline).accessibilityIdentifier("expenses.reject")
                    }.disabled(busy)
                }
            }.jacSurface().navigationTitle("Gasto de viaje").jacInlineTitle()
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Listo") { dismiss() }.disabled(busy) } }
                .sheet(item:$document,onDismiss:{ if let previousDocument { TemporaryDocuments.remove(previousDocument);self.previousDocument=nil } }) { file in
                    NavigationStack { DocumentPreview(url:file.url).privacySensitive().ignoresSafeArea(edges:.bottom).navigationTitle("Comprobante").jacInlineTitle().toolbar { ToolbarItem(placement:.confirmationAction) { Button("Listo") { document=nil } } } }
                }
        }.interactiveDismissDisabled(busy)
    }
    private func open(_ file:NoticeAttachment) async { busy=true;defer { busy=false };do { let result=try await store.client.expenseFile(item,file:file);previousDocument=result;document=result } catch { self.error=store.reportReadFailure(error) } }
    private func review(_ approve:Bool) async {
        guard !busy else { return };busy=true;defer { busy=false }
        guard !approve || store.canWrite else { error="Resuelve primero los cambios pendientes de nómina.";return }
        guard reason.utf16.count <= 500 else { error="El comentario admite hasta 500 caracteres.";return }
        do { try await store.client.reviewExpense(item,approve:approve,reason:reason,employeeID:employeeID,periodID:periodID);if approve { try await store.refresh() };dismiss() } catch { self.error=error.localizedDescription;store.report(error) }
    }
}
struct ExpenseComposer:View {
    @EnvironmentObject private var store:PayrollStore
    @Environment(\.dismiss) private var dismiss
    let onSaved:() async -> Void
    @State private var draft=ExpenseDraft()
    @State private var files:[NoticeUpload]=[]
    @State private var scope:AgendaCacheScope?
    @State private var loaded=false
    @State private var finished=false
    @State private var busy=false
    @State private var importing=false
    @State private var scanner=false
    @State private var error:String?
    @State private var message:String?
    private var snapshot:ExpenseDraft {
        var value=draft;value.files=files.map { ExpenseDraft.File(filename:$0.filename,data:$0.data) };return value
    }
    private var selectedDate:Binding<Date> { Binding(get:{ ReceiptParser.civilDate(draft.date) ?? Date() },set:{ draft.date=BoardingClock.today($0) }) }
    var body:some View {
        NavigationStack {
            Form {
                if let error { InlineError(message:error) }
                Section {
                    Button { scanner=true } label: { Label("Escanear factura",systemImage:"text.viewfinder") }.accessibilityIdentifier("expenses.scan")
                    Text("Lee una foto y sugiere tipo, concepto, valor y fecha. Revisa los datos antes de enviar.").font(.footnote).foregroundStyle(.secondary)
                }.disabled(busy || importing || draft.attempted)
                Section("Gasto en pesos colombianos") {
                    Picker("Tipo de gasto",selection:$draft.kind) { Text("Sin clasificar").tag("");ForEach(ExpenseKind.allCases,id:\.rawValue) { Text($0.rawValue).tag($0.rawValue) } }.accessibilityIdentifier("expenses.kind")
                    TextField("Concepto",text:$draft.concept).accessibilityIdentifier("expenses.concept")
                    TextField("Valor en COP",text:$draft.amount).keyboardType(.numberPad).accessibilityIdentifier("expenses.amount")
                    JACDatePicker("Fecha",selection:selectedDate,displayedComponents:.date).environment(\.timeZone,CalendarClock.calendar.timeZone).accessibilityIdentifier("expenses.date")
                    TextField("Hora de factura (opcional)",text:Binding(get:{ draft.receiptTime ?? "" },set:{ draft.receiptTime=$0.isEmpty ? nil : $0 })).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("expenses.time")
                    TextField("Nota opcional",text:$draft.note,axis:.vertical).lineLimit(2...5)
                }.disabled(busy || draft.attempted)
                TravelAttachmentsPicker(files:$files,importing:$importing).disabled(busy || draft.attempted)
                if draft.attempted { Section { Text("Reintenta con los mismos datos para evitar duplicados. El borrador conserva la solicitud enviada.").font(.footnote) } }
                Section {
                    if let message { Text(message).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("expenses.draftStatus") }
                    if store.isOffline { Text("Sin conexión: puedes guardar el borrador. Envíalo cuando recuperes internet.").font(.footnote).foregroundStyle(.secondary) }
                    Button("Guardar borrador y cerrar") { if persist() { dismiss() } }.disabled(busy || importing || snapshot.isEmpty).accessibilityIdentifier("expenses.saveDraft")
                    Button(busy ? "Enviando…" : "Enviar a revisión") { Task { await save() } }.buttonStyle(JACPrimaryButtonStyle()).disabled(busy || importing || store.isOffline).accessibilityIdentifier("expenses.submit")
                }
            }.jacSurface().navigationTitle("Registrar gasto").jacInlineTitle()
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cerrar") { if persist() { dismiss() } }.disabled(busy || importing) } }
                .onAppear {
                    guard !loaded else { return };loaded=true
                    do { scope=try store.client.offlineScope();if let saved=store.client.expenseDraft() { draft=saved;files=saved.files.map { NoticeUpload(filename:$0.filename,data:$0.data) } } }
                    catch { self.error=error.localizedDescription }
                }
                .task(id:snapshot) {
                    guard loaded,!finished,!busy else { return }
                    do { try await Task.sleep(for:.milliseconds(650));try Task.checkCancellation();_ = persist() } catch {}
                }
                .sheet(isPresented:$scanner) { ReceiptScannerView { suggestion,file in
                    guard let scope,scope.id == (try? store.client.offlineScope())?.id else { error=APIError.unauthorized.localizedDescription;return }
                    guard files.count < 5,files.reduce(0,{ $0+$1.data.count })+file.data.count <= 10*1024*1024 else { error="Elige hasta 5 archivos que sumen como máximo 10 MB.";return }
                    files.append(file)
                    if let value=suggestion.kind { draft.kind=value.rawValue }
                    if let value=suggestion.concept { draft.concept=value }
                    if let value=suggestion.amount { draft.amount=String(value) }
                    if let value=suggestion.date { draft.date=value };draft.receiptTime=suggestion.time
                    message="Datos sugeridos: revisa tipo, concepto, valor y fecha antes de enviar.";error=nil
                } }
        }.interactiveDismissDisabled(busy || !snapshot.isEmpty)
    }
    @discardableResult private func persist() -> Bool {
        guard !finished,let scope else { error="No se pudo abrir el almacenamiento de la sesión.";return false }
        do { if snapshot.isEmpty { try store.client.removeExpenseDraft(scope:scope);message=nil } else { try store.client.saveExpenseDraft(snapshot,scope:scope);message="Borrador guardado en este \(JACDevice.name)." };return true }
        catch { self.error=error.localizedDescription;return false }
    }
    private func save() async {
        let value=snapshot
        guard value.receiptTime.map(ReceiptParser.validTime) ?? true else { error="Revisa la hora de factura: usa HH:mm o HH:mm:ss, por ejemplo 13:45.";return }
        guard !busy,!store.isOffline,let amount=Double(value.amount),amount > 0,amount <= 1e9,amount.rounded() == amount,
              value.concept.trimmingCharacters(in:.whitespacesAndNewlines).count >= 2,value.concept.utf16.count <= 120,
              value.submissionNote.utf16.count <= 500,!files.isEmpty else { error="Revisa concepto, valor en pesos, nota y comprobantes.";return }
        busy=true;draft.attempted=true;defer { busy=false }
        guard persist() else { return }
        do {
            try await store.client.submitExpense(id:draft.id,concept:draft.concept,amount:amount,date:draft.date,note:draft.submissionNote,files:files)
            if let scope { try store.client.removeExpenseDraft(scope:scope) };finished=true;dismiss();await onSaved()
        } catch { self.error=error.localizedDescription;store.report(error) }
    }
}
struct ItineraryUpdateView:View {
    @EnvironmentObject private var store:PayrollStore
    @Environment(\.dismiss) private var dismiss
    let item:JACNotice;let onSaved:() async -> Void
    @State private var requestID=UUID().uuidString.lowercased()
    @State private var title=""
    @State private var message=""
    @State private var summary=""
    @State private var files:[NoticeUpload]=[]
    @State private var attempted=false
    @State private var busy=false
    @State private var importing=false
    @State private var error:String?
    var body:some View {
        NavigationStack {
            Form {
                if let error { InlineError(message:error) }
                Section("Nueva versión") { TextField("Título",text:$title);TextField("Mensaje",text:$message,axis:.vertical);TextField("Qué cambió",text:$summary,axis:.vertical).lineLimit(3...6).accessibilityIdentifier("itinerary.update.summary");Text("Adjunta la versión completa. Sustituirá los archivos anteriores y requerirá una nueva confirmación de recepción.").font(.footnote).foregroundStyle(.secondary) }.disabled(busy || attempted)
                TravelAttachmentsPicker(files:$files,importing:$importing).disabled(busy || attempted)
                if attempted && error != nil { Text("Reintenta con los mismos datos. Si el itinerario cambió, vuelve a abrir su versión actual.").font(.footnote) }
                Section { Button(busy ? "Guardando…" : "Actualizar y notificar") { Task { await save() } }.buttonStyle(JACPrimaryButtonStyle()).disabled(busy || importing || store.isOffline).accessibilityIdentifier("itinerary.update.save") }
            }.jacSurface().navigationTitle("Actualizar itinerario").jacInlineTitle().toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancelar") { dismiss() }.disabled(busy) } }
                .onAppear { if !attempted { title=item.title;message=item.body } }
        }.interactiveDismissDisabled(busy)
    }
    private func save() async {
        guard !busy else { return };guard !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,title.utf16.count <= 120,message.utf16.count <= 2000,summary.trimmingCharacters(in:.whitespacesAndNewlines).count >= 3,summary.utf16.count <= 500,!files.isEmpty else { error="Revisa título, cambios y adjuntos.";return }
        busy=true;attempted=true;defer { busy=false }
        do { try await store.client.updateItinerary(item,requestID:requestID,title:title,body:message,summary:summary,files:files);dismiss();await onSaved() } catch { self.error=error.localizedDescription;store.report(error) }
    }
}
struct TravelAttachmentsPicker:View {
    @Environment(\.isEnabled) private var enabled
    @EnvironmentObject private var store:PayrollStore
    @Binding var files:[NoticeUpload]
    @Binding var importing:Bool
    @State private var picking=false
    @State private var camera=false
    @State private var photos:[PhotosPickerItem]=[]
    @State private var error:String?
    var body:some View {
        Section("Comprobantes y adjuntos") {
            if let error { InlineError(message:error) }
            Button("Elegir PDF o imágenes de Archivos") { picking=true }
            PhotosPicker(selection:$photos,maxSelectionCount:5,matching:.images) { Label("Elegir fotos",systemImage:"photo") }
            if JACCameraAvailable { Button("Fotografiar comprobante") { camera=true } }
            ForEach(files) { file in HStack { Text(file.filename);Spacer();Button(role:.destructive) { files.removeAll { $0.id == file.id } } label: { Image(systemName:"xmark.circle") }.accessibilityLabel("Quitar "+file.filename) } }
            Text("De 1 a 5 archivos PDF, JPG o PNG. 10 MB en total.").font(.footnote).foregroundStyle(.secondary)
            #if DEBUG
            if store.client.baseURL.host?.hasSuffix(".invalid") == true { Button("Adjuntar comprobante ficticio") { add([NoticeUpload(filename:"Comprobante ficticio.pdf",data:JACPlatform.fixturePDF())]) }.accessibilityIdentifier("travel.fixture") }
            #endif
        }.disabled(importing)
            .fileImporter(isPresented:$picking,allowedContentTypes:[.pdf,.jpeg,.png],allowsMultipleSelection:true) { result in
                do { var incoming:[NoticeUpload]=[];for url in try result.get() { let access=url.startAccessingSecurityScopedResource();defer { if access { url.stopAccessingSecurityScopedResource() } };guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) <= 10*1024*1024 else { throw APIError.message("El archivo supera los 10 MB.") };let data=try Data(contentsOf:url);_ = try NoticeUpload.mime(data);incoming.append(NoticeUpload(filename:url.lastPathComponent,data:data)) };add(incoming) } catch { if (error as? CocoaError)?.code != .userCancelled { self.error=error.localizedDescription } }
            }
            .jacFileDrop(enabled:enabled && !importing) {urls in do{add(try NoticeUpload.readLocalFiles(urls))}catch{self.error=error.localizedDescription}}
            .onChange(of:photos) { _,selected in Task { await readPhotos(selected) } }
            .sheet(isPresented:$camera) { TravelReceiptCamera { image in camera=false;if let image,let bytes=image.jpegData(compressionQuality:0.85) { add([NoticeUpload(filename:"Comprobante.jpg",data:bytes)]) } } }
    }
    private func add(_ incoming:[NoticeUpload]) { guard files.count+incoming.count <= 5,(files+incoming).reduce(0, { $0+$1.data.count }) <= 10*1024*1024 else { error="Elige hasta 5 archivos que sumen como máximo 10 MB.";return };files += incoming;error=nil }
    private func readPhotos(_ selected:[PhotosPickerItem]) async {
        guard !selected.isEmpty else { return };importing=true;defer { importing=false;photos=[] }
        do { var incoming:[NoticeUpload]=[];for (i,p) in selected.enumerated() { guard let bytes=try await p.loadTransferable(type:Data.self),bytes.count <= 10*1024*1024,let image=JACPlatformImage(data:bytes),let jpeg=image.jpegData(compressionQuality:0.85) else { throw APIError.message("No se pudo leer la foto o supera los 10 MB.") };incoming.append(NoticeUpload(filename:"Comprobante-\(i+1).jpg",data:jpeg)) };add(incoming) } catch { self.error=error.localizedDescription }
    }
}
#if os(iOS)
struct TravelReceiptCamera:UIViewControllerRepresentable {
    let onImage:(UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onImage) }
    func makeUIViewController(context:Context) -> UIImagePickerController { let picker=UIImagePickerController();picker.sourceType = .camera;picker.delegate=context.coordinator;return picker }
    func updateUIViewController(_ uiViewController:UIImagePickerController,context:Context) {}
    final class Coordinator:NSObject,UIImagePickerControllerDelegate,UINavigationControllerDelegate {
        let callback:(UIImage?) -> Void
        init(_ callback:@escaping (UIImage?) -> Void) { self.callback=callback }
        func imagePickerControllerDidCancel(_ picker:UIImagePickerController) { callback(nil) }
        func imagePickerController(_ picker:UIImagePickerController,didFinishPickingMediaWithInfo info:[UIImagePickerController.InfoKey:Any]) { callback(info[.originalImage] as? UIImage) }
    }
}

#endif
