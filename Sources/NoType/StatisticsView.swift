import SwiftUI
import NoTypeCore

struct StatisticsView: View {
    @ObservedObject var state: AppState
    @State private var period = "all"
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var metric = "characters"
    @State private var selectedDay: Date?
    private var calendar: Calendar { var value = Calendar.current; value.firstWeekday = 2; return value }
    private var all: UsageStatistics { UsageStatistics(records: state.records, calendar: calendar) }
    private var summary: UsageStatistics {
        let now = Date()
        let component: Calendar.Component? = period == "today" ? .day : period == "week" ? .weekOfYear : period == "month" ? .month : nil
        return UsageStatistics(records: state.records, calendar: calendar, interval: component.flatMap { calendar.dateInterval(of: $0, for: now) })
    }
    private var years: [Int] {
        let current = calendar.component(.year, from: Date())
        return Array(Set(all.days.map { calendar.component(.year, from: $0.date) } + [current, year])).sorted(by: >)
    }
    private var yearStart: Date { calendar.date(from: DateComponents(year: year, month: 1, day: 1))! }
    private var yearEnd: Date { calendar.date(byAdding: .year, value: 1, to: yearStart)! }
    private var gridStart: Date {
        let offset = (calendar.component(.weekday, from: yearStart) + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: yearStart)!
    }
    private var weeks: Int { (calendar.dateComponents([.day], from: gridStart, to: yearEnd).day! + 6) / 7 }
    private var daily: [Date: DailyUsage] { Dictionary(uniqueKeysWithValues: all.days.map { ($0.date, $0) }) }
    private func value(_ usage: DailyUsage?) -> Double {
        guard let usage else { return 0 }
        switch metric { case "seconds": return usage.seconds; case "sessions": return Double(usage.sessions); default: return Double(usage.characters) }
    }
    private var maximum: Double { max(1, all.days.filter { $0.date >= yearStart && $0.date < yearEnd }.map { value($0) }.max() ?? 1) }
    private func duration(_ seconds: Double) -> String {
        let total = Int(seconds)
        if total >= 3600 { return "\(total / 3600) 小时 \((total % 3600) / 60) 分" }
        return "\(total / 60) 分 \(total % 60) 秒"
    }
    var body: some View {
        let lookup = daily
        let peak = maximum
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("使用统计").font(.system(size: 26, weight: .semibold))
                    Text("口述统计与每日使用记录，仅保存在本机。").font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer()
            }
            Picker("统计范围", selection: $period) {
                Text("今天").tag("today"); Text("本周").tag("week"); Text("本月").tag("month"); Text("全部").tag("all")
            }.pickerStyle(.segmented)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                stat("口述字数", value: summary.characters.formatted(), unit: "字", icon: "textformat.abc")
                stat("平均口述速度", value: summary.seconds > 0 ? String(format: "%.0f", summary.charactersPerMinute) : "—", unit: "字 / 分钟", icon: "speedometer")
                stat("口述时间", value: duration(summary.seconds), unit: "", icon: "waveform")
                stat("活跃天数", value: "\(summary.activeDays)", unit: "天 · \(summary.sessions) 次口述", icon: "calendar")
            }
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("每日使用热力图", systemImage: "square.grid.3x3.fill").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Picker("年份", selection: $year) { ForEach(years, id: \.self) { Text(String($0)).tag($0) } }.frame(width: 115)
                        .onChange(of: year) { _, _ in selectedDay = nil }
                }
                Picker("热力图指标", selection: $metric) {
                    Text("口述字数").tag("characters"); Text("口述时间").tag("seconds"); Text("使用次数").tag("sessions")
                }.pickerStyle(.segmented)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 4) {
                        VStack(spacing: 4) {
                            Color.clear.frame(height: 16)
                            ForEach(0..<7) { row in
                                Text(row == 0 ? "一" : row == 3 ? "四" : row == 6 ? "日" : "")
                                    .font(.system(size: 9)).frame(width: 16, height: 10)
                            }
                        }.foregroundStyle(Palette.muted)
                        ForEach(0..<weeks, id: \.self) { week in
                            VStack(spacing: 4) {
                                Text(monthLabel(week)).font(.system(size: 9)).foregroundStyle(Palette.muted).fixedSize().frame(width: 10, height: 16)
                                ForEach(0..<7) { row in cell(week: week, row: row, usage: lookup[date(week: week, row: row)], peak: peak) }
                            }
                        }
                    }.padding(.vertical, 4)
                }
                HStack(spacing: 5) {
                    Text("\(String(year)) 年 · \(all.days.filter { $0.date >= yearStart && $0.date < yearEnd }.count) 个活跃日")
                    Spacer(); Text("少")
                    ForEach(0..<5) { level in RoundedRectangle(cornerRadius: 2).fill(color(level)).frame(width: 10, height: 10) }
                    Text("多")
                }.font(.system(size: 11)).foregroundStyle(Palette.muted)
                if let selectedDay {
                    let usage = daily[selectedDay]
                    Text("\(selectedDay.formatted(date: .abbreviated, time: .omitted)) · \(usage?.characters ?? 0) 字 · \(duration(usage?.seconds ?? 0)) · \(usage?.sessions ?? 0) 次口述")
                        .font(.system(size: 12)).foregroundStyle(Palette.green).textSelection(.enabled)
                } else {
                    Text("悬停查看每日数据，点击方格保留详情。").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                if all.sessions == 0 { Text("还没有口述记录。完成并保存第一段录音后，这里就会亮起第一格。").font(.system(size: 12)).foregroundStyle(Palette.muted) }
            }.padding(22).nativeCard()
            Text("统计基于本机已保存的成功口述：按原始转写计算字数，忽略空白和标点；速度为总字数 ÷ 总录音分钟数。导入音频、手动输入与重复润色不增加口述次数。删除历史会同步减少统计；关闭历史保存期间不计入。每天按当前系统时区归属。")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func stat(_ title: String, value: String, unit: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon).font(.system(size: 12)).foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(value).font(.system(size: 27, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(unit).font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).nativeCard()
    }
    private func date(week: Int, row: Int) -> Date { calendar.date(byAdding: .day, value: week * 7 + row, to: gridStart)! }
    private func monthLabel(_ week: Int) -> String {
        let first = date(week: week, row: 0)
        let last = date(week: week, row: 6)
        if yearStart >= first && yearStart <= last { return "1月" }
        if calendar.component(.day, from: first) == 1, first < yearEnd { return "\(calendar.component(.month, from: first))月" }
        if calendar.component(.month, from: first) != calendar.component(.month, from: last), last < yearEnd {
            return "\(calendar.component(.month, from: last))月"
        }
        return ""
    }
    private func color(_ level: Int) -> Color { level == 0 ? Palette.sidebar : Palette.green.opacity([0, 0.28, 0.48, 0.72, 1][level]) }
    @ViewBuilder private func cell(week: Int, row: Int, usage: DailyUsage?, peak: Double) -> some View {
        let day = date(week: week, row: row)
        let valid = day >= yearStart && day < yearEnd && day <= calendar.startOfDay(for: Date())
        let level = value(usage) <= 0 ? 0 : min(4, max(1, Int(ceil(value(usage) / peak * 4))))
        if valid {
            Button { selectedDay = day } label: {
                RoundedRectangle(cornerRadius: 2).fill(color(level)).frame(width: 10, height: 10)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(selectedDay == day ? Palette.ink : .clear, lineWidth: 1.5))
            }.buttonStyle(.plain)
                .help("\(day.formatted(date: .abbreviated, time: .omitted))：\(usage?.characters ?? 0) 字，\(duration(usage?.seconds ?? 0))，\(usage?.sessions ?? 0) 次")
                .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted))，\(usage?.characters ?? 0) 字，\(usage?.sessions ?? 0) 次口述")
        } else { Color.clear.frame(width: 10, height: 10) }
    }
}
