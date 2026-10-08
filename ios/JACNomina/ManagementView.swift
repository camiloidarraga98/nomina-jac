import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import UIKit

struct ManagementView: View {
    @EnvironmentObject private var store: PayrollStore
    let user: PayrollUser
    var body: some View {
        NavigationStack {
            List {
                OperationStatusSection()
                Section("Avisos") {
                    NavigationLink { TravelExpensesView() } label: { Label("Gastos de viaje",systemImage:"receipt") }.accessibilityIdentifier("management.expenses")
                    NavigationLink { NoticesView(user: user, kind: "alert") } label: { Label("Alertas", systemImage: "bell") }.accessibilityIdentifier("notices.alerts")
                    NavigationLink { NotificationSettingsView() } label: { Label("Notificaciones", systemImage: "bell.badge") }.accessibilityIdentifier("management.notifications")
                }
                if user.itinerariesOnly != true { Section("Administración") {
                    if let overview = store.overview {
                        NavigationLink { PeriodsView(overview: overview, archive: true, embedded: true) } label: { Label("Archivo", systemImage: "archivebox") }.accessibilityIdentifier("management.archive")
                        NavigationLink { EmployeesView(overview: overview, embedded: true) } label: { Label("Equipo", systemImage: "person.2") }.accessibilityIdentifier("management.employees")
                    }
                    NavigationLink { ConceptsRulesView(user: user) } label: { Label("Conceptos y reglas", systemImage: "list.bullet.rectangle") }
                    NavigationLink { MailView(user: user) } label: { Label("Correos y Gmail", systemImage: "envelope") }
                    if user.isOwner { NavigationLink { UsersView() } label: { Label("Usuarios y permisos", systemImage: "person.badge.key") } }
                }
            } }.jacSurface().navigationTitle("Gestión")
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
        }.jacSurface().navigationTitle("Conceptos y reglas").navigationBarTitleDisplayMode(.inline)
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
    var body:some View {
        List {
            if let error { InlineError(message:error) }
            Section { Text("Adjunta tus comprobantes. Un administrador revisará el gasto antes de incorporarlo como reintegro.").font(.footnote).foregroundStyle(.secondary)
                Button("Registrar gasto") { editor=true }.accessibilityIdentifier("expenses.create") }
            Section("Gastos de viaje") {
                ForEach(records) { item in Button { detail=item } label: { VStack(alignment:.leading,spacing:8) {
                    Text(item.concept).font(.headline);Text(PayrollFormat.money(item.amount));Text(item.name+" · "+item.expenseDate).font(.caption).foregroundStyle(.secondary);Text(item.statusLabel).font(.caption)
                }.padding(.vertical,6) }.buttonStyle(.plain).accessibilityIdentifier("expense."+item.id) }
                if records.isEmpty { Text(feed == nil ? "Consultando…" : "Todavía no hay gastos registrados.").foregroundStyle(.secondary) }
                if let cursor=feed?.nextCursor,!cursor.isEmpty { Button("Ver anteriores") { Task { await load(cursor) } } }
            }
        }.jacSurface().navigationTitle("Gastos de viaje").navigationBarTitleDisplayMode(.inline)
            .task { await load() }.refreshable { await load() }
            .sheet(isPresented:$editor) { ExpenseComposer { await load() } }
            .sheet(item:$detail,onDismiss:{ Task { await load() } }) { item in ExpenseDetailView(item:item,feed:feed) }
    }
    private func load(_ cursor:String = "") async { do { let result=try await store.client.expenses(cursor:cursor);feed=result;if cursor.isEmpty { records=result.expenses } else { records += result.expenses.filter { item in !records.contains { $0.id == item.id } } };error=nil } catch { self.error=store.reportReadFailure(error) } }
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
                        Button("Rechazar con motivo",role:.destructive) { Task { await review(false) } }.disabled(busy || reason.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).accessibilityIdentifier("expenses.reject")
                    }.disabled(busy)
                }
            }.jacSurface().navigationTitle("Gasto de viaje").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Listo") { dismiss() }.disabled(busy) } }
                .sheet(item:$document,onDismiss:{ if let previousDocument { TemporaryDocuments.remove(previousDocument);self.previousDocument=nil } }) { file in
                    NavigationStack { DocumentPreview(url:file.url).privacySensitive().ignoresSafeArea(edges:.bottom).navigationTitle("Comprobante").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement:.confirmationAction) { Button("Listo") { document=nil } } } }
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
    @State private var id=UUID().uuidString.lowercased()
    @State private var concept=""
    @State private var amount=""
    @State private var date=Date()
    @State private var note=""
    @State private var files:[NoticeUpload]=[]
    @State private var attempted=false
    @State private var busy=false
    @State private var importing=false
    @State private var error:String?
    var body:some View {
        NavigationStack {
            Form {
                if let error { InlineError(message:error) }
                Section("Gasto en pesos colombianos") { TextField("Concepto",text:$concept).accessibilityIdentifier("expenses.concept");TextField("Valor en COP",text:$amount).keyboardType(.numberPad).accessibilityIdentifier("expenses.amount");DatePicker("Fecha",selection:$date,displayedComponents:.date).environment(\.timeZone,CalendarClock.calendar.timeZone);TextField("Nota opcional",text:$note,axis:.vertical).lineLimit(2...5) }.disabled(busy || attempted)
                TravelAttachmentsPicker(files:$files,importing:$importing).disabled(busy || attempted)
                if attempted && error != nil { Section { Text("Reintenta con los mismos datos. Para modificarlos, abre un formulario nuevo.").font(.footnote) } }
                Section { Button(busy ? "Enviando…" : "Enviar a revisión") { Task { await save() } }.buttonStyle(JACPrimaryButtonStyle()).disabled(busy || importing).accessibilityIdentifier("expenses.submit") }
            }.jacSurface().navigationTitle("Registrar gasto").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancelar") { dismiss() }.disabled(busy) } }
        }.interactiveDismissDisabled(busy)
    }
    private func save() async {
        guard !busy,let value=Double(amount),value > 0,value <= 1e9,value.rounded() == value,concept.trimmingCharacters(in:.whitespacesAndNewlines).count >= 2,concept.utf16.count <= 120,note.utf16.count <= 500,!files.isEmpty else { error="Revisa concepto, valor en pesos y comprobantes.";return }
        busy=true;attempted=true;defer { busy=false }
        do { try await store.client.submitExpense(id:id,concept:concept,amount:value,date:BoardingClock.today(date),note:note,files:files);dismiss();await onSaved() } catch { self.error=error.localizedDescription;store.report(error) }
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
                Section { Button(busy ? "Guardando…" : "Actualizar y notificar") { Task { await save() } }.buttonStyle(JACPrimaryButtonStyle()).disabled(busy || importing).accessibilityIdentifier("itinerary.update.save") }
            }.jacSurface().navigationTitle("Actualizar itinerario").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancelar") { dismiss() }.disabled(busy) } }
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
            if UIImagePickerController.isSourceTypeAvailable(.camera) { Button("Fotografiar comprobante") { camera=true } }
            ForEach(files) { file in HStack { Text(file.filename);Spacer();Button(role:.destructive) { files.removeAll { $0.id == file.id } } label: { Image(systemName:"xmark.circle") }.accessibilityLabel("Quitar "+file.filename) } }
            Text("De 1 a 5 archivos PDF, JPG o PNG. 10 MB en total.").font(.footnote).foregroundStyle(.secondary)
            #if DEBUG
            if store.client.baseURL.host?.hasSuffix(".invalid") == true { Button("Adjuntar comprobante ficticio") { add([NoticeUpload(filename:"Comprobante ficticio.pdf",data:UIGraphicsPDFRenderer(bounds:CGRect(x:0,y:0,width:200,height:200)).pdfData { c in c.beginPage();("PRUEBA SIN DATOS REALES" as NSString).draw(at:CGPoint(x:10,y:10),withAttributes:nil) })]) }.accessibilityIdentifier("travel.fixture") }
            #endif
        }.disabled(importing)
            .fileImporter(isPresented:$picking,allowedContentTypes:[.pdf,.jpeg,.png],allowsMultipleSelection:true) { result in
                do { var incoming:[NoticeUpload]=[];for url in try result.get() { let access=url.startAccessingSecurityScopedResource();defer { if access { url.stopAccessingSecurityScopedResource() } };guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) <= 10*1024*1024 else { throw APIError.message("El archivo supera los 10 MB.") };let data=try Data(contentsOf:url);_ = try NoticeUpload.mime(data);incoming.append(NoticeUpload(filename:url.lastPathComponent,data:data)) };add(incoming) } catch { if (error as? CocoaError)?.code != .userCancelled { self.error=error.localizedDescription } }
            }
            .onChange(of:photos) { _,selected in Task { await readPhotos(selected) } }
            .sheet(isPresented:$camera) { TravelReceiptCamera { image in camera=false;if let image,let bytes=image.jpegData(compressionQuality:0.85) { add([NoticeUpload(filename:"Comprobante.jpg",data:bytes)]) } } }
    }
    private func add(_ incoming:[NoticeUpload]) { guard files.count+incoming.count <= 5,(files+incoming).reduce(0, { $0+$1.data.count }) <= 10*1024*1024 else { error="Elige hasta 5 archivos que sumen como máximo 10 MB.";return };files += incoming;error=nil }
    private func readPhotos(_ selected:[PhotosPickerItem]) async {
        guard !selected.isEmpty else { return };importing=true;defer { importing=false;photos=[] }
        do { var incoming:[NoticeUpload]=[];for (i,p) in selected.enumerated() { guard let bytes=try await p.loadTransferable(type:Data.self),bytes.count <= 10*1024*1024,let image=UIImage(data:bytes),let jpeg=image.jpegData(compressionQuality:0.85) else { throw APIError.message("No se pudo leer la foto o supera los 10 MB.") };incoming.append(NoticeUpload(filename:"Comprobante-\(i+1).jpg",data:jpeg)) };add(incoming) } catch { self.error=error.localizedDescription }
    }
}
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
