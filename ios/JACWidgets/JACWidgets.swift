import SwiftUI
import WidgetKit
import AppIntents
import ImageIO

enum JACWidgetMode: String, AppEnum {
    case calendar
    case photography
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Contenido"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .calendar: "Calendario",
        .photography: "Fotografía"
    ]
}
struct JACWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Contenido de JAC"
    static var description = IntentDescription("Elige entre tu calendario y las últimas fotografías disponibles.")
    @Parameter(title: "Mostrar", default: JACWidgetMode.calendar)
    var content: JACWidgetMode
}
private struct JACWidgetEntry: TimelineEntry {
    let date: Date
    let configuration: JACWidgetConfiguration
    let snapshot: JACWidgetSnapshot?
    let images: [String: CGImage]
    var preview = false
}
private struct JACWidgetProvider: AppIntentTimelineProvider {
    typealias Intent = JACWidgetConfiguration
    typealias Entry = JACWidgetEntry
    func placeholder(in context: Context) -> JACWidgetEntry {
        preview(configuration: JACWidgetConfiguration())
    }
    func snapshot(for configuration: JACWidgetConfiguration, in context: Context) async -> JACWidgetEntry {
        if context.isPreview { return preview(configuration: configuration) }
        let now = Date(), saved = await JACWidgetSnapshotStore().read()
        let images = await decodeImages(saved)
        return JACWidgetEntry(date: now, configuration: configuration, snapshot: saved, images: images)
    }
    func timeline(for configuration: JACWidgetConfiguration, in context: Context) async -> Timeline<JACWidgetEntry> {
        let now = Date(), saved = await JACWidgetSnapshotStore().read(now: now)
        let images = await decodeImages(saved)
        let horizon = now.addingTimeInterval(24 * 60 * 60)
        var changes = Set<Date>([now])
        if let midnight = JACWidgetClock.calendar.date(byAdding: .day, value: 1, to: JACWidgetClock.calendar.startOfDay(for: now)) { changes.insert(midnight) }
        for expiry in [saved?.calendar?.expiresAt, saved?.photography?.expiresAt].compactMap({ $0 }) where expiry > now && expiry <= horizon {
            changes.insert(expiry.addingTimeInterval(1))
        }
        // Reserve midnight and expiry even on very busy days. iOS can delay a
        // reload, so those transitions cannot depend on another network turn.
        var eventChanges = Set<Date>()
        for event in saved?.calendar?.events ?? [] {
            for time in [event.start, event.end] where time > now && time < horizon && !changes.contains(time) { eventChanges.insert(time) }
        }
        for time in eventChanges.sorted().prefix(max(0, 24 - changes.count)) { changes.insert(time) }
        let entries = changes.sorted().map { date in
            JACWidgetEntry(date: date, configuration: configuration, snapshot: valid(saved, at: date), images: images)
        }
        // WidgetKit grants refresh opportunities. Reading a timeline never
        // launches a network request or obtains the app's session credentials.
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60)))
    }
    private func valid(_ snapshot: JACWidgetSnapshot?, at date: Date) -> JACWidgetSnapshot? {
        guard var snapshot else { return nil }
        if let content = snapshot.calendar, content.expiresAt <= date { snapshot.calendar = nil }
        if let content = snapshot.photography, content.expiresAt <= date { snapshot.photography = nil }
        return snapshot
    }
    private func decodeImages(_ snapshot: JACWidgetSnapshot?) async -> [String: CGImage] {
        let photographs = snapshot?.photography?.photos ?? []
        return await Task.detached(priority: .utility) {
            var images: [String: CGImage] = [:]
            for photo in photographs.prefix(4) {
                guard photo.imageData.count <= JACWidgetShared.maximumImageBytes,
                      let source = CGImageSourceCreateWithData(photo.imageData as CFData, nil),
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                      let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
                      width.int64Value > 0, height.int64Value > 0,
                      width.int64Value <= 4000, height.int64Value <= 4000,
                      width.int64Value * height.int64Value <= 4_000_000,
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceShouldCacheImmediately: true,
                        kCGImageSourceThumbnailMaxPixelSize: 512
                      ] as CFDictionary) else { continue }
                images[photo.id] = image
            }
            return images
        }.value
    }
    private func preview(configuration: JACWidgetConfiguration) -> JACWidgetEntry {
        let now = Date(), event = JACWidgetEvent(id: "widget-preview", title: "Próximo evento", start: now.addingTimeInterval(7200), end: now.addingTimeInterval(10800), allDay: false)
        let calendar = JACWidgetCalendarContent(updatedAt: now, expiresAt: now.addingTimeInterval(86400), events: [event])
        return JACWidgetEntry(date: now, configuration: configuration, snapshot: JACWidgetSnapshot(owner: String(repeating: "0", count: 64), calendar: calendar), images: [:], preview: true)
    }
}

