import SwiftUI
import Combine
import Charts

@MainActor
final class ChartsViewModel: ObservableObject {
    @Published var stats: TeamStats?
    @Published var error: String?

    private var loadToken = UUID()

    func load(groupId: UUID?) async {
        let token = UUID()
        loadToken = token
        do {
            let result = try await APIClient.shared.teamStats(groupId: groupId)
            guard loadToken == token else { return }
            stats = result
            error = nil
        } catch let api as APIError where api.isCancelled {
            // ignored
        } catch {
            guard loadToken == token else { return }
            self.error = error.localizedDescription
        }
    }
}

struct ChartsView: View {
    @StateObject private var vm = ChartsViewModel()
    @EnvironmentObject var filter: GroupFilterStore

    private static let isoDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Convert "yyyy-MM-dd" strings into real Dates so the chart renders a
    /// proper time axis (the previous version used the raw string, which made
    /// Charts treat the x-axis as a discrete category and produced misleading
    /// spacing for sparse data).
    private func cumulativeDated(_ points: [CumulativePoint]) -> [(date: Date, total: Int)] {
        points.compactMap { p in
            guard let d = Self.isoDayFormatter.date(from: p.date) else { return nil }
            return (d, p.total)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack {
                    GroupFilterPicker()
                    Spacer()
                }
                if let stats = vm.stats {
                    chartSection("Beers by time of day") {
                        Chart(stats.byHour) { bucket in
                            BarMark(x: .value("Hour", bucket.hour), y: .value("Beers", bucket.count))
                                .foregroundStyle(.orange)
                        }
                        .chartXAxis {
                            AxisMarks(values: [0, 6, 12, 18]) { v in
                                AxisGridLine()
                                AxisTick()
                                AxisValueLabel { if let i = v.as(Int.self) { Text(Format.hourLabel(i)) } }
                            }
                        }
                        .frame(height: 200)
                    }

                    chartSection("Beers by day of week") {
                        Chart(stats.byDayOfWeek) { bucket in
                            BarMark(x: .value("Day", Format.dayOfWeekName(bucket.day)),
                                    y: .value("Beers", bucket.count))
                                .foregroundStyle(.orange.gradient)
                        }
                        .frame(height: 200)
                    }

                    chartSection("Beers over time (cumulative)") {
                        let dated = cumulativeDated(stats.cumulative)
                        if dated.isEmpty {
                            Text("No drinks logged yet.")
                                .foregroundStyle(.secondary)
                                .frame(height: 220, alignment: .center)
                                .frame(maxWidth: .infinity)
                        } else {
                            Chart {
                                ForEach(dated, id: \.date) { p in
                                    LineMark(x: .value("Date", p.date), y: .value("Total", p.total))
                                        .interpolationMethod(.monotone)
                                        .foregroundStyle(.orange)
                                    AreaMark(x: .value("Date", p.date), y: .value("Total", p.total))
                                        .foregroundStyle(.orange.opacity(0.15))
                                }
                            }
                            .chartXAxis {
                                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                                    AxisGridLine()
                                    AxisTick()
                                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                }
                            }
                            .frame(height: 220)
                        }
                    }

                    if let drinkTypes = stats.drinkTypes, drinkTypes.contains(where: { $0.count > 0 }) {
                        chartSection("Drink mix") {
                            Chart(drinkTypes.filter { $0.count > 0 }) { bucket in
                                SectorMark(
                                    angle: .value("Count", bucket.count),
                                    innerRadius: .ratio(0.55),
                                    angularInset: 1
                                )
                                .foregroundStyle(by: .value("Type", bucket.drinkType?.displayName ?? bucket.type))
                            }
                            .chartLegend(position: .bottom, alignment: .center, spacing: 8)
                            .frame(height: 220)
                        }
                    }

                    chartSection("Top 10 drinkers") {
                        Chart(stats.topUsers) { user in
                            BarMark(
                                x: .value("Beers", user.count),
                                y: .value("User", user.nickname)
                            )
                            .foregroundStyle(.orange)
                        }
                        .frame(height: max(220, CGFloat(stats.topUsers.count) * 28))
                    }

                    chartSection("Beers per week") {
                        Chart(stats.byWeek) { w in
                            BarMark(x: .value("Week", w.week), y: .value("Beers", w.count))
                                .foregroundStyle(.orange)
                        }
                        .chartXAxis(.hidden)
                        .frame(height: 200)
                    }

                    chartSection("Beers by month") {
                        Chart(stats.byMonth) { m in
                            BarMark(x: .value("Month", m.month), y: .value("Beers", m.count))
                                .foregroundStyle(.orange.gradient)
                        }
                        .frame(height: 200)
                    }

                    chartSection("Personal vs team") {
                        let mine = stats.myCount
                        let team = max(stats.total - mine, 0)
                        Chart {
                            SectorMark(angle: .value("Me", mine), innerRadius: .ratio(0.6))
                                .foregroundStyle(.orange)
                                .annotation(position: .overlay) { Text("\(mine)").font(.caption) }
                            SectorMark(angle: .value("Team", team), innerRadius: .ratio(0.6))
                                .foregroundStyle(.gray.opacity(0.4))
                        }
                        .frame(height: 220)
                    }
                } else if let err = vm.error {
                    Text(err).foregroundStyle(.red)
                } else {
                    ProgressView()
                }
            }
            .padding()
        }
        .navigationTitle("Charts")
        .refreshable { await vm.load(groupId: filter.selectedGroupId) }
        .task(id: filter.selectedGroupId) { await vm.load(groupId: filter.selectedGroupId) }
    }

    @ViewBuilder
    private func chartSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
