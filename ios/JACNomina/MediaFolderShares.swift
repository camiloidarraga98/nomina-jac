#if os(iOS)
import SwiftUI
import SafariServices

struct MediaSharedLink: Decodable, Identifiable {
    let id: String
    let url: String
    let createdAt: String
    let expiresAt: String
    func absoluteURL(origin: URL) -> URL? {
        guard url.range(of: "^/compartir/[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else { return nil }
        return URL(string: url, relativeTo: origin)?.absoluteURL
    }
}

struct MediaIncomingShare: Identifiable {
    let id: String
    var url: URL { PayrollClient.productionURL.appendingPathComponent("compartir").appendingPathComponent(id) }
    static func parse(_ url: URL) -> MediaIncomingShare? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.user == nil,
              parts.password == nil, parts.port == nil, parts.query == nil, parts.fragment == nil else { return nil }
        let token: String
        if parts.scheme == "https", parts.host == "jhonalexcastano.com", parts.path.hasPrefix("/compartir/") {
            token = String(parts.path.dropFirst("/compartir/".count))
        } else if parts.scheme == "jacnomina", parts.host == "compartir", parts.path.hasPrefix("/") {
            token = String(parts.path.dropFirst())
        } else { return nil }
        guard token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else { return nil }
        return MediaIncomingShare(id: token)
    }
}

// Safari's in-app controller uses the public capability page. No JAC session,
// login or access to the rest of the native account is granted by this route.
struct MediaSharedFolderBrowser: UIViewControllerRepresentable {
    let share: MediaIncomingShare
    func makeUIViewController(context: Context) -> SFSafariViewController {
        try? MediaVideoAudioPlayback.activate()
        return SFSafariViewController(url: share.url)
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: SFSafariViewController, coordinator: ()) { MediaVideoAudioPlayback.deactivate() }
}

struct MediaFolderShareSheet: View {
    let folder: MediaFolder
    let client: PayrollClient
    @Environment(\.dismiss) private var dismiss
    @State private var links: [MediaSharedLink] = []
    @State private var days = 30
    @State private var attempt: (id: String, days: Int)?
    @State private var busy = false
    @State private var error: String?
    @State private var stamp: String?
    @State private var operation: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(folder.name).font(.headline)
                    Text("Cualquier persona con el enlace podrá ver y descargar esta carpeta y sus subcarpetas sin una cuenta de JAC. Puedes revocarlo aquí.").font(.footnote).foregroundStyle(.secondary)
                    Picker("Vencimiento", selection: $days) { ForEach([7,30,90], id: \.self) { Text("\($0) días").tag($0) } }.disabled(busy || attempt != nil)
                    Button("Crear enlace") { run { try await create() } }.disabled(busy).accessibilityIdentifier("media.share.create")
                }
                if busy { ProgressView() }
                if let error { Section { InlineError(message: error) } }
                Section("Enlaces activos") {
                    ForEach(links) { link in
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Vence " + String(link.expiresAt.prefix(10))).font(.caption)
                            if let url = link.absoluteURL(origin: client.baseURL) {
                                ShareLink(item: url) { Label("Compartir enlace", systemImage: "square.and.arrow.up") }
                                    .accessibilityIdentifier("media.share.link." + link.id)
                            }
                            Button("Revocar enlace", role: .destructive) { run { try await revoke(link) } }
                                .disabled(busy).accessibilityIdentifier("media.share.revoke." + link.id)
                        }
                    }
                }
            }.navigationTitle("Compartir carpeta").jacInlineTitle()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Listo") { dismiss() } } }
        }
        .task { stamp = try? client.mediaAccessStamp(); run { try await refresh() } }
        .onChange(of: try? client.mediaAccessStamp()) { _, value in if value != stamp { links = []; operation?.cancel(); dismiss() } }
        .onDisappear { operation?.cancel(); links = [] }
    }
    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true; error = nil
        operation = Task { @MainActor in
            defer { busy = false }
            do { try await action() }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func validate() throws {
        try Task.checkCancellation()
        guard stamp != nil, stamp == (try client.mediaAccessStamp()), client.accessUser?.canUploadMedia == true else { throw CancellationError() }
    }
    private func refresh() async throws { let result = try await client.mediaFolderShares(folder.id); try validate(); links = result }
    private func create() async throws {
        try validate()
        if attempt == nil { attempt = (UUID().uuidString.lowercased(), days) }
        guard let attempt else { return }
        let link = try await client.createMediaFolderShare(folder.id, id: attempt.id, days: attempt.days)
        try validate(); links.removeAll { $0.id == link.id }; links.insert(link, at: 0); self.attempt = nil
    }
    private func revoke(_ link: MediaSharedLink) async throws {
        try validate(); try await client.revokeMediaFolderShare(folder.id, id: link.id); try validate(); links.removeAll { $0.id == link.id }
    }
}
#endif
