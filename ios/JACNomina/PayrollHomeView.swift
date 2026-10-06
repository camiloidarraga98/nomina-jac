import SwiftUI

struct PayrollHomeView: View {
    let overview: PayrollOverview
    var body: some View {
        TabView {
            PeriodsView(overview: overview).tabItem { Label("Quincenas", systemImage: "calendar") }
            PeriodsView(overview: overview, archive: true).tabItem { Label("Archivo", systemImage: "archivebox") }
            CalendarView(user: overview.user).tabItem { Label("Agenda", systemImage: "calendar.badge.clock") }
            EmployeesView(overview: overview).tabItem { Label("Equipo", systemImage: "person.2") }
            ManagementView(user: overview.user).tabItem { Label("Gestión", systemImage: "slider.horizontal.3") }
        }
    }
}
struct PeriodsView: View {
    @EnvironmentObject private var store: PayrollStore
    let overview: PayrollOverview
    var archive = false
    @State private var search = ""
    @State private var editor: PayrollEditorSession?
    @State private var path: [String] = []
    @State private var createdPeriod: String?
    private var periods: [PeriodSummary] {
        overview.periods.sorted { $0.start > $1.start }.filter {
            (!archive || $0.isClosed) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || ($0.isClosed ? "cerrada" : "abierta").localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        NavigationStack(path: $path) {
            List {
                OperationStatusSection()
                if periods.isEmpty {
                    ContentUnavailableView(search.isEmpty ? (archive ? "Archivo vacío" : "Sin quincenas") : "Sin resultados", systemImage: archive ? "archivebox" : "calendar", description: Text(archive ? "Consulta los cierres y sus documentos." : "Crea una quincena para comenzar."))
                }
                ForEach([false, true], id: \.self) { closed in
                    let group = periods.filter { $0.isClosed == closed }
                    if !group.isEmpty {
                        Section(closed ? "Quincenas cerradas" : "En preparación") {
                            ForEach(group) { period in
                                NavigationLink(value: period.id) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(period.title).font(.headline)
                                        HStack {
                                            Label(period.isClosed ? "Cerrada" : "Abierta", systemImage: period.isClosed ? "lock.fill" : "pencil")
                                            Spacer(); Text("\(period.showCount) shows")
                                        }.font(.caption).foregroundStyle(.secondary)
                                        if period.ownerOnly { Text("Corrección de cierre").font(.caption).foregroundStyle(.orange) }
                                    }.padding(.vertical, 5)
                                }.accessibilityIdentifier("period.\(period.id)")
                            }
                        }
                    }
                }
            }.navigationTitle(archive ? "Archivo" : "Quincenas")
                .navigationDestination(for: String.self) { PeriodDetailView(periodID: $0, user: overview.user) }
                .searchable(text: $search, prompt: "Buscar mes o estado")
                .refreshable { try? await store.refresh() }
                .toolbar {
                    if !archive && overview.user.can("payroll") {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                if let w = store.workspace { editor = PayrollEditorSession(kind: .period, workspace: w, detail: nil, record: PayrollEditorSession.newRecord(.period, workspace: w)) }
                            } label: { Image(systemName: "plus") }
                                .accessibilityLabel("Crear quincena").accessibilityIdentifier("period.create").disabled(!store.canWrite)
                        }
                    }
                }
                .sheet(item: $editor, onDismiss: { if let id = createdPeriod { path.append(id); createdPeriod = nil } }) { session in PayrollEditorView(session: session) { createdPeriod = $0 } }
        }
    }
}
