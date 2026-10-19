import SwiftUI
import AVFoundation
import Combine
import UniformTypeIdentifiers
#if canImport(MediaPlayer)
import MediaPlayer
#endif

enum MusicSection: String, Codable, CaseIterable, Identifiable {
    case warmup, tracks, demos, studio
    var id: String { rawValue }
    var title: String { switch self { case .warmup: "Para Calentar"; case .tracks: "Pistas"; case .demos: "Maquetas"; case .studio: "Música estudio" } }
    var subtitle: String { switch self { case .warmup: "Antes de salir al escenario"; case .tracks: "Las canciones de Jhon Alex, de la A a la Z"; case .demos: "Ideas y demos para escuchar y elegir"; case .studio: "Lo que está tomando forma en el estudio" } }
    var icon: String { switch self { case .warmup: "flame"; case .tracks: "mic"; case .demos: "headphones"; case .studio: "slider.horizontal.3" } }
    var color: Color { switch self {case .warmup: .orange; case .tracks: JACTheme.action; case .demos: .purple; case .studio: .teal} }
}
struct MusicTrack: Codable, Identifiable, Equatable {
    let id: String
    let section: MusicSection
    let title: String
    let filename: String
    let mimeType: String
    let size: Int64
    let revision: String
    let createdAt: String
    var mediaItem: MediaItem { MediaItem(id: id, name: filename, mimeType: mimeType, kind: "audio", size: size, modifiedAt: revision, thumbnailAvailable: false) }
    var sizeLabel: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
    static func sorted(_ tracks: [MusicTrack]) -> [MusicTrack] {
        tracks.sorted { a,b in
            let order = a.title.compare(b.title, options: [.caseInsensitive,.diacriticInsensitive,.numeric], locale: Locale(identifier:"es_CO"))
            return order == .orderedSame ? a.id < b.id : order == .orderedAscending
        }
    }
    func matches(_ query: String) -> Bool { query.isEmpty || title.range(of: query, options:[.caseInsensitive,.diacriticInsensitive], locale:Locale(identifier:"es_CO")) != nil }
}
struct MusicLibrary: Codable {
    let tracks: [MusicTrack]
    let canUpload: Bool
    let canDelete: Bool
    // Web-only derived capabilities are intentionally ignored by the native decoder.
}
struct MusicImportFile: Identifiable {
    let id: String
    let name: String
    let url: URL
    let size: Int64
    static func copy(_ source: URL) throws -> MusicImportFile {
        guard source.isFileURL, ["mp3","m4a","aac","wav"].contains(source.pathExtension.lowercased()) else { throw APIError.invalid("Selecciona un audio MP3, M4A, AAC o WAV.") }
        let access = source.startAccessingSecurityScopedResource(); defer { if access {source.stopAccessingSecurityScopedResource()} }
        let id = UUID().uuidString.lowercased(), folder = FileManager.default.temporaryDirectory.appendingPathComponent("JACMusicImports",isDirectory:true).appendingPathComponent(id,isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:JACFileSecurity.directoryAttributes)
        do {
            let name = MediaLocalFile.safeName(source.lastPathComponent), target = folder.appendingPathComponent(name)
            var coordinationError: NSError?, copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt:source,options:[],error:&coordinationError) { readable in
                do {try FileManager.default.copyItem(at:readable,to:target)} catch {copyError=error}
            }
            if let coordinationError { throw coordinationError }
            if let copyError { throw copyError }
            try FileManager.default.setAttributes(JACFileSecurity.fileAttributes,ofItemAtPath:target.path)
            let size = Int64(try target.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0)
            guard size >= 12 else {throw APIError.invalid("El audio está vacío o incompleto.")}
            return MusicImportFile(id:id,name:name,url:target,size:size)
        } catch {try? FileManager.default.removeItem(at:folder);throw error}
    }
    func remove() {try? FileManager.default.removeItem(at:url.deletingLastPathComponent())}
}
struct MusicIncomingAudio: Identifiable {
    let id = UUID()
    let files: [MusicImportFile]
}

