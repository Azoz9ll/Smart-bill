//
//  StatisticsView.swift
//  Smart Bill
//
//  Analytics are calculated from the receipt and receipt-item records already
//  returned by get_receipts.php and get_items.php.
//

import SwiftUI
import Charts

private enum AnalyticsPeriod: String, CaseIterable, Identifiable {
    case sevenDays, thirtyDays, threeMonths, sixMonths, oneYear, all

    var id: String { rawValue }
    var title: String {
        switch self {
        case .sevenDays: "آخر 7 أيام"
        case .thirtyDays: "آخر 30 يوم"
        case .threeMonths: "آخر 3 أشهر"
        case .sixMonths: "آخر 6 أشهر"
        case .oneYear: "آخر سنة"
        case .all: "جميع الفواتير"
        }
    }
    var usesDailyChart: Bool { self == .sevenDays || self == .thirtyDays }
    var dayCount: Int? {
        switch self {
        case .sevenDays: 7
        case .thirtyDays: 30
        default: nil
        }
    }
    var monthCount: Int? {
        switch self {
        case .threeMonths: 3
        case .sixMonths: 6
        case .oneYear: 12
        default: nil
        }
    }
}

private struct AnalyticsPoint: Identifiable {
    let date: Date
    let total: Double
    var id: Date { date }
}

private struct CategorySpending: Identifiable {
    let name: String
    let total: Double
    let share: Double
    var id: String { name }
}

private struct StoreSpending: Identifiable {
    let name: String
    let total: Double
    let receiptCount: Int
    let share: Double
    var id: String { name }
}

private struct ProductFrequency: Identifiable {
    let name: String
    let count: Int
    var id: String { name }
}

private struct SpendingSummary {
    let currentReceipts: [Receipt]
    let total: Double
    let previousTotal: Double
    let averageReceipt: Double?
    let receiptCount: Int
    let hasIncompleteTotals: Bool
    let hasIncompleteProductPrices: Bool
    let previousHasIncompleteTotals: Bool
    let invalidDateCount: Int
    let categories: [CategorySpending]
    let stores: [StoreSpending]
    let productFrequencies: [ProductFrequency]
    let mostExpensiveProduct: Product?
    let averageProductSpend: Double?
    let points: [AnalyticsPoint]
    let period: AnalyticsPeriod
    let calendar: Calendar

