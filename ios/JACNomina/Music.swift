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
    #if os(iOS)
    @State private var expanded = false
    #endif
    var body: some View {
        if let track=player.current {
            #if os(iOS)
            mobilePlayer(track)
                .sheet(isPresented:$expanded) { playbackDetails }
            #else
            legacyPlayer(track)
            #endif
        }
    }
    #if os(iOS)
    private func mobilePlayer(_ track: MusicTrack) -> some View {
        VStack(spacing:0) {
            VStack(alignment:.leading,spacing:6) {
                HStack(spacing:8) {
                    Button {expanded=true} label:{
                        HStack(spacing:10) {
                            Image(systemName:"waveform").font(.system(size:20,weight:.medium))
                                .foregroundStyle(JACTheme.highlight).frame(width:40,height:40)
                                .background(.white.opacity(0.09),in:RoundedRectangle(cornerRadius:10))
                            VStack(alignment:.leading,spacing:4) {
                                Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(track.section.title+" · "+Self.time(player.elapsed)+" / "+Self.time(player.duration))
                                    .font(.caption2).foregroundStyle(Color.white.opacity(0.76)).lineLimit(1).monospacedDigit()
                            }.frame(maxWidth:.infinity,alignment:.leading)
                        }.frame(minHeight:44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Abrir reproductor: "+track.title)
                    if player.preparing {ProgressView().tint(.white).controlSize(.small).accessibilityLabel("Preparando audio")}
                    Button {player.toggle()} label:{Image(systemName:player.playing ? "pause.fill":"play.fill").font(.system(size:20,weight:.medium)).frame(width:44,height:44)}
                        .accessibilityLabel(player.playing ? "Pausar música":"Reproducir música").accessibilityIdentifier("music.player.toggle")
                    Button {player.next()} label:{Image(systemName:"forward.end.fill").font(.system(size:19,weight:.medium)).frame(width:44,height:44)}.accessibilityLabel("Siguiente audio")
                }.buttonStyle(.plain)
                if let error=player.error {Text(error).font(.caption).foregroundStyle(Color(red:1,green:0.79,blue:0.73)).fixedSize(horizontal:false,vertical:true)}
            }.padding(.horizontal,12).padding(.vertical,10)
            GeometryReader { geometry in
                ZStack(alignment:.leading) {
                    Rectangle().fill(.white.opacity(0.18))
                    Rectangle().fill(JACTheme.highlight).frame(width:geometry.size.width * CGFloat(min(1,max(0,player.duration > 0 ? player.elapsed/player.duration:0))))
                }
            }.frame(height:3).accessibilityHidden(true)
        }.foregroundStyle(.white)
            .background(JACTheme.navy,in:RoundedRectangle(cornerRadius:17))
            .clipShape(RoundedRectangle(cornerRadius:17))
            .contextMenu {
                Button {expanded=true} label:{Label("Abrir reproductor",systemImage:"waveform")}
                Button {player.previous()} label:{Label("Audio anterior",systemImage:"backward.end")}
                Button {player.stop()} label:{Label("Cerrar reproductor",systemImage:"xmark")}
            }
            .padding(.horizontal,14).padding(.vertical,8)
            .background(JACTheme.canvas)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("music.player")
    }
    private var playbackDetails: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing:24) {
                    if let track=player.current {
                        Image(systemName:"waveform").font(.system(size:48,weight:.light)).foregroundStyle(JACTheme.action)
                            .frame(width:128,height:128).background(JACTheme.action.opacity(0.08),in:RoundedRectangle(cornerRadius:26)).accessibilityHidden(true)
                        VStack(spacing:8) {
                            Text(track.title).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                            Text(track.section.title).font(.subheadline).foregroundStyle(.secondary)
                        }
                        timeline
                        HStack(spacing:28) {
                            Button {player.previous()} label:{Image(systemName:"backward.end.fill").font(.title2).frame(width:48,height:48)}.accessibilityLabel("Audio anterior")
                            Button {player.toggle()} label:{Image(systemName:player.playing ? "pause.fill":"play.fill").font(.title).frame(width:68,height:68).foregroundStyle(.white).background(JACTheme.primary,in:Circle())}.accessibilityLabel(player.playing ? "Pausar música":"Reproducir música")
                            Button {player.next()} label:{Image(systemName:"forward.end.fill").font(.title2).frame(width:48,height:48)}.accessibilityLabel("Siguiente audio")
                        }.buttonStyle(.plain)
                        if player.preparing {ProgressView("Preparando audio…")}
                        if let error=player.error {InlineError(message:error)}
                        Button {player.stop();expanded=false} label:{Label("Cerrar reproductor",systemImage:"xmark.circle").frame(minHeight:44)}.foregroundStyle(.secondary)
                    }
                }.padding(24).frame(maxWidth:.infinity)
            }.jacSurface()
                .navigationTitle("Reproduciendo").navigationBarTitleDisplayMode(.inline)
                .toolbar {ToolbarItem(placement:.confirmationAction){Button("Listo"){expanded=false}}}
        }.presentationDetents([.medium,.large]).presentationDragIndicator(.visible)
    }
    #endif
    private var timeline: some View {
        HStack(spacing:8) {
            Text(Self.time(scrubbing ? scrubValue:player.elapsed)).monospacedDigit().font(.caption2).foregroundStyle(.secondary)
            Slider(value:Binding(get:{scrubbing ? scrubValue:player.elapsed},set:{scrubValue=$0}),in:0...max(1,player.duration),onEditingChanged:{editing in if editing {scrubValue=player.elapsed;scrubbing=true} else {player.seek(scrubValue);scrubbing=false}}).accessibilityLabel("Posición del audio")
            Text(Self.time(player.duration)).monospacedDigit().font(.caption2).foregroundStyle(.secondary)
        }
    }
    #if os(macOS)
    private func legacyPlayer(_ track: MusicTrack) -> some View {
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
            timeline
            if let error=player.error {Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)}
        }.padding(.horizontal,16).padding(.vertical,10).background(.bar).overlay(alignment:.top){Divider()}.accessibilityIdentifier("music.player")
    }
    #endif
    private static func time(_ value: Double) -> String {guard value.isFinite,value>=0 else{return "0:00"};return String(format:"%d:%02d",Int(value)/60,Int(value)%60)}
}

