import SwiftUI

struct PayrollHomeView: View {
    let overview: PayrollOverview
    var body: some View {
        TabView {
            PeriodsView(overview: overview).tabItem { Label("Quincenas", systemImage: "calendar") }
            EmployeesView(overview: overview).tabItem { Label("Equipo", systemImage: "person.2") }
            AccountView(user: overview.user).tabItem { Label("Mi cuenta", systemImage: "person.crop.circle") }
        }
    }
}

struct PeriodsView: View {
    @EnvironmentObject private var store: PayrollStore
    let overview: PayrollOverview
    @State private var search = ""

    private var periods: [PeriodSummary] {
        overview.periods.sorted { $0.start > $1.start }.filter {
            search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || ($0.isClosed ? "cerrada" : "abierta").localizedCaseInsensitiveContains(search)
        }
    }
    var body: some View {
        NavigationStack {
            List {
                if let error = store.error { Section { InlineError(message: error) } }
                if overview.periods.isEmpty {
                    ContentUnavailableView("Sin quincenas", systemImage: "calendar", description: Text("Las quincenas que registres en el sistema aparecerán aquí."))
                } else if periods.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else {
                    ForEach([false, true], id: \.self) { closed in
                        let group = periods.filter { $0.isClosed == closed }
                        if !group.isEmpty {
                            Section(closed ? "Archivo" : "En preparación") {
                                ForEach(group) { period in
                                    NavigationLink { PeriodDetailView(summary: period, user: overview.user) } label: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(period.title).font(.headline)
                                            HStack {
                                                Label(period.isClosed ? "Cerrada" : "Abierta", systemImage: period.isClosed ? "lock.fill" : "pencil")
                                                Spacer()
                                                Text("\(period.showCount) shows")
                                            }.font(.caption).foregroundStyle(.secondary)
                                        }.padding(.vertical, 5)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Quincenas")
            .searchable(text: $search, prompt: "Buscar mes o estado")
            .refreshable { try? await store.refresh() }
        }
    }
}