enum MusicPlaybackDocuments {
    static var root: URL { FileManager.default.temporaryDirectory.appendingPathComponent("JACMusicPlayback", isDirectory: true) }
    static func remove(_ document: ExportedDocument) {
        let folder = document.url.deletingLastPathComponent()
        guard folder.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: folder)
    }
    static func clear() { try? FileManager.default.removeItem(at: root) }
}

@MainActor final class MusicPlayer: ObservableObject {
    @Published private(set) var current: MusicTrack?
    @Published private(set) var playing = false
    @Published private(set) var preparing = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var error: String?
    let client: PayrollClient
    private let player = AVPlayer()
    private var queue: [MusicTrack] = []
    private var position = 0
    private var generation = UUID()
    private var task: Task<Void,Never>?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var itemObserver: NSKeyValueObservation?
    private var notices: [NSObjectProtocol] = []
    private var localDocument: ExportedDocument?
    private var resumeAfterInterruption = false
    #if canImport(MediaPlayer)
    private var remoteTargets: [(MPRemoteCommand,Any)] = []
    #endif
    init(client: PayrollClient) {
        self.client = client
        statusObserver = player.observe(\.timeControlStatus, options:[.initial,.new]) { [weak self] _,_ in Task { @MainActor [weak self] in guard let self else {return};self.playing=self.player.timeControlStatus == .playing;self.preparing=self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate;self.updateNowPlaying() } }
        timeObserver = player.addPeriodicTimeObserver(forInterval:CMTime(seconds:0.5,preferredTimescale:600),queue:.main) { [weak self] time in Task { @MainActor [weak self] in guard let self else {return};self.elapsed=time.seconds.isFinite ? time.seconds:0;let length=self.player.currentItem?.duration.seconds ?? 0;self.duration=length.isFinite ? length:0;self.updateNowPlaying() } }
        notices.append(NotificationCenter.default.addObserver(forName:.AVPlayerItemDidPlayToEndTime,object:nil,queue:.main) { [weak self] notice in Task { @MainActor [weak self] in guard let self, let item=notice.object as? AVPlayerItem, item === self.player.currentItem else {return};self.next() } })
        notices.append(NotificationCenter.default.addObserver(forName:Notification.Name("JACVideoPlaybackBegan"),object:nil,queue:.main) { [weak self] _ in Task { @MainActor [weak self] in self?.pause() } })
        #if os(iOS)
        notices.append(NotificationCenter.default.addObserver(forName:AVAudioSession.interruptionNotification,object:nil,queue:.main) { [weak self] notice in
            let type=(notice.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let options=AVAudioSession.InterruptionOptions(rawValue:notice.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            Task { @MainActor [weak self] in guard let self else{return};if type == .began {self.resumeAfterInterruption=self.playing;self.player.pause()} else if type == .ended {let resume=self.resumeAfterInterruption && options.contains(.shouldResume);self.resumeAfterInterruption=false;if resume {self.resume()}} }
        })
        notices.append(NotificationCenter.default.addObserver(forName:AVAudioSession.routeChangeNotification,object:nil,queue:.main) { [weak self] notice in
            let reason=notice.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {Task { @MainActor [weak self] in self?.pause() }}
        })
        #endif
        configureRemoteControls()
    }
    func play(_ track: MusicTrack, queue: [MusicTrack]) {
        self.queue=queue;self.position=queue.firstIndex(where:{$0.id==track.id}) ?? 0
        do {try client.beginMusicPlayback();begin(track)} catch {self.error=error.localizedDescription}
    }
    private func begin(_ track: MusicTrack) {
        task?.cancel();generation=UUID();let own=generation;player.pause();player.replaceCurrentItem(with:nil);cleanupLocal()
        current=track;preparing=true;playing=false;elapsed=0;duration=0;error=nil
        task=Task { [weak self] in
            guard let self else {return}
            do {
                let (url,document)=try await client.musicPlayback(track)
                guard generation==own,!Task.isCancelled else {if let document {MusicPlaybackDocuments.remove(document)};return}
                localDocument=document
                #if os(iOS)
                try AVAudioSession.sharedInstance().setCategory(.playback,mode:.default)
                try AVAudioSession.sharedInstance().setActive(true)
                #endif
                let item=AVPlayerItem(url:url)
                itemObserver=item.observe(\.status,options:[.new]) { [weak self] item,_ in
                    let failure=item.status == .failed ? item.error?.localizedDescription ?? "No se pudo reproducir el audio.":nil
                    if let failure { Task { @MainActor [weak self] in guard let self,self.generation==own else{return};self.error=failure;self.preparing=false;self.playing=false } }
                }
                player.replaceCurrentItem(with:item);player.play();updateNowPlaying()
            } catch {guard generation==own else{return};preparing=false;playing=false;if !(error is CancellationError) {self.error=error.localizedDescription}}
        }
    }
    func pause() {resumeAfterInterruption=false;player.pause();playing=false;updateNowPlaying()}
    func resume() {
        guard current != nil else {return}
        #if os(iOS)
        do {try AVAudioSession.sharedInstance().setCategory(.playback,mode:.default);try AVAudioSession.sharedInstance().setActive(true)} catch {self.error=error.localizedDescription;return}
        #endif
        player.play()
    }
    func toggle() {playing ? pause():resume()}
    func seek(_ seconds: Double) {guard seconds.isFinite else{return};player.seek(to:CMTime(seconds:max(0,min(seconds,duration)),preferredTimescale:600));elapsed=seconds;updateNowPlaying()}
    func next() {guard position+1<queue.count else {pause();return};position+=1;begin(queue[position])}
    func previous() {if elapsed>3 {seek(0)} else if position>0 {position-=1;begin(queue[position])}}
    func reconcile(_ library: MusicLibrary) {
        let fresh=Dictionary(uniqueKeysWithValues:library.tracks.map{($0.id,$0.revision)})
        if let current, fresh[current.id] != current.revision {stop()}
        let currentID=current?.id;queue=queue.filter{fresh[$0.id]==$0.revision};if let currentID {position=queue.firstIndex(where:{$0.id==currentID}) ?? 0}
    }
    func stop() {
        task?.cancel();task=nil;generation=UUID();player.pause();player.replaceCurrentItem(with:nil);itemObserver=nil;cleanupLocal()
        client.endMusicPlayback()
        current=nil;queue=[];playing=false;preparing=false;elapsed=0;duration=0;resumeAfterInterruption=false
        #if canImport(MediaPlayer)
        MPNowPlayingInfoCenter.default().nowPlayingInfo=nil
        #endif
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
        #endif
    }
    private func cleanupLocal() {if let localDocument {MusicPlaybackDocuments.remove(localDocument)};localDocument=nil}
    private func updateNowPlaying() {
        #if canImport(MediaPlayer)
        guard let current else {return}
        MPNowPlayingInfoCenter.default().nowPlayingInfo=[MPMediaItemPropertyTitle:current.title,MPMediaItemPropertyArtist:"Jhon Alex Castaño",MPMediaItemPropertyAlbumTitle:current.section.title,MPMediaItemPropertyPlaybackDuration:duration,MPNowPlayingInfoPropertyElapsedPlaybackTime:elapsed,MPNowPlayingInfoPropertyPlaybackRate:playing ? 1.0:0.0,MPNowPlayingInfoPropertyMediaType:MPNowPlayingInfoMediaType.audio.rawValue]
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState=playing ? .playing:.paused
        #endif
        #endif
    }
    private func configureRemoteControls() {
        #if canImport(MediaPlayer)
        let center=MPRemoteCommandCenter.shared()
        for (command, action) in [(center.playCommand,0),(center.pauseCommand,1),(center.togglePlayPauseCommand,2),(center.nextTrackCommand,3),(center.previousTrackCommand,4)] {
            command.isEnabled=true
            let target=command.addTarget { [weak self] _ in Task { @MainActor [weak self] in guard let self else{return};switch action {case 0:self.resume();case 1:self.pause();case 2:self.toggle();case 3:self.next();default:self.previous()} };return .success }
            remoteTargets.append((command,target))
        }
        let target=center.changePlaybackPositionCommand.addTarget { [weak self] event in guard let e=event as? MPChangePlaybackPositionCommandEvent else{return .commandFailed};Task { @MainActor [weak self] in self?.seek(e.positionTime) };return .success }
        remoteTargets.append((center.changePlaybackPositionCommand,target))
        #endif
    }
}

struct MusicMiniPlayer: View {
    @ObservedObject var player: MusicPlayer
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    var body: some View {
        if let track=player.current {
            VStack(spacing:8) {
                HStack(spacing:12) {
                    Image(systemName:"music.note").font(.title2).foregroundStyle(JACTheme.action).frame(width:36)
                    VStack(alignment:.leading,spacing:3) {Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1);Text(track.section.title).font(.caption).foregroundStyle(.secondary)}
                    Spacer(minLength:4)
                    if player.preparing {ProgressView().controlSize(.small)}
                    Button {player.previous()} label:{Image(systemName:"backward.end.fill")}.accessibilityLabel("Audio anterior")
                    Button {player.toggle()} label:{Image(systemName:player.playing ? "pause.fill":"play.fill").font(.title3).frame(width:36,height:36)}.accessibilityLabel(player.playing ? "Pausar música":"Reproducir música").accessibilityIdentifier("music.player.toggle")
                    Button {player.next()} label:{Image(systemName:"forward.end.fill")}.accessibilityLabel("Siguiente audio")
                    Button {player.stop()} label:{Image(systemName:"xmark").foregroundStyle(.secondary).frame(width:30,height:36)}.accessibilityLabel("Cerrar reproductor")
                }.buttonStyle(.plain)
                HStack(spacing:8) {
                    Text(Self.time(scrubbing ? scrubValue:player.elapsed)).monospacedDigit().font(.caption2).foregroundStyle(.secondary)
                    Slider(value:Binding(get:{scrubbing ? scrubValue:player.elapsed},set:{scrubValue=$0}),in:0...max(1,player.duration),onEditingChanged:{editing in if editing {scrubValue=player.elapsed;scrubbing=true} else {player.seek(scrubValue);scrubbing=false}}).accessibilityLabel("Posición del audio")
                    Text(Self.time(player.duration)).monospacedDigit().font(.caption2).foregroundStyle(.secondary)
                }
                if let error=player.error {Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)}
            }.padding(.horizontal,16).padding(.vertical,10).background(.bar).overlay(alignment:.top){Divider()}.accessibilityIdentifier("music.player")
        }
    }
    private static func time(_ value: Double) -> String {guard value.isFinite,value>=0 else{return "0:00"};return String(format:"%d:%02d",Int(value)/60,Int(value)%60)}
}

