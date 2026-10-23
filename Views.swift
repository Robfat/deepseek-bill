import SwiftUI

// MARK: - 设计常量

private enum DS {
    static let corner: CGFloat = 18
    static let pad: CGFloat = 18
    static let accent = Color.accentColor
    static let hairline = Color.primary.opacity(0.08)
    static let label = Color.primary
    static let dim = Color.secondary
}

// MARK: - 根视图

struct DashboardView: View {
    @ObservedObject var model: UsageModel
    @State private var appeared = false
    @State private var hoveredDay: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let err = model.error { errorBar(err) }
            metrics
            todayLine
            chartSection
            keySection
            modelSection
            footer
        }
        .padding(DS.pad)
        .frame(width: 380)
        .overlay(
            RoundedRectangle(cornerRadius: DS.corner, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.28), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        )
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.985)
        .onAppear {
            withAnimation(.easeOut(duration: 0.18)) { appeared = true }
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("¥")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.dim)
                Text(balanceNumber)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(DS.label)
            }
            Spacer()
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("官方数据")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.dim)
            }
        }
    }

    private var balanceNumber: String {
        guard let b = model.balance else { return "--" }
        return String(format: "%.2f", b)
    }

    // MARK: 三个指标

    private var metrics: some View {
        HStack(spacing: 0) {
            metric("累计消费", money(model.totalCost))
            verticalDivider
            metric("今日", money(model.todayCost))
            verticalDivider
            metric("昨日", money(model.yesterdayCost))
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(DS.dim)
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(DS.label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(DS.hairline)
            .frame(width: 0.5, height: 26)
    }

    private var todayLine: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 8, weight: .semibold))
            Text("今日 \(model.todayRequests) 次请求 · \(compactTokens(model.todayTokens)) tokens")
                .font(.system(size: 11))
        }
        .foregroundStyle(DS.dim)
    }

    // MARK: 图表

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("每日官方消费")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.label)
                Spacer()
                rangeSwitch
            }
            chart
                .overlay(alignment: .top) {
                    if let day = hoveredDay, let p = model.points.first(where: { $0.day == day }) {
                        Text("\(shortDate(p.date)) · \(money(p.cost))")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(.regularMaterial))
                            .overlay(Capsule().strokeBorder(DS.hairline, lineWidth: 0.5))
                            .offset(y: -4)
                            .transition(.opacity)
                    }
                }
            HStack {
                Text(label(for: 0)).font(.system(size: 9)).foregroundStyle(DS.dim)
                Spacer()
                Text(label(for: model.rangeDays - 1)).font(.system(size: 9)).foregroundStyle(DS.dim)
            }
        }
    }

    private var rangeSwitch: some View {
        HStack(spacing: 2) {
            ForEach([7, 30], id: \.self) { d in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { model.rangeDays = d }
                } label: {
                    Text("\(d) 天")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(model.rangeDays == d ? DS.label : DS.dim)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            ZStack {
                                if model.rangeDays == d {
                                    Capsule()
                                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.9))
                                        .shadow(color: .black.opacity(0.14), radius: 2, y: 1)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    private var chart: some View {
        let visible = Array(model.points.suffix(model.rangeDays))
        let maxCost = max(visible.map { $0.cost }.max() ?? 0, 0.01)
        let spacing: CGFloat = model.rangeDays > 10 ? 3 : 10
        return ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { _ in
                    Rectangle().fill(DS.hairline).frame(height: 0.5)
                    Spacer()
                }
            }
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(visible) { p in
                    VStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(barStyle(p, max: maxCost))
                            .frame(height: max(2, CGFloat(p.cost / maxCost) * 88))
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        withAnimation(.easeOut(duration: 0.08)) {
                            if inside { hoveredDay = p.day }
                            else if hoveredDay == p.day { hoveredDay = nil }
                        }
                    }
                }
            }
        }
        .frame(height: 92)
    }

    private func barStyle(_ p: CostPoint, max: Double) -> LinearGradient {
        let isToday = p.day == (model.points.last?.day ?? 0)
        if isToday {
            return LinearGradient(colors: [DS.accent, DS.accent.opacity(0.75)],
                                  startPoint: .top, endPoint: .bottom)
        }
        let ratio = min(1, p.cost / max)
        return LinearGradient(colors: [DS.accent.opacity(0.35 + 0.55 * ratio),
                                       DS.accent.opacity(0.18 + 0.3 * ratio)],
                              startPoint: .top, endPoint: .bottom)
    }

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        f.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        return f.string(from: d)
    }

    private func label(for index: Int) -> String {
        let visible = Array(model.points.suffix(model.rangeDays))
        guard index < visible.count else { return "" }
        return shortDate(visible[index].date)
    }

    // MARK: 列表

    private var keySection: some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionHeader("按 API Key", trailing: "近 30 天")
            if model.byKey.isEmpty {
                emptyRow
            } else {
                ForEach(model.byKey.prefix(4)) { k in
                    dataRow(monogram: String(k.name.prefix(1)), title: k.name, value: money(k.cost))
                }
            }
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionHeader("按模型", trailing: "近 30 天")
            if model.byModel.isEmpty {
                emptyRow
            } else {
                ForEach(model.byModel.prefix(4)) { m in
                    dataRow(monogram: nil, title: displayModel(m.name), value: money(m.cost), dot: true)
                }
            }
        }
    }

    private func sectionHeader(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.label)
            Spacer()
            Text(trailing)
                .font(.system(size: 9))
                .foregroundStyle(DS.dim)
        }
        .padding(.bottom, 2)
    }

    private var emptyRow: some View {
        Text("暂无数据")
            .font(.system(size: 11))
            .foregroundStyle(DS.dim)
            .padding(.vertical, 4)
    }

    private func dataRow(monogram: String?, title: String, value: String, dot: Bool = false) -> some View {
        HoverRow {
            HStack(spacing: 8) {
                if let mono = monogram {
                    Text(mono)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.accent)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(DS.accent.opacity(0.12)))
                } else if dot {
                    Circle()
                        .fill(DS.accent.opacity(0.35))
                        .frame(width: 5, height: 5)
                        .frame(width: 18, height: 18)
                }
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.label)
                    .lineLimit(1)
                Spacer()
                Text(value)
                    .font(.system(size: 12, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(DS.label.opacity(0.9))
            }
        }
    }

    private func displayModel(_ raw: String) -> String {
        raw.replacingOccurrences(of: "deepseek-v4-", with: "v4 ")
            .replacingOccurrences(of: "deepseek-", with: "")
            .replacingOccurrences(of: "deepseek", with: "")
    }

    // MARK: 错误与底部

    private func errorBar(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
            Text(message)
                .font(.system(size: 11))
                .lineLimit(2)
            Spacer()
            Button("重试") { model.refresh() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.accent)
        }
        .foregroundStyle(Color.red.opacity(0.85))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.red.opacity(0.07)))
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Rectangle().fill(DS.hairline).frame(height: 0.5)
            HStack(spacing: 6) {
                if let t = model.lastUpdated {
                    Text("更新 \(timeString(t)) · 60 秒自动刷新")
                        .font(.system(size: 9.5))
                        .foregroundStyle(DS.dim)
                }
                Spacer()
                iconButton("arrow.clockwise", help: "立即刷新") { model.refresh() }
                iconButton("arrow.up.right.square", help: "平台用量") {
                    if let url = URL(string: "https://platform.deepseek.com/usage") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        IconButton(symbol: symbol, help: help, action: action)
    }

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}

// MARK: - 小组件

private struct HoverRow<Content: View>: View {
    @State private var hover = false
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hover ? Color.primary.opacity(0.06) : .clear)
            )
            .contentShape(Rectangle())
            .onHover { hover = $0 }
    }
}

private struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hover ? Color.primary : Color.secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(hover ? Color.primary.opacity(0.08) : .clear))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hover = $0 }
    }
}