@main
struct JACWidgets: WidgetBundle {
    var body: some Widget { JACHomeWidget() }
}
private struct JACHomeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: JACWidgetShared.kind, intent: JACWidgetConfiguration.self, provider: JACWidgetProvider()) { entry in
            JACWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("JAC")
        .description("Tu calendario o las últimas fotografías de JAC.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
private struct JACWidgetView: View {
    let entry: JACWidgetEntry
    var body: some View {
        Group {
            switch entry.configuration.content {
            case .calendar: JACCalendarWidgetView(entry: entry)
            case .photography: JACPhotographyWidgetView(entry: entry)
            }
        }.padding(12).privacySensitive()
    }
}
private enum JACWidgetClock {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!
        calendar.locale = Locale(identifier: "es_CO"); calendar.firstWeekday = 2
        return calendar
    }()
    static func label(_ date: Date, _ format: String) -> String {
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.locale = calendar.locale
        formatter.timeZone = calendar.timeZone; formatter.dateFormat = format
        return formatter.string(from: date)
    }
    static func days(_ date: Date) -> [Date] {
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        let offset = (calendar.component(.weekday, from: first) + 5) % 7
        let beginning = calendar.date(byAdding: .day, value: -offset, to: first)!
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: beginning) }
    }
    static func upcoming(_ events: [JACWidgetEvent], at date: Date) -> [JACWidgetEvent] {
        events.filter { $0.end > date }.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }
}
private struct JACCalendarWidgetView: View {
    let entry: JACWidgetEntry
    @Environment(\.widgetFamily) private var family
    private var content: JACWidgetCalendarContent? { entry.snapshot?.calendar }
    var body: some View {
        Group {
            if let content {
                if family == .systemSmall {
                    JACWidgetMonth(date: entry.date, events: content.events, compact: true)
                } else if family == .systemMedium {
                    HStack(alignment: .top, spacing: 14) {
                        JACWidgetMonth(date: entry.date, events: content.events, compact: true).frame(width: 144)
                        JACWidgetUpcoming(date: entry.date, content: content, count: 2)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        JACWidgetMonth(date: entry.date, events: content.events, compact: false)
                        Divider()
                        JACWidgetUpcoming(date: entry.date, content: content, count: 3, compact: true)
                    }
                }
            } else {
                JACWidgetEmpty(symbol: "calendar", title: "Tu calendario JAC", message: "Abre JAC para actualizar la agenda.")
            }
        }.widgetURL(JACWidgetRoute.calendar.url)
    }
}
private struct JACWidgetMonth: View {
    let date: Date
    let events: [JACWidgetEvent]
    let compact: Bool
    private var days: [Date] { JACWidgetClock.days(date) }
    var body: some View {
        VStack(spacing: compact ? 4 : 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(JACWidgetClock.label(date, "MMMM").capitalized).font(compact ? .caption.weight(.bold) : .headline)
                Spacer(minLength: 2)
                Text("JAC").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.blue)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 3) {
                ForEach(Array(["L", "M", "X", "J", "V", "S", "D"].enumerated()), id: \.offset) { _, name in
                    Text(name).font(.system(size: compact ? 8 : 10, weight: .semibold)).foregroundStyle(.secondary)
                }
                ForEach(days, id: \.self) { day in dayCell(day) }
            }
        }
    }
    private func dayCell(_ day: Date) -> some View {
        let calendar = JACWidgetClock.calendar
        let today = calendar.isDate(day, inSameDayAs: date)
        let currentMonth = calendar.isDate(day, equalTo: date, toGranularity: .month)
        let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let hasEvent = events.contains { $0.start < next && $0.end > day }
        return Text(String(calendar.component(.day, from: day)))
            .font(.system(size: compact ? 10 : 12, weight: today ? .bold : .medium)).monospacedDigit()
            .frame(maxWidth: .infinity).frame(height: compact ? 13 : 17)
            .foregroundStyle(today ? Color.white : currentMonth ? Color.primary : Color.secondary.opacity(0.5))
            .background { if today { Circle().fill(Color.blue) } }
            .overlay(alignment: .bottom) { if hasEvent && !today { Circle().fill(Color.blue).frame(width: 2, height: 2).offset(y: 2) } }
            .accessibilityLabel(JACWidgetClock.label(day, "d 'de' MMMM") + (hasEvent ? ", con eventos" : ""))
    }
}
private struct JACWidgetUpcoming: View {
    let date: Date
    let content: JACWidgetCalendarContent
    let count: Int
    var compact = false
    private var events: [JACWidgetEvent] { Array(JACWidgetClock.upcoming(content.events, at: date).prefix(count)) }
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            Text("Próximos eventos").font(.caption.weight(.bold)).lineLimit(1).minimumScaleFactor(0.8)
            if events.isEmpty {
                Text("No hay eventos próximos.").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ForEach(events, id: \.id) { event in
                    HStack(alignment: .top, spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.blue).frame(width: 3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title).font(.system(size: 11, weight: .semibold)).lineLimit(compact ? 1 : 2)
                            Text(event.allDay ? JACWidgetClock.label(event.start, "d MMM") + " · Todo el día" : JACWidgetClock.label(event.start, "d MMM · HH:mm"))
                                .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            JACWidgetUpdated(date: content.updatedAt)
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
private struct JACPhotographyWidgetView: View {
    let entry: JACWidgetEntry
    @Environment(\.widgetFamily) private var family
    private var content: JACWidgetPhotographyContent? { entry.snapshot?.photography }
    private var photos: [JACWidgetPhoto] {
        Array((content?.photos ?? []).prefix(family == .systemSmall ? 1 : family == .systemMedium ? 2 : 4))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Fotografía", systemImage: "photo").font(.caption.weight(.bold))
                Spacer(minLength: 0)
                Text("JAC").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.blue)
            }
            if !photos.isEmpty {
                photoGrid
                if family != .systemSmall, let content { JACWidgetUpdated(date: content.updatedAt) }
            } else {
                JACWidgetEmpty(symbol: "photo.on.rectangle", title: "Últimas fotografías", message: content != nil ? "No hay fotos disponibles." : "Abre JAC para actualizar las fotos.")
            }
        }.widgetURL(JACWidgetRoute.photography(folderID: photos.first?.folderID).url)
    }
    private var photoGrid: some View {
        GeometryReader { geometry in
            let columns = family == .systemSmall ? 1 : 2
            let rows = family == .systemLarge && photos.count > 2 ? 2 : 1
            let height = max(1, (geometry.size.height - CGFloat(rows - 1) * 6) / CGFloat(rows))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
                ForEach(photos, id: \.id) { photo in
                    Link(destination: JACWidgetRoute.photography(folderID: photo.folderID).url) {
                        Group {
                            if let image = entry.images[photo.id] {
                                Image(decorative: image, scale: 1).resizable().scaledToFill()
                            } else { Color.blue.opacity(0.08).overlay { Image(systemName: "photo").foregroundStyle(.secondary) } }
                        }.frame(maxWidth: .infinity).frame(height: height).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .accessibilityLabel("Fotografía reciente. Abrir carpeta en JAC.")
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}
private struct JACWidgetUpdated: View {
    let date: Date
    var body: some View {
        HStack(spacing: 3) {
            Text("Actualizado")
            Text(date, style: .relative)
        }.font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
    }
}
private struct JACWidgetEmpty: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol).font(.title2).foregroundStyle(Color.blue)
            Text(title).font(.caption.weight(.semibold))
            Text(message).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
