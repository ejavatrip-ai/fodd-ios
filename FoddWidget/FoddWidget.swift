import SwiftUI
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit
#endif

struct FoddWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: FoddWidgetSnapshot
}

struct FoddWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FoddWidgetEntry { .init(date: .now, snapshot: .empty) }
    func getSnapshot(in context: Context, completion: @escaping (FoddWidgetEntry) -> Void) { completion(.init(date: .now, snapshot: FoddSharedContainer.loadWidgetSnapshot())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FoddWidgetEntry>) -> Void) {
        let entry = FoddWidgetEntry(date: .now, snapshot: FoddSharedContainer.loadWidgetSnapshot())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

struct FoddWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FoddWidgetEntry

    var body: some View {
        if family == .systemSmall { small } else { medium }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Image(systemName: "fork.knife.circle.fill"); Text("Fodd").font(.headline.bold()); Spacer() }
            Text(entry.snapshot.tasteHeadline).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(entry.snapshot.restaurantName).font(.headline).lineLimit(2)
            Spacer(minLength: 0)
            if entry.snapshot.restaurantMatch > 0 { Text("\(entry.snapshot.restaurantMatch)% MATCH").font(.caption.bold()).foregroundStyle(.orange) }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(entry.snapshot.restaurantId.isEmpty ? URL(string: "fodd://explore/home") : URL(string: "fodd://restaurant/\(entry.snapshot.restaurantId)"))
    }

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Label("FOR YOU", systemImage: "sparkles").font(.caption2.bold()).foregroundStyle(.orange)
                Text(entry.snapshot.restaurantName).font(.headline).lineLimit(2)
                Text(entry.snapshot.restaurantCategory).font(.caption).foregroundStyle(.secondary)
                if entry.snapshot.restaurantMatch > 0 { Text("\(entry.snapshot.restaurantMatch)% Taste Match").font(.caption.bold()) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            VStack(alignment: .leading, spacing: 7) {
                Label("TOGETHER", systemImage: "person.3.fill").font(.caption2.bold()).foregroundStyle(.orange)
                Text(entry.snapshot.planTitle).font(.subheadline.bold()).lineLimit(2)
                if let date = entry.snapshot.planScheduledAt { Text(date, style: .relative).font(.caption).foregroundStyle(.secondary) }
                if !entry.snapshot.planRestaurant.isEmpty { Text(entry.snapshot.planRestaurant).font(.caption).lineLimit(1) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(entry.snapshot.planId.isEmpty ? URL(string: "fodd://explore/home") : URL(string: "fodd://together/\(entry.snapshot.planId)"))
    }
}

struct FoddHomeWidget: Widget {
    let kind = "FoddHomeWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FoddWidgetProvider()) { entry in FoddWidgetView(entry: entry) }
            .configurationDisplayName("Fodd Smart Food")
            .description("Taste DNA, rekomendasi restoran, dan Makan Bareng berikutnya.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#if canImport(ActivityKit)
struct FoddDiningLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FoddDiningActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "person.3.fill").font(.title2).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.title).font(.headline).lineLimit(1)
                    Text(context.state.restaurantName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    HStack { Label("\(context.state.goingCount)", systemImage: "checkmark.circle.fill"); Label("\(context.state.messageCount)", systemImage: "message.fill"); Text(Date(timeIntervalSince1970: context.state.scheduledAt), style: .timer) }
                        .font(.caption2)
                }
                Spacer()
            }
            .padding(.horizontal, 4)
            .widgetURL(URL(string: "fodd://together/\(context.attributes.planId)"))
            .activityBackgroundTint(.black.opacity(0.04))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "fork.knife.circle.fill").foregroundStyle(.orange) }
                DynamicIslandExpandedRegion(.trailing) { Text(Date(timeIntervalSince1970: context.state.scheduledAt), style: .timer).font(.caption.bold()) }
                DynamicIslandExpandedRegion(.center) { Text(context.attributes.title).font(.headline).lineLimit(1) }
                DynamicIslandExpandedRegion(.bottom) { HStack { Text(context.state.restaurantName).lineLimit(1); Spacer(); Label("\(context.state.goingCount)", systemImage: "person.2.fill"); Label("\(context.state.messageCount)", systemImage: "message.fill") }.font(.caption) }
            } compactLeading: {
                Image(systemName: "fork.knife").foregroundStyle(.orange)
            } compactTrailing: {
                Text(Date(timeIntervalSince1970: context.state.scheduledAt), style: .timer).font(.caption2.bold()).frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "person.3.fill").foregroundStyle(.orange)
            }
            .widgetURL(URL(string: "fodd://together/\(context.attributes.planId)"))
        }
    }
}
#endif

@main
struct FoddWidgetBundle: WidgetBundle {
    var body: some Widget {
        FoddHomeWidget()
        #if canImport(ActivityKit)
        FoddDiningLiveActivityWidget()
        #endif
    }
}