struct MusicLibraryView: View {
    let user: PayrollUser
    @EnvironmentObject private var store: PayrollStore
    @State private var library: MusicLibrary?
    @State private var section: MusicSection?
    @State private var search = ""
    @State private var error: String?
    @State private var notice: String?
    @State private var loading = false
    @State private var picker = false
    @State private var importing: MusicIncomingAudio?
    @State private var deleting: MusicTrack?
    @State private var downloaded: Set<String> = []
    @State private var downloadTask: Task<Void,Never>?
    @State private var downloadProgress: String?
    private var tracks: [MusicTrack] { MusicTrack.sorted((library?.tracks ?? []).filter{(section == nil || $0.section == section) && $0.matches(search)}) }
    var body: some View {
        List {
            if let error {Section {InlineError(message:error)}}
            if let notice {Section {Text(notice).font(.subheadline).foregroundStyle(.secondary)}}
            if let downloadProgress {Section {HStack{ProgressView().controlSize(.small);Text(downloadProgress).font(.caption);Spacer();Button("Cancelar"){downloadTask?.cancel()}}}}
            if section == nil && search.isEmpty {
                Section {
                    ForEach(MusicSection.allCases) {item in
                        Button {section=item;search=""} label:{
                            HStack(spacing:16) {
                                Image(systemName:item.icon).font(.title2).foregroundStyle(item.color).frame(width:58,height:58).background(item.color.opacity(0.1),in:RoundedRectangle(cornerRadius:16))
                                VStack(alignment:.leading,spacing:5) {Text(item.title).font(.headline).foregroundStyle(JACTheme.ink);Text(item.subtitle).font(.caption).foregroundStyle(.secondary);Text("\(library?.tracks.filter{$0.section==item}.count ?? 0) audios").font(.caption2).foregroundStyle(.secondary)}
                                Spacer();Image(systemName:"chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            }.padding(.vertical,8)
                        }.buttonStyle(.plain).accessibilityIdentifier("music.section."+item.rawValue)
                    }
                }
            } else {
                Section {
                    if let section, let library, !library.tracks.filter({$0.section==section}).isEmpty {
                        Button {download(library.tracks.filter{$0.section==section})} label:{Label("Descargar sección sin conexión",systemImage:"arrow.down.circle")}.disabled(downloadTask != nil || store.isOffline).accessibilityIdentifier("music.download.section")
                    }
                    ForEach(tracks) {track in row(track)}
                    if tracks.isEmpty && !loading {ContentUnavailableView(search.isEmpty ? "Aún no hay audios":"No encontramos ese audio",systemImage:"headphones",description:Text(search.isEmpty ? "Los audios aparecerán cuando el equipo los suba.":"Prueba con otro nombre."))}
                } header:{Text(section?.title ?? "Resultados en Música")}
            }
            if loading && library == nil {Section {ProgressView("Cargando Música…")}}
            Section {Label("Las descargas están disponibles en este dispositivo sin conexión.",systemImage:"arrow.down.circle").font(.caption).foregroundStyle(.secondary)}
        }.jacSurface().navigationTitle(section?.title ?? "Música").jacInlineTitle()
            .searchable(text:$search,prompt:section == nil ? "Buscar en toda Música":"Buscar en esta sección")
            .toolbar {
                if section != nil {ToolbarItem(placement:.cancellationAction){Button {section=nil;search=""} label:{Label("Música",systemImage:"chevron.left")}}}
                if user.canUploadMusic {ToolbarItem(placement:.primaryAction){Button {picker=true} label:{Label("Subir audios",systemImage:"plus")}.disabled(store.isOffline).accessibilityIdentifier("music.import")}}
                ToolbarItem {Button {Task{await load()}} label:{Image(systemName:"arrow.clockwise")}.disabled(loading).accessibilityLabel("Actualizar Música")}
            }
            .fileImporter(isPresented:$picker,allowedContentTypes:[.audio],allowsMultipleSelection:true) {result in
                do {let urls=try result.get();Task {await prepare(urls)}} catch {self.error=error.localizedDescription}
            }
            .sheet(item:$importing,onDismiss:{Task{await load()}}){incoming in MusicImportView(incoming:incoming,initialSection:section ?? .warmup).environmentObject(store)}
            .confirmationDialog("Eliminar audio",isPresented:Binding(get:{deleting != nil},set:{if !$0 {deleting=nil}}),titleVisibility:.visible) {
                if let track=deleting {Button("Eliminar «\(track.title)»",role:.destructive){Task{await remove(track)}}}
            } message:{Text("Dejará de estar disponible para el equipo.")}
            .task {library=store.client.cachedMusic();updateDownloads();await load()}
            .onDisappear {downloadTask?.cancel()}
    }
    private func row(_ track: MusicTrack) -> some View {
        HStack(spacing:12) {
            Button {store.music.play(track,queue:tracks)} label:{
                HStack(spacing:14) {
                    Image(systemName:"play.fill").foregroundStyle(JACTheme.action).frame(width:36,height:44)
                    VStack(alignment:.leading,spacing:5) {Text(track.title).font(.body.weight(.medium)).foregroundStyle(JACTheme.ink);Text((section == nil ? track.section.title+" · ":"")+track.filename.components(separatedBy:".").last!.uppercased()+" · "+track.sizeLabel).font(.caption).foregroundStyle(.secondary)}
                    Spacer(minLength:4)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("music.track."+track.id)
            if downloaded.contains(track.id) {Image(systemName:"checkmark.circle.fill").foregroundStyle(.teal).accessibilityLabel("Disponible sin conexión")}
            Menu {
                Button {store.music.play(track,queue:tracks)} label:{Label("Reproducir",systemImage:"play")}
                if downloaded.contains(track.id) {Button {do {if store.music.current?.id==track.id {store.music.stop()};try store.client.forgetMusic(track);updateDownloads()} catch {self.error=error.localizedDescription}} label:{Label("Quitar descarga de este dispositivo",systemImage:"arrow.down.circle")}}
                else {Button {download([track])} label:{Label("Descargar sin conexión",systemImage:"arrow.down.circle")}.disabled(downloadTask != nil || store.isOffline)}
                if library?.canDelete == true {Button(role:.destructive){deleting=track} label:{Label("Eliminar audio",systemImage:"trash")}}
            } label:{Image(systemName:"ellipsis").frame(width:36,height:44).contentShape(Rectangle())}.accessibilityLabel("Opciones de "+track.title)
        }.padding(.vertical,5)
    }
    private func prepare(_ urls:[URL]) async {
        do {let files=try await Task.detached(priority:.userInitiated){var files:[MusicImportFile]=[];do {for url in urls {files.append(try MusicImportFile.copy(url))};return files} catch {files.forEach{$0.remove()};throw error}}.value;importing=MusicIncomingAudio(files:files)} catch {self.error=error.localizedDescription}
    }
    private func load() async {
        guard !loading else{return};loading=true;defer{loading=false};error=nil
        do {let value=try await store.client.musicLibrary();library=value;store.music.reconcile(value);updateDownloads()} catch {if !AgendaOfflineCache.isUnavailable(error) {self.error=error.localizedDescription};if library==nil {library=store.client.cachedMusic()};updateDownloads()}
    }
    private func updateDownloads() {downloaded=Set((library?.tracks ?? []).filter{store.client.musicHasDownload($0)}.map(\.id))}
    private func download(_ tracks:[MusicTrack]) {
        guard downloadTask==nil else{return};downloadTask=Task {defer{downloadTask=nil;downloadProgress=nil;updateDownloads()};do {for (index,track) in tracks.enumerated(){try Task.checkCancellation();downloadProgress="\(index+1)/\(tracks.count) · \(track.title)";try await store.client.downloadMusic(track){value in downloadProgress="\(index+1)/\(tracks.count) · \(Int(value*100))%"}};notice=tracks.count==1 ? "Audio disponible sin conexión.":"Sección disponible sin conexión."} catch {if !(error is CancellationError) {self.error=error.localizedDescription}}}
    }
    private func remove(_ track:MusicTrack) async {do{try await store.client.deleteMusic(track);if store.music.current?.id==track.id {store.music.stop()};deleting=nil;await load()}catch{self.error=error.localizedDescription}}
}

struct MusicImportView: View {
    let incoming: MusicIncomingAudio
    let initialSection: MusicSection
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.dismiss) private var dismiss
    @State private var section: MusicSection = .warmup
    @State private var busy = false
    @State private var locked = false
    @State private var completed: Set<String> = []
    @State private var progress = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {Text("Elige dónde guardar los audios. Se subirán a la biblioteca privada del equipo.").foregroundStyle(.secondary)}
                Section("Destino") {Picker("Sección",selection:$section){ForEach(MusicSection.allCases){Text($0.title).tag($0)}}.disabled(busy||locked)}
                Section("Audios") {ForEach(incoming.files){file in HStack{Text(file.name);Spacer();if completed.contains(file.id){Image(systemName:"checkmark.circle.fill").foregroundStyle(.teal)}}}}
                if let error {Section{InlineError(message:error)}}
                if busy {Section{ProgressView();Text(progress).font(.caption)}}
                Section {Button(busy ? "Subiendo…":"Subir audios"){Task{await upload()}}.disabled(busy || store.overview?.user.canUploadMusic != true || store.isOffline).accessibilityIdentifier("music.import.confirm")}
            }.navigationTitle("Agregar a Música").toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancelar"){dismiss()}.disabled(busy)}}
        }.interactiveDismissDisabled(busy).onAppear{section=initialSection}.onDisappear{incoming.files.forEach{$0.remove()}}
        #if os(macOS)
        .frame(minWidth:520,minHeight:460)
        #endif
    }
    private func upload() async {
        guard store.overview?.user.canUploadMusic == true else {error="Tu cuenta no puede subir audios.";return}
        busy=true;locked=true;error=nil;defer{busy=false}
        do {for file in incoming.files where !completed.contains(file.id){progress=file.name;try await store.client.uploadMusic(file,section:section){value in progress=file.name+" · \(Int(value*100))%"};completed.insert(file.id)};dismiss()} catch {self.error=error.localizedDescription+" Puedes reintentar los audios pendientes."}
    }
}