struct MusicLibraryView: View {
    let user: PayrollUser
    @EnvironmentObject private var store: PayrollStore
    @Environment(\.isWorkspaceActive) private var isWorkspaceActive
    @Environment(\.scenePhase) private var phase
    @Environment(\.jacWorkspaceLayout) private var layout
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
    #if os(iOS)
    @State private var downloadedOnly = false
    #endif
    private var tracks: [MusicTrack] { MusicTrack.sorted((library?.tracks ?? []).filter{(section == nil || $0.section == section) && $0.matches(search) && includesDownload($0)}) }
    var body: some View {
        titledContent
            .jacSearchable(text:$search,prompt:section == nil ? "Buscar en toda Música":"Buscar en esta sección")
            .toolbar {
                if section != nil && !layout.isWide {ToolbarItem(placement:.cancellationAction){Button {section=nil;search=""} label:{Label("Música",systemImage:"chevron.left")}}}
                if user.canUploadMusic {ToolbarItem(placement:.primaryAction){importButton}}
                #if os(macOS)
                ToolbarItem {Button {Task{await load()}} label:{Image(systemName:"arrow.clockwise")}.disabled(loading).accessibilityLabel("Actualizar Música")}
                #endif
            }
            .fileImporter(isPresented:$picker,allowedContentTypes:[.audio],allowsMultipleSelection:true) {result in
                do {let urls=try result.get();Task {await prepare(urls)}} catch {self.error=error.localizedDescription}
            }
            .sheet(item:$importing,onDismiss:{Task{await load()}}){incoming in MusicImportView(incoming:incoming,initialSection:section ?? .warmup).environmentObject(store)}
            .confirmationDialog("Eliminar audio",isPresented:Binding(get:{deleting != nil},set:{if !$0 {deleting=nil}}),titleVisibility:.visible) {
                if let track=deleting {Button("Eliminar «\(track.title)»",role:.destructive){Task{await remove(track)}}}
            } message:{Text("Dejará de estar disponible para el equipo.")}
            .task(id: isWorkspaceActive && phase == .active) {
                guard isWorkspaceActive, phase == .active else { return }
                if library == nil { library = store.client.cachedMusic() }
                updateDownloads(); await load()
            }
            .onDisappear {downloadTask?.cancel()}
    }
    @ViewBuilder private var titledContent: some View {
        #if os(iOS)
        if layout.isWide {wideLibrary.jacSurface().jacWorkspaceTitle("Música")}
        else if section == nil {mobileLibrary.jacSurface().jacWorkspaceTitle("Música")}
        else {mobileLibrary.jacSurface().navigationTitle(section!.title).jacInlineTitle()}
        #else
        legacyLibrary.jacSurface().navigationTitle(section?.title ?? "Música").jacInlineTitle()
        #endif
    }
    @ViewBuilder private var importButton: some View {
        #if os(iOS)
        Button {picker=true} label:{
            Image(systemName:"plus").font(.system(size:20,weight:.medium)).frame(width:44,height:44)
                .foregroundStyle(.white).background(JACTheme.primary,in:RoundedRectangle(cornerRadius:14))
        }.buttonStyle(.plain).disabled(store.isOffline).accessibilityLabel("Subir audios").accessibilityIdentifier("music.import")
        #else
        Button {picker=true} label:{Label("Subir audios",systemImage:"plus")}.disabled(store.isOffline).accessibilityIdentifier("music.import")
        #endif
    }
    private func includesDownload(_ track: MusicTrack) -> Bool {
        #if os(iOS)
        !downloadedOnly || downloaded.contains(track.id)
        #else
        true
        #endif
    }
    #if os(iOS)
    private var wideLibrary: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tu biblioteca").font(.headline)
                        ForEach(MusicSection.allCases) { item in
                            playlistRow(item).padding(.horizontal, 10)
                                .background(section == item ? JACTheme.action.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 14))
                                .id(item.id)
                        }
                    }.padding(16)
                }
                .accessibilityIdentifier("music.playlists")
                .onAppear { if let section { proxy.scrollTo(section.id, anchor: .center) } }
                .onChange(of: section) { _, value in if let value { proxy.scrollTo(value.id, anchor: .center) } }
            }.frame(width: min(290, layout.contentWidth * 0.36))
            Rectangle().fill(JACTheme.border).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let error { InlineError(message: error) }
                    if let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        Text(section?.title ?? "Todos los audios").font(.title2.bold())
                        Spacer(); libraryOptions
                    }
                    if let downloadProgress {
                        HStack { ProgressView(); Text(downloadProgress).font(.caption); Button("Cancelar") { downloadTask?.cancel() } }
                    }
                    HStack(spacing: 14) {
                        Button { if let first = tracks.first { store.music.play(first, queue: tracks) } } label: { Label("Reproducir", systemImage: "play.fill") }
                            .buttonStyle(.borderedProminent).disabled(tracks.isEmpty).accessibilityIdentifier("music.wide.play")
                        Button { download(tracks) } label: { Image(systemName: "arrow.down.circle").frame(width: 44, height: 44) }
                            .disabled(tracks.isEmpty || downloadTask != nil || store.isOffline)
                            .accessibilityLabel("Descargar audios sin conexión").accessibilityIdentifier("music.download.section")
                    }
                    LazyVStack(spacing: 0) {
                        ForEach(tracks) { track in row(track); Divider().overlay(JACTheme.border) }
                    }
                    if tracks.isEmpty && !loading { ContentUnavailableView("No hay audios", systemImage: "music.note", description: Text("Elige otra playlist o cambia la búsqueda.")) }
                    if loading && library == nil { ProgressView("Cargando Música…") }
                }.padding(18)
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("phone.music.columns").refreshable { await load() }
    }
    private var recentlyAdded: [MusicTrack] {
        Array((library?.tracks ?? []).sorted {a,b in a.createdAt == b.createdAt ? a.id < b.id:a.createdAt > b.createdAt}.prefix(2))
    }
    private var mobileLibrary: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                if let error {InlineError(message:error)}
                if let notice {Text(notice).font(.subheadline).foregroundStyle(.secondary)}
                if let downloadProgress {
                    HStack(spacing:10) {
                        ProgressView().controlSize(.small)
                        Text(downloadProgress).font(.caption).frame(maxWidth:.infinity,alignment:.leading)
                        Button("Cancelar"){downloadTask?.cancel()}.frame(minHeight:44)
                    }.padding(12).background(JACTheme.card,in:RoundedRectangle(cornerRadius:14))
                }
                if section == nil && search.isEmpty && !downloadedOnly {
                    HStack {
                        Text("Tu biblioteca").font(.headline)
                        Spacer()
                        libraryOptions
                    }
                    VStack(spacing:0) {
                        ForEach(MusicSection.allCases) {item in
                            playlistRow(item)
                            if item != MusicSection.allCases.last {Divider().overlay(JACTheme.border)}
                        }
                    }
                    if !recentlyAdded.isEmpty {
                        VStack(alignment:.leading,spacing:8) {
                            Text("Agregados recientemente").font(.headline)
                            VStack(spacing:0) {
                                ForEach(recentlyAdded) {track in
                                    row(track)
                                    if track.id != recentlyAdded.last?.id {Divider().overlay(JACTheme.border)}
                                }
                            }
                        }.padding(.top,2)
                    }
                } else {
                    HStack(alignment:.center) {
                        Text(downloadedOnly ? "Descargados":section?.title ?? "Resultados en Música").font(.headline)
                        Spacer()
                        libraryOptions
                    }
                    if let section, let library, !library.tracks.filter({$0.section==section}).isEmpty {
                        Button {download(library.tracks.filter{$0.section==section})} label:{
                            Label("Descargar sección sin conexión",systemImage:"arrow.down.circle").font(.subheadline.weight(.medium)).frame(minHeight:44)
                        }.disabled(downloadTask != nil || store.isOffline).accessibilityIdentifier("music.download.section")
                    }
                    LazyVStack(spacing:0) {
                        ForEach(tracks) {track in
                            row(track)
                            if track.id != tracks.last?.id {Divider().overlay(JACTheme.border)}
                        }
                    }
                    if tracks.isEmpty && !loading {
                        ContentUnavailableView(downloadedOnly ? "Sin audios descargados":search.isEmpty ? "Aún no hay audios":"No encontramos ese audio",systemImage:downloadedOnly ? "arrow.down.circle":"headphones",description:Text(downloadedOnly ? "Descarga un audio o una sección para escuchar sin conexión.":search.isEmpty ? "Los audios aparecerán cuando el equipo los suba.":"Prueba con otro nombre."))
                    }
                }
                if loading && library == nil {ProgressView("Cargando Música…").frame(maxWidth:.infinity).padding(.vertical,20)}
            }.padding(.horizontal,20).padding(.top,8).padding(.bottom,20)
        }.refreshable {await load()}
    }
    private var libraryOptions: some View {
        Menu {
            Button {downloadedOnly.toggle()} label:{Label(downloadedOnly ? "Ver todos los audios":"Ver audios descargados",systemImage:downloadedOnly ? "music.note.list":"arrow.down.circle")}
            Button {Task{await load()}} label:{Label("Actualizar Música",systemImage:"arrow.clockwise")}.disabled(loading)
        } label:{Image(systemName:downloadedOnly ? "arrow.down.circle.fill":"arrow.down.to.line").font(.system(size:19,weight:.medium)).frame(width:44,height:44).contentShape(Rectangle())}
            .accessibilityLabel("Descargas y opciones de Música")
    }
    private func playlistRow(_ item: MusicSection) -> some View {
        let list=library?.tracks.filter{$0.section==item} ?? []
        let available = !list.isEmpty && list.allSatisfy{downloaded.contains($0.id)}
        return Button {section=item;search="";downloadedOnly=false} label:{
            HStack(spacing:13) {
                Image(systemName:playlistIcon(item)).font(.system(size:23,weight:.regular)).foregroundStyle(playlistTint(item))
                    .frame(width:52,height:52).background(playlistTint(item).opacity(0.09),in:RoundedRectangle(cornerRadius:13))
                VStack(alignment:.leading,spacing:5) {
                    Text(item.title).font(.system(.body,weight:.semibold)).foregroundStyle(JACTheme.ink)
                    Text("\(list.count) audios"+(available ? " · Sin conexión":"")).font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,alignment:.leading)
                if available {Image(systemName:"checkmark.circle").font(.subheadline).foregroundStyle(.teal).accessibilityLabel("Disponible sin conexión")}
                Image(systemName:"chevron.right").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }.padding(.vertical,13).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("music.section."+item.rawValue)
    }
    private func playlistIcon(_ section: MusicSection) -> String {
        switch section {case .warmup:"mic";case .tracks:"opticaldisc";case .demos:"square.and.pencil";case .studio:"waveform"}
    }
    private func playlistTint(_ section: MusicSection) -> Color {
        switch section {
        case .warmup,.tracks:JACTheme.action
        case .demos:JACAdaptiveColor(light:(0.30,0.36,0.53),dark:(0.66,0.72,0.91))
        case .studio:JACAdaptiveColor(light:(0.22,0.45,0.48),dark:(0.53,0.79,0.81))
        }
    }
    #endif
    #if os(macOS)
    private var legacyLibrary: some View {
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
        }
    }
    #endif
    @ViewBuilder private func row(_ track: MusicTrack) -> some View {
        #if os(iOS)
        mobileTrackRow(track)
        #else
        legacyTrackRow(track)
        #endif
    }
    #if os(iOS)
    private func mobileTrackRow(_ track: MusicTrack) -> some View {
        HStack(spacing:10) {
            Button {store.music.play(track,queue:tracks)} label:{
                HStack(spacing:12) {
                    Image(systemName:"music.note").font(.system(size:17,weight:.medium)).foregroundStyle(JACTheme.action).frame(width:40,height:40)
                        .background(JACTheme.action.opacity(0.08),in:RoundedRectangle(cornerRadius:10))
                    VStack(alignment:.leading,spacing:5) {
                        Text(track.title).font(.body.weight(.medium)).foregroundStyle(JACTheme.ink).lineLimit(2)
                        Text((section == nil ? track.section.title+" · ":"")+track.filename.components(separatedBy:".").last!.uppercased()+" · "+track.sizeLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength:4)
                }.frame(minHeight:44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("music.track."+track.id)
            if downloaded.contains(track.id) {Image(systemName:"checkmark.circle.fill").foregroundStyle(.teal).accessibilityLabel("Disponible sin conexión")}
            Menu {
                Button {store.music.play(track,queue:tracks)} label:{Label("Reproducir",systemImage:"play")}
                if downloaded.contains(track.id) {Button {do {if store.music.current?.id==track.id {store.music.stop()};try store.client.forgetMusic(track);updateDownloads()} catch {self.error=error.localizedDescription}} label:{Label("Quitar descarga de este dispositivo",systemImage:"arrow.down.circle")}}
                else {Button {download([track])} label:{Label("Descargar sin conexión",systemImage:"arrow.down.circle")}.disabled(downloadTask != nil || store.isOffline)}
                if library?.canDelete == true {Button(role:.destructive){deleting=track} label:{Label("Eliminar audio",systemImage:"trash")}}
            } label:{Image(systemName:"ellipsis").frame(width:44,height:44).contentShape(Rectangle())}.accessibilityLabel("Opciones de "+track.title)
        }.padding(.vertical,8)
    }
    #endif
    #if os(macOS)
    private func legacyTrackRow(_ track: MusicTrack) -> some View {
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
    #endif
    private func prepare(_ urls:[URL]) async {
        do {let files=try await Task.detached(priority:.userInitiated){var files:[MusicImportFile]=[];do {for url in urls {files.append(try MusicImportFile.copy(url))};return files} catch {files.forEach{$0.remove()};throw error}}.value;importing=MusicIncomingAudio(files:files)} catch {self.error=error.localizedDescription}
    }
    private func load() async {
        guard isWorkspaceActive, phase == .active, !Task.isCancelled, !loading else{return};loading=true;defer{loading=false};error=nil
        do {let value=try await store.client.musicLibrary();try Task.checkCancellation();library=value;store.music.reconcile(value);updateDownloads()} catch {guard !Task.isCancelled else{return};if !AgendaOfflineCache.isUnavailable(error) {self.error=error.localizedDescription};if library==nil {library=store.client.cachedMusic()};updateDownloads()}
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