    static func parseDate(_ value: String, timeZone: TimeZone) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return date
    }

    init(receipts: [Receipt], period: AnalyticsPeriod, now: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
        self.period = period

        let dated = receipts.compactMap { receipt -> (Receipt, Date)? in
            guard let date = Self.parseDate(receipt.date, timeZone: timeZone), date <= now else { return nil }
            return (receipt, date)
        }
        invalidDateCount = receipts.count - dated.count

        let start: Date
        switch period {
        case .sevenDays:
            start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
        case .thirtyDays:
            start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) ?? now
        case .threeMonths:
            start = calendar.date(byAdding: .month, value: -3, to: now) ?? now
        case .sixMonths:
            start = calendar.date(byAdding: .month, value: -6, to: now) ?? now
        case .oneYear:
            start = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        case .all:
            start = dated.map { $0.1 }.min() ?? now
        }

        currentReceipts = dated.filter { $0.1 >= start && $0.1 <= now }.map { $0.0 }
        receiptCount = currentReceipts.count
        hasIncompleteTotals = currentReceipts.contains { !$0.totalIsComplete }
        hasIncompleteProductPrices = currentReceipts.contains { receipt in
            receipt.items.contains { !$0.priceAvailable }
        }
        let computedTotal = currentReceipts.reduce(0) { $0 + $1.total }
        total = computedTotal
        averageReceipt = receiptCount > 0 ? computedTotal / Double(receiptCount) : nil

        let previousStart: Date
        switch period {
        case .sevenDays: previousStart = calendar.date(byAdding: .day, value: -7, to: start) ?? start
        case .thirtyDays: previousStart = calendar.date(byAdding: .day, value: -30, to: start) ?? start
        case .threeMonths: previousStart = calendar.date(byAdding: .month, value: -3, to: start) ?? start
        case .sixMonths: previousStart = calendar.date(byAdding: .month, value: -6, to: start) ?? start
        case .oneYear: previousStart = calendar.date(byAdding: .year, value: -1, to: start) ?? start
        case .all:
            let duration = max(now.timeIntervalSince(start), 86_400)
            previousStart = start.addingTimeInterval(-duration)
        }
        let previousReceipts = dated.filter { $0.1 >= previousStart && $0.1 < start }.map { $0.0 }
        previousTotal = previousReceipts.reduce(0) { $0 + $1.total }
        previousHasIncompleteTotals = previousReceipts.contains { !$0.totalIsComplete }

        var categoryTotals: [String: Double] = [:]
        var productCounts: [String: (displayName: String, count: Int)] = [:]
        var availableProducts: [Product] = []
        for receipt in currentReceipts {
            for product in receipt.items where product.priceAvailable {
                let name = product.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                availableProducts.append(product)
                let key = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ar"))
                var frequency = productCounts[key, default: (name, 0)]
                frequency.count += 1
                productCounts[key] = frequency

                let category = product.category.trimmingCharacters(in: .whitespacesAndNewlines)
                if !category.isEmpty { categoryTotals[category, default: 0] += product.price }
            }
        }
        let categoryTotal = categoryTotals.values.reduce(0, +)
        categories = categoryTotal > 0
            ? categoryTotals.map { CategorySpending(name: $0.key, total: $0.value, share: $0.value / categoryTotal) }
                .sorted { $0.total == $1.total ? $0.name < $1.name : $0.total > $1.total }
            : []
        productFrequencies = productCounts.values.map { ProductFrequency(name: $0.displayName, count: $0.count) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
        mostExpensiveProduct = availableProducts.max { $0.price < $1.price }
        averageProductSpend = availableProducts.isEmpty
            ? nil
            : availableProducts.reduce(0) { $0 + $1.price } / Double(availableProducts.count)

        var storeTotals: [String: (total: Double, receipts: Int)] = [:]
        for receipt in currentReceipts {
            let name = Self.storeDisplayName(receipt.store)
            guard !name.isEmpty else { continue }
            var aggregate = storeTotals[name, default: (0, 0)]
            aggregate.total += receipt.total
            aggregate.receipts += 1
            storeTotals[name] = aggregate
        }
        var computedStores: [StoreSpending] = []
        for (name, aggregate) in storeTotals {
            let share = computedTotal > 0 ? aggregate.total / computedTotal : 0
            computedStores.append(StoreSpending(name: name, total: aggregate.total,
                                                receiptCount: aggregate.receipts, share: share))
        }
        computedStores.sort { lhs, rhs in
            lhs.total == rhs.total ? lhs.name < rhs.name : lhs.total > rhs.total
        }
        stores = computedStores

        var buckets: [Date: Double] = [:]
        for (receipt, date) in dated where date >= start && date <= now {
            let bucket = period.usesDailyChart
                ? calendar.startOfDay(for: date)
                : (calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date))
            buckets[bucket, default: 0] += receipt.total
        }
        if let dayCount = period.dayCount {
            let lastDay = calendar.startOfDay(for: now)
            points = (0..<dayCount).compactMap { offset in
                guard let date = calendar.date(byAdding: .day, value: offset - dayCount + 1, to: lastDay) else { return nil }
                return AnalyticsPoint(date: date, total: buckets[date, default: 0])
            }
        } else {
            let firstMonth: Date
            if period == .all {
                let latestTwelveMonths = calendar.date(byAdding: .month, value: -11,
                    to: calendar.dateInterval(of: .month, for: now)?.start ?? now) ?? start
                firstMonth = max(calendar.dateInterval(of: .month, for: start)?.start ?? start, latestTwelveMonths)
            } else {
                firstMonth = calendar.dateInterval(of: .month, for: start)?.start ?? start
            }
            let lastMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
            var month = firstMonth
            var monthly: [AnalyticsPoint] = []
            while month <= lastMonth {
                monthly.append(AnalyticsPoint(date: month, total: buckets[month, default: 0]))
                guard let next = calendar.date(byAdding: .month, value: 1, to: month), next > month else { break }
                month = next
            }
            points = monthly
        }
    }

    var periodChange: Double? {
        guard previousTotal > 0, !hasIncompleteTotals, !previousHasIncompleteTotals else { return nil }
        let result = (total - previousTotal) / previousTotal * 100
        return result.isFinite ? result : nil
    }

    var topStore: StoreSpending? { stores.first }
    var topCategory: CategorySpending? { categories.first }

    var highestSpendingBucket: AnalyticsPoint? {
        points.filter { $0.total > 0 }.max { $0.total < $1.total }
    }

    func chartLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar_SA@numbers=latn")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = period.usesDailyChart ? "d MMM" : "MMM yy"
        return formatter.string(from: date)
    }

    private static func storeDisplayName(_ source: String) -> String {
        let value = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ar"))
        if normalized.contains("panda") || normalized.contains("باندا") { return "Panda Saudi Arabia" }
        if normalized.contains("tamimi") || normalized.contains("تميمي") { return "Tamimi Markets" }
        if normalized.contains("danube") || normalized.contains("دانوب") { return "Danube" }
        return value
    }
}

