#if os(iOS)
import SwiftUI

struct MediaFullscreenPhotoView:View {
    @StateObject private var photos:MediaFullscreenPhotoModel
    @EnvironmentObject private var store:PayrollStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    private let client:PayrollClient
    private let stamp:String?
    private let canDelete:Bool

    init(selected:MediaItem,feed:MediaFeed,client:PayrollClient,denied:@escaping(Error)->Void) {
        self.client=client;self.canDelete=feed.canDelete == true
        let expected=try? client.mediaAccessStamp();stamp=expected
        _photos=StateObject(wrappedValue:MediaFullscreenPhotoModel(selected:selected,items:feed.items,token:feed.nextPageToken ?? "",folderID:feed.folder?.id ?? "",collectionID:feed.collectionID,load:{try await client.mediaPhotoPreview($0,progress:$1)},validate:{try await client.validateMediaItem($0)},page:{try await client.media(folder:feed.folder?.id ?? "",pageToken:$0)},isCurrent:{expected != nil && expected == (try? client.mediaAccessStamp())},denied:denied))
    }
    var body:some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MediaFullscreenPhotoPager(items:photos.items,selectedID:photos.selectedID,documents:photos.urls,progress:photos.progress,errors:photos.errors,active:phase == .active,select:photos.select,retry:photos.retry)
                .ignoresSafeArea().accessibilityIdentifier("media.fullscreen")
        }
        .safeAreaInset(edge:.top,spacing:0) {
            HStack {
                if let item=photos.selected {MediaPhotoMenu(item:item,client:client,canDelete:canDelete && store.overview?.user.canDeleteMedia == true).id(item.id)}
                Spacer()
                Button {photos.stop();dismiss()} label:{Image(systemName:"xmark").font(.body.weight(.semibold)).foregroundStyle(.white).frame(width:44,height:44).background(.black.opacity(0.45),in:Circle())}
                    .accessibilityLabel("Listo").accessibilityIdentifier("media.preview.close")
            }.padding(.horizontal,16).padding(.top,4).padding(.bottom,8).background(.black.opacity(0.15))
        }
        .safeAreaInset(edge:.bottom,spacing:0) {
            VStack(spacing:4) {
                if photos.paging {ProgressView("Consultando más fotos…").font(.caption).tint(.white).foregroundStyle(.white)}
                if let error=photos.pageError {HStack {Text(error).font(.caption);Button("Reintentar"){photos.retryPage()}}.foregroundStyle(.white).multilineTextAlignment(.center).padding(.horizontal,16)}
                HStack(spacing:14) {
                    Button {photos.move(-1)} label:{Image(systemName:"chevron.left").frame(width:44,height:44).contentShape(Rectangle())}.disabled(!photos.canPrevious).accessibilityLabel("Foto anterior").accessibilityIdentifier("media.preview.previous")
                    Spacer(minLength:0)
                    VStack(spacing:4) {
                        Text(photos.selected?.name ?? "Foto").font(.caption).lineLimit(1).accessibilityIdentifier("media.preview.name")
                        Text(photos.counter).font(.caption2).monospacedDigit().accessibilityIdentifier("media.preview.counter")
                    }
                    Spacer(minLength:0)
                    Button {photos.move(1)} label:{Image(systemName:"chevron.right").frame(width:44,height:44).contentShape(Rectangle())}.disabled(!photos.canNext).accessibilityLabel("Foto siguiente").accessibilityIdentifier("media.preview.next")
                }.buttonStyle(.plain).foregroundStyle(.white).padding(.horizontal,16).padding(.bottom,4)
            }.background(.black.opacity(0.55))
        }
        .statusBarHidden().privacySensitive().preferredColorScheme(.dark)
        .task {
            photos.start()
            while !Task.isCancelled {
                do {try await Task.sleep(for:.seconds(15))}catch{return}
                if phase == .active {photos.refreshAuthorization()}
            }
        }
        .onChange(of:phase) {_,value in if value == .active {photos.refreshAuthorization()}}
        .onChange(of:try? client.mediaAccessStamp()) {_,value in if value != stamp {photos.stop();dismiss()}}
        .onReceive(client.$cacheRevision) {_ in if let id=photos.selected?.id,let scope=try? client.mediaScope(),client.mediaOffline.isDeleted(id,scope:scope) {photos.stop();dismiss()}}
        .onChange(of:store.overview?.user.canReadMedia) {_,value in if value != true {photos.stop();dismiss()}}
        .onDisappear {photos.stop()}
    }
}
#endif
