import SwiftUI
import QuickLook
import UIKit

struct DocumentsSection: View {
    @EnvironmentObject private var store: PayrollStore
    let detail: PeriodDetail
    let user: PayrollUser
    @State private var search = ""
    var body: some View {
        Section("Documentos de la quincena") {
            if !detail.period.isClosed {
                Text("Los documentos estarán disponibles cuando se cierre la quincena.").foregroundStyle(.secondary)
            } else if !user.can("export") {
                Text("Tu cuenta no tiene permiso para descargar documentos.").foregroundStyle(.secondary)
            } else {
                ForEach(DocumentFormat.allCases) { format in
                    ExportButton(periodID: detail.period.id, format: format)
                }
            }
        }
        if detail.period.isClosed && user.can("export") {
            Section("Desprendible individual") {
                TextField("Buscar persona para imprimir", text: $search)
                ForEach(uniqueEmployees, id: \.employeeId) { payment in
                    ExportButton(periodID: detail.period.id, format: .pdf, employeeID: payment.employeeId, title: payment.name)
                }
            }
        }
    }
    private var uniqueEmployees: [PayrollPayment] {
        var seen = Set<String>()
        return detail.calculation.rows.filter { seen.insert($0.employeeId).inserted && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }.sorted { $0.name < $1.name }
    }
}

struct PaymentDetailView: View {
    let rows: [PayrollPayment]
    let period: PayrollPeriod
    let user: PayrollUser
    var conditions: JSONValue? = nil
    var body: some View {
        List {
            if let first = rows.first {
                Section {
                    Text(first.name).font(.title2.weight(.semibold))
                    LabeledContent("Documento", value: first.document); LabeledContent("Cargo", value: first.role)
                    AmountRow(title: "Neto total de la persona", value: rows.reduce(0) { $0 + $1.net })
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Section(PayrollFormat.category(row.category)) {
                        AmountRow(title: "Ingresos", value: row.gross); AmountRow(title: "Descuentos", value: row.deductions)
                        AmountRow(title: "Reintegros", value: row.reimbursements); AmountRow(title: "Neto", value: row.net)
                        ForEach(Array(row.items.enumerated()), id: \.offset) { _, item in
                            VStack(alignment: .leading, spacing: 5) {
                                AmountRow(title: item.concept, value: item.amount)
                                Text("\(PayrollFormat.number(item.quantity)) × \(PayrollFormat.money(item.rate)) · \(item.kind)").font(.caption).foregroundStyle(.secondary)
                                if let reference = item.reference { Text(reference).font(.caption).foregroundStyle(.secondary) }
                            }.padding(.vertical, 3)
                        }
                    }
                }
                if let conditions {
                    Section { NavigationLink("Condiciones utilizadas en este corte") { List { EmployeeConditionsSection(record: conditions) }.jacSurface().navigationTitle("Condiciones del corte") } }
                }
                if period.isClosed && user.can("export") {
                    Section { ExportButton(periodID: period.id, format: .pdf, employeeID: first.employeeId, title: "Desprendible PDF") }
                }
            }
        }.jacSurface().navigationTitle("Detalle del pago").navigationBarTitleDisplayMode(.inline)
    }
}

struct ExportButton: View {
    @EnvironmentObject private var store: PayrollStore
    let periodID: String
    let format: DocumentFormat
    var employeeID: String? = nil
    var title: String? = nil
    @State private var document: ExportedDocument?
    @State private var pendingDocument: ExportedDocument?
    @State private var downloading = false
    @State private var error: String?

    var body: some View {
        Button {
            downloading = true; error = nil
            Task {
                defer { downloading = false }
                do {
                    let result = try await store.client.download(periodID: periodID, format: format, employeeID: employeeID)
                    pendingDocument = result; document = result
                } catch { self.error = error.localizedDescription; store.report(error) }
            }
        } label: {
            HStack { Label(title ?? format.title, systemImage: "doc.text"); Spacer(); if downloading { ProgressView() } else { Image(systemName: "arrow.down.circle") } }
        }
        .disabled(downloading)
        .sheet(item: $document, onDismiss: {
            if let pendingDocument { TemporaryDocuments.remove(pendingDocument); self.pendingDocument = nil }
        }) { file in
            NavigationStack {
                DocumentPreview(url: file.url).ignoresSafeArea(edges: .bottom)
                    .jacSurface().navigationTitle(title ?? format.title).navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { Button("Listo") { document = nil } }
                        ToolbarItem(placement: .topBarTrailing) {
                            if file.url.pathExtension.lowercased() == "pdf" { Button { let printer = UIPrintInteractionController.shared; printer.printingItem = file.url; printer.present(animated: true, completionHandler: nil) } label: { Image(systemName: "printer") }.accessibilityLabel("Imprimir documento") }
                        }
                        ToolbarItem(placement: .topBarTrailing) { ShareLink(item: file.url) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Compartir documento") }
                    }
            }
        }
        .alert("No se pudo descargar", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Aceptar", role: .cancel) { error = nil }
        } message: { Text(error ?? "Intenta de nuevo.") }
    }
}

struct DocumentPreview: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}