struct StatisticsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var receipts: [Receipt] = []
    @State private var period: AnalyticsPeriod = .thirtyDays
    @State private var isLoading = true
    @State private var isFetching = false
    @State private var hasError = false
    @State private var referenceDate = Date()
    @State private var selectedChartDate: Date?

    private var summary: SpendingSummary {
        SpendingSummary(receipts: receipts, period: period, now: referenceDate)
    }
    private var accent: Color {
        colorScheme == .dark ? Color(red: 0.40, green: 0.63, blue: 0.51) : Color(red: 0.20, green: 0.48, blue: 0.36)
    }
    private var background: Color {
        colorScheme == .dark ? Color(red: 0.025, green: 0.04, blue: 0.04) : Color(red: 0.965, green: 0.975, blue: 0.97)
    }
    private var card: Color {
        colorScheme == .dark ? Color(red: 0.075, green: 0.095, blue: 0.095) : .white
    }
    private var primary: Color { colorScheme == .dark ? .white : Color(red: 0.07, green: 0.10, blue: 0.09) }
    private var secondary: Color { colorScheme == .dark ? .white.opacity(0.58) : .black.opacity(0.56) }
    private var border: Color { colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08) }
    private var warning: Color { colorScheme == .dark ? Color(red: 0.90, green: 0.55, blue: 0.45) : Color(red: 0.67, green: 0.25, blue: 0.17) }
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(card)
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(border, lineWidth: 1))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.08 : 0.035), radius: 10, y: 4)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    periodSelector
                    if isLoading {
                        loadingState
                    } else if hasError {
                        errorState
                    } else if receipts.isEmpty {
                        emptyState("لا توجد بيانات كافية", subtitle: "احفظ بعض الفواتير لعرض ملخص إنفاقك.")
                    } else {
                        let values = summary
                        if values.invalidDateCount > 0 {
                            Label("بعض الفواتير لا تحمل تاريخاً صالحاً، لذلك لم تُحتسب.", systemImage: "info.circle")
                                .font(.caption).foregroundStyle(secondary)
                        }
                        financialSummary(values)
                        if values.receiptCount == 0 {
                            emptyState("لا توجد فواتير في هذه الفترة", subtitle: "اختر فترة أخرى لعرض بياناتك.")
                        } else {
                            monthlyChart(values)
                            categoriesChart(values)
                            storeComparison(values)
                            purchaseInsights(values)
                            smartInsights(values)
                        }
                    }
                }
                .padding(SmartBillStyle.horizontalInset)
                .padding(.bottom, 24)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .foregroundStyle(primary)
            .background(screenBackground)
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(background, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .refreshable { await fetchStatistics() }
            .onAppear { Task { await fetchStatistics() } }
            .onChange(of: period) { _, _ in selectedChartDate = nil }
        }
        .tint(accent)
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 52, height: 52)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text("الإحصائيات").font(.system(.title2, design: .rounded, weight: .bold))
                Text("ملخص مصاريفك وتحليلها").font(.subheadline).foregroundStyle(secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var periodSelector: some View {
        Menu {
            Picker("الفترة", selection: $period) {
                ForEach(AnalyticsPeriod.allCases) { option in Text(option.title).tag(option) }
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "calendar").foregroundStyle(accent)
                Text(period.title).font(.subheadline.weight(.semibold)).foregroundStyle(primary)
                Spacer()
                Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(secondary)
            }
            .padding(.horizontal, 16).frame(minHeight: 50)
            .background(cardBackground)
        }
        .accessibilityLabel("الفترة الزمنية")
    }

    private func financialSummary(_ values: SpendingSummary) -> some View {
        VStack(spacing: 9) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 3), spacing: 9) {
                metricCard(title: values.hasIncompleteTotals ? "مصروفات جزئية" : "إجمالي المصروفات",
                           value: SmartBillFormatting.money(values.total), symbol: "banknote", emphasize: true)
                metricCard(title: "عدد الفواتير", value: SmartBillFormatting.digits(String(values.receiptCount)),
                           symbol: "doc.text")
                metricCard(title: values.hasIncompleteTotals ? "متوسط جزئي" : "متوسط الفاتورة",
                           value: values.averageReceipt.map(SmartBillFormatting.money) ?? "—", symbol: "divide")
            }
            if let change = values.periodChange {
                HStack(spacing: 6) {
                    Image(systemName: change < 0 ? "arrow.down.right" : change > 0 ? "arrow.up.right" : "minus")
                    Text("\(String(format: "%.1f%%", locale: SmartBillFormatting.locale, abs(change))) مقارنة بالفترة السابقة")
                        .monospacedDigit()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(change > 0 ? warning : accent)
            }
        }
    }

    private func metricCard(title: String, value: String, symbol: String, emphasize: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(emphasize ? accent : secondary)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            Text(value)
                .font(.system(size: emphasize ? 15 : 14, weight: .bold, design: .rounded))
                .foregroundStyle(emphasize ? accent : primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .environment(\.layoutDirection, .leftToRight)
        }
        .frame(maxWidth: .infinity, minHeight: 107, alignment: .leading)
        .padding(12)
        .background(cardBackground)
    }

    private var selectedPoint: AnalyticsPoint? {
        guard let selectedChartDate else { return nil }
        let values = summary
        return values.points.first {
            values.period.usesDailyChart
                ? values.calendar.isDate($0.date, inSameDayAs: selectedChartDate)
                : values.calendar.isDate($0.date, equalTo: selectedChartDate, toGranularity: .month)
        }
    }

    private func monthlyChart(_ values: SpendingSummary) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(values.period.usesDailyChart ? "الإنفاق خلال الفترة" : "المصروفات الشهرية")
                        .font(.headline)
                    Text(values.period == .all ? "عرض الأشهر الاثني عشر الأخيرة في الرسم" : "اضغط على الرسم لعرض قيمة الفترة")
                        .font(.caption).foregroundStyle(secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chart.bar.fill").foregroundStyle(accent)
            }
            if let selectedPoint {
                HStack {
                    Text(values.chartLabel(selectedPoint.date)).foregroundStyle(secondary)
                    Spacer()
                    Text(SmartBillFormatting.money(selectedPoint.total)).font(.subheadline.bold()).foregroundStyle(accent)
                }
                .font(.caption)
                .monospacedDigit()
            }
            Chart(values.points) { point in
                BarMark(
                    x: .value("التاريخ", point.date, unit: values.period.usesDailyChart ? .day : .month),
                    y: .value("المصروفات", point.total)
                )
                .foregroundStyle(isSelected(point, in: values) ? accent : accent.opacity(0.58))
                .cornerRadius(5)
                if isSelected(point, in: values) {
                    RuleMark(x: .value("التاريخ المحدد", point.date))
                        .foregroundStyle(accent.opacity(0.2))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartXSelection(value: $selectedChartDate)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: values.period == .sevenDays ? 7 : 5)) { axis in
                    AxisGridLine().foregroundStyle(.clear)
                    AxisTick().foregroundStyle(border)
                    AxisValueLabel {
                        if let date = axis.as(Date.self) {
                            Text(values.chartLabel(date)).font(.caption2).foregroundStyle(secondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                    AxisGridLine().foregroundStyle(border)
                    AxisValueLabel().foregroundStyle(secondary)
                }
            }
            .chartYScale(domain: 0...(max(values.points.map(\.total).max() ?? 0, 1) * 1.12))
            .frame(height: 190)
            .animation(.easeInOut(duration: 0.25), value: period)
        }
        .padding(17)
        .background(cardBackground)
    }

    private func isSelected(_ point: AnalyticsPoint, in values: SpendingSummary) -> Bool {
        guard let date = selectedChartDate else { return false }
        return values.period.usesDailyChart
            ? values.calendar.isDate(point.date, inSameDayAs: date)
            : values.calendar.isDate(point.date, equalTo: date, toGranularity: .month)
    }

    private func categoriesChart(_ values: SpendingSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("توزيع المصروفات حسب التصنيف").font(.headline)
            if values.categories.isEmpty {
                Text("لا توجد مبالغ منتجات مصنفة في هذه الفترة.")
                    .font(.subheadline).foregroundStyle(secondary)
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
            } else {
                Chart(values.categories) { category in
                    SectorMark(angle: .value("المصروفات", category.total),
                               innerRadius: .ratio(0.60), angularInset: 2)
                    .foregroundStyle(by: .value("التصنيف", category.name))
                    .cornerRadius(4)
                }
                .chartLegend(.hidden)
                .chartForegroundStyleScale(domain: values.categories.map(\.name), range: categoryPalette)
                .frame(height: 190)

                ForEach(values.categories) { category in
                    HStack(spacing: 10) {
                        Circle().fill(categoryColor(category, in: values)).frame(width: 9, height: 9)
                        Image(systemName: categoryIcon(category.name)).foregroundStyle(accent).frame(width: 18)
                        SmartBillCategoryLabel(category: category.name)
                            .font(.subheadline).foregroundStyle(primary)
                        Spacer(minLength: 6)
                        Text(SmartBillFormatting.money(category.total))
                            .font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(primary)
                        Text(String(format: "%.1f%%", locale: SmartBillFormatting.locale, category.share * 100))
                            .font(.caption2.weight(.semibold)).monospacedDigit().foregroundStyle(accent)
                            .frame(minWidth: 47, alignment: .trailing)
                    }
                }
            }
        }
        .padding(17)
        .background(cardBackground)
    }

    private var categoryPalette: [Color] {
        [accent, Color(red: 0.33, green: 0.55, blue: 0.72), Color(red: 0.80, green: 0.56, blue: 0.30),
         Color(red: 0.62, green: 0.47, blue: 0.70), Color(red: 0.38, green: 0.67, blue: 0.60),
         Color(red: 0.78, green: 0.40, blue: 0.42), Color(red: 0.66, green: 0.66, blue: 0.34)]
    }

    private func categoryColor(_ category: CategorySpending, in values: SpendingSummary) -> Color {
        guard let index = values.categories.firstIndex(where: { $0.id == category.id }) else { return accent }
        return categoryPalette[index % categoryPalette.count]
    }

    private func storeComparison(_ values: SpendingSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("المصروفات حسب المتجر").font(.headline)
            if values.stores.isEmpty {
                Text("لا توجد أسماء متاجر مسجلة في فواتير هذه الفترة.")
                    .font(.subheadline).foregroundStyle(secondary)
            } else {
                Chart(values.stores) { store in
                    BarMark(x: .value("المصروفات", store.total), y: .value("المتجر", store.name))
                        .foregroundStyle(accent.opacity(store.id == values.stores.first?.id ? 1 : 0.68))
                        .cornerRadius(5)
                }
                .chartXAxis {
                    AxisMarks(position: .bottom, values: .automatic(desiredCount: 4)) {
                        AxisGridLine().foregroundStyle(border)
                        AxisValueLabel().foregroundStyle(secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { axis in
                        AxisValueLabel().foregroundStyle(primary)
                    }
                }
                .frame(height: CGFloat(min(max(values.stores.count, 1), 5) * 44 + 20))

                ForEach(values.stores) { store in
                    HStack(spacing: 10) {
                        Image(systemName: storeIcon(store.name))
                            .foregroundStyle(accent).frame(width: 30, height: 30)
                            .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.name).font(.subheadline.weight(.semibold)).foregroundStyle(primary).lineLimit(1)
                            Text("\(SmartBillFormatting.digits(String(store.receiptCount))) فواتير")
                                .font(.caption2).foregroundStyle(secondary)
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(SmartBillFormatting.money(store.total)).font(.caption.weight(.bold)).foregroundStyle(primary).monospacedDigit()
                            Text(String(format: "%.1f%%", locale: SmartBillFormatting.locale, store.share * 100))
                                .font(.caption2).foregroundStyle(accent).monospacedDigit()
                        }
                    }
                }
            }
        }
        .padding(17)
        .background(cardBackground)
    }

    private func purchaseInsights(_ values: SpendingSummary) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("تحليل مشترياتك").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
                insightTile("الأكثر تكراراً", value: values.productFrequencies.first?.name,
                            detail: values.productFrequencies.first.map { "\($0.count) مرات ورود في الفواتير" }, symbol: "repeat")
                insightTile("أعلى سعر منتج", value: values.mostExpensiveProduct?.name,
                            detail: values.mostExpensiveProduct.map { SmartBillFormatting.money($0.price) }, symbol: "tag.fill")
                insightTile("أعلى تصنيف إنفاقاً", value: values.topCategory?.name,
                            detail: values.topCategory.map { SmartBillFormatting.money($0.total) }, symbol: "square.grid.2x2.fill")
                insightTile("متوسط سعر المنتج", value: values.averageProductSpend.map(SmartBillFormatting.money),
                            detail: "من أسعار المنتجات المسجلة", symbol: "divide")
                insightTile("الأكثر زيارة", value: values.topStore?.name,
                            detail: values.topStore.map { "\($0.receiptCount) فواتير" }, symbol: "storefront.fill")
            }
            if values.hasIncompleteProductPrices {
                Text("بعض المنتجات بلا سعر مسجل؛ تحليل المنتجات يشمل الأسعار المتاحة فقط.")
                    .font(.caption).foregroundStyle(secondary)
            }
        }
        .padding(17)
        .background(cardBackground)
    }

    private func insightTile(_ title: String, value: String?, detail: String?, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).font(.caption).foregroundStyle(accent)
            Text(title).font(.caption2).foregroundStyle(secondary)
            Text(value ?? "لا توجد بيانات")
                .font(.subheadline.weight(.semibold)).foregroundStyle(primary)
                .lineLimit(2).minimumScaleFactor(0.8)
            if let detail { Text(detail).font(.caption2).foregroundStyle(secondary).lineLimit(2) }
        }
        .frame(maxWidth: .infinity, minHeight: 102, alignment: .leading)
        .padding(11)
        .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(border, lineWidth: 1))
    }

    private func smartInsights(_ values: SpendingSummary) -> some View {
        let insights = makeInsights(values)
        return VStack(alignment: .leading, spacing: 13) {
            Label("تحليل SmartBill", systemImage: "sparkles")
                .font(.headline).foregroundStyle(primary)
            if insights.isEmpty {
                Text("لا توجد بيانات كافية لاستخراج ملاحظات مؤكدة لهذه الفترة.")
                    .font(.subheadline).foregroundStyle(secondary)
            } else {
                ForEach(Array(insights.enumerated()), id: \.offset) { _, insight in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(accent)
                        Text(insight).font(.subheadline).foregroundStyle(primary).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(17)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(accent.opacity(0.20), lineWidth: 1))
    }

    private func makeInsights(_ values: SpendingSummary) -> [String] {
        var result: [String] = []
        if let top = values.highestSpendingBucket, top.total > 0 {
            let timeframe = values.period.usesDailyChart ? "يوم" : "شهر"
            result.append("أعلى إنفاق مسجل في هذه الفترة كان خلال \(timeframe) \(values.chartLabel(top.date)).")
        }
        if let category = values.topCategory {
            result.append("أعلى تصنيف إنفاقاً هو \(category.name)، بإجمالي \(SmartBillFormatting.money(category.total)).")
        }
        if let change = values.periodChange {
            let direction = change < 0 ? "انخفض" : change > 0 ? "ارتفع" : "لم يتغير"
            result.append("إنفاق الفترة \(direction) بنسبة \(String(format: "%.1f%%", locale: SmartBillFormatting.locale, abs(change))) مقارنة بالفترة السابقة.")
        }
        return result
    }

    private func categoryIcon(_ name: String) -> String {
        let value = name.lowercased()
        if name.contains("مشروب") || name.contains("قهوة") || value.contains("drink") || value.contains("beverage") { return "cup.and.saucer.fill" }
        if name.contains("مخبوز") || value.contains("bakery") { return "birthday.cake.fill" }
        if name.contains("منظف") || value.contains("clean") { return "sparkles" }
        if name.contains("منزل") || value.contains("home") { return "house.fill" }
        if name.contains("طعام") || name.contains("أطعمة") || value.contains("food") { return "fork.knife" }
        return "tag.fill"
    }

    private func storeIcon(_ name: String) -> String {
        let value = name.lowercased()
        if value.contains("panda") || name.contains("باندا") { return "basket.fill" }
        return "storefront.fill"
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large).tint(accent)
            Text("جاري تحميل فواتيرك...").font(.subheadline).foregroundStyle(secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(cardBackground)
    }

    private var errorState: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark").font(.title2).foregroundStyle(accent)
            Text("تعذر تحميل الإحصائيات").font(.headline)
            Text("تحقق من الاتصال وحاول مرة أخرى.").font(.subheadline).foregroundStyle(secondary)
            Button { Task { await fetchStatistics() } } label: {
                Label("إعادة المحاولة", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(accent)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .background(background, in: Capsule())
            }
            .disabled(isFetching)
        }
        .frame(maxWidth: .infinity).padding(22).background(cardBackground)
    }

    private func emptyState(_ title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.doc.horizontal").font(.system(size: 34, weight: .light)).foregroundStyle(accent)
            Text(title).font(.headline).foregroundStyle(primary)
            Text(subtitle).font(.subheadline).foregroundStyle(secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(24).background(cardBackground)
    }

    @MainActor
    private func fetchStatistics() async {
        guard !isFetching else { return }
        isFetching = true
        isLoading = true
        hasError = false
        defer { isFetching = false; isLoading = false }
        do {
            let rows = try await fetchRows(endpoint: "get_receipts.php")
            var itemCache: [Int: [Product]] = [:]
            for row in rows {
                let id = integerValue(row["id"])
                let inline = row["items"] as? [[String: Any]] ?? []
                if id > 0, !inline.isEmpty, inline.allSatisfy({ $0["category"] is String }) {
                    itemCache[id] = decodeProducts(inline)
                }
            }

            var loaded: [Receipt] = []
            loaded.reserveCapacity(rows.count)
            for row in rows {
                try Task.checkCancellation()
                let id = integerValue(row["id"])
                let inline = row["items"] as? [[String: Any]] ?? []
                var products = decodeProducts(inline)
                if inline.isEmpty || inline.contains(where: { !($0["category"] is String) }) {
                    guard id > 0 else { throw URLError(.cannotParseResponse) }
                    if let cached = itemCache[id] {
                        products = cached
                    } else {
                        let itemRows = try await fetchRows(endpoint: "get_items.php", query: [
                            URLQueryItem(name: "receipt_id", value: String(id))
                        ])
                        products = decodeProducts(itemRows)
                        itemCache[id] = products
                    }
                }
                let itemsTotal = Product.knownReceiptTotal(products)
                let serverTotal = numericValue(row["total"])
                let totalIsComplete = serverTotal != nil || Product.receiptPricesAreComplete(products)
                let city = (row["city"] as? String ?? row["city_name"] as? String ?? row["location"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                loaded.append(Receipt(
                    serverId: id,
                    store: row["store"] as? String ?? "",
                    total: serverTotal ?? itemsTotal,
                    totalIsComplete: totalIsComplete,
                    date: row["date"] as? String ?? "",
                    items: products,
                    city: city
                ))
            }
            try Task.checkCancellation()
            receipts = loaded
            referenceDate = Date()
        } catch {
            if !Task.isCancelled {
                hasError = true
                print("Statistics loading failed:", error)
            }
        }
    }

    private func fetchRows(endpoint: String, query: [URLQueryItem] = []) async throws -> [[String: Any]] {
        let url = try ServerConfig.endpoint(endpoint, queryItems: query)
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }
        return rows
    }

    private func decodeProducts(_ rows: [[String: Any]]) -> [Product] {
        rows.map {
            Product.receiptProduct(
                id: UUID().uuidString.hashValue,
                name: $0["name"] as? String ?? "",
                rawPrice: $0["price"],
                category: $0["category"] as? String ?? ""
            )
        }
    }

    private func integerValue(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? String { return Int(value) ?? 0 }
        return 0
    }

    private func numericValue(_ value: Any?) -> Double? {
        let number = (value as? Double) ?? Double(value as? String ?? "")
        guard let number, number.isFinite, number >= 0 else { return nil }
        return number
    }

    private var screenBackground: some View {
        background
            .overlay(alignment: .topTrailing) {
                Circle().fill(accent.opacity(0.06)).frame(width: 300, height: 300)
                    .blur(radius: 60).offset(x: 130, y: -130)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}
