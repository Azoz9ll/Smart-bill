//
//  ContentView.swift
//  Smart Bill
//
//  Purpose:
//  الشاشة الرئيسية لتحليل الفواتير، ومعها واجهات السجل والباركود.
//
//  Responsibilities:
//  - ربط الصور والكاميرا بتحليل الفاتورة وتعديل المنتجات
//  - حفظ الفاتورة بعد التأكيد ومنع تكرار الحفظ
//  - عرض الفواتير المحفوظة وتفاصيلها ونتائج مسح الباركود
//

//
//  ContentView.swift
//  Smart bill
//
//  Created by abdulaziz on 30/03/2026.
//

import SwiftUI
import Combine
// CODEX TEST
import PhotosUI
import UIKit
import MapKit
import AVFoundation

/// الشاشة الرئيسية لتحليل الفواتير، ومعها واجهات السجل والباركود.
struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab = 0
    @State private var showSavedReceipts = false
    @State private var showReceiptScanner = false
    @State private var showShoppingListPlaceholder = false
    @State private var showBestOffers = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isLoading = false
    @State private var showCamera = false
    @State private var extractedItems: [Product] = []
    @State private var storeName: String = ""
    @State private var searchText: String = ""
    @State private var showPreview = false
    @State private var showSaveConfirmation = false
    @State private var cityName: String = ""
    @State private var isSavingReceipt = false
    @State private var lastSavedSignature: String = ""
    @State private var lastSaveTime = Date.distantPast

    @State private var showBarcodeScanner = false
    @State private var scannedBarcode: String = ""
    @State private var pendingBarcode: String?
    @State private var pendingBarcodeError: String?
    @State private var isFetchingBarcode = false
    @State private var barcodeResults: [StoreProduct] = []
    @State private var showBarcodeResults = false
    @State private var barcodeErrorMessage: String = ""

    @State private var ai = VisionManager()
    @State private var isImportingImage = false
    @State private var showPhotoPicker = false
    @State private var imageRequestID = UUID()
    @State private var imageError: String?
    @State private var analysisFailed = false
    @State private var analysisFailureMessage: String?
    @State private var retryCoolingDown = false
    @State private var hasAnalyzed = false
    @State private var saveError: String?
    @State private var savedSuccessfully = false
    @State private var editingProduct: Product?
    @State private var showCameraError = false
    @State private var cameraDenied = false
    private var receiptBusy: Bool { isLoading || isSavingReceipt || isImportingImage }
    private var presentingReceiptSheet: Bool {
        showCamera || showPreview || showSavedReceipts || showBarcodeScanner || showBarcodeResults || editingProduct != nil || showPhotoPicker
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            mainView
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("الرئيسية")
                }
                .tag(0)
            
            CategoriesView()
                .tabItem {
                    Image(systemName: "tag.fill")
                    Text("منتجاتي")
                }
                .tag(1)
            
            StatisticsView()
                .tabItem {
                    Label("الإحصائيات", systemImage: "chart.bar.fill")
                }
                .tag(2)

            NavigationView {
                SettingsView()
            }
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("الإعدادات")
                }
                .tag(3)
        }
        .tint(accentColor)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SmartBillShowReceipts"))) { _ in
            selectedTab = 0
            showSavedReceipts = true
        }
        .sheet(isPresented: $showSavedReceipts) {
            SavedReceiptsView()
        }
    }

    private var mainView: some View {
        NavigationStack {
            Group {
                if showReceiptScanner {
                    ScrollView(showsIndicators: false) {
                        receiptScannerContent
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 28)
                            .frame(maxWidth: 640)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(primaryTextColor)
                    }
                    .scrollDismissesKeyboard(.interactively)
                } else {
                    HomeDashboardView(
                        onScanReceipt: { showReceiptScanner = true },
                        onComparePrices: { selectedTab = 1 },
                        onOpenShoppingList: { showShoppingListPlaceholder = true },
                        onOpenBestOffers: { showBestOffers = true },
                        onOpenReceipts: { showSavedReceipts = true }
                    )
                }
            }
            .background(screenBackground)
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(backgroundColor, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .fullScreenCover(isPresented: $showPreview) {
                receiptPreviewScreen
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraView(image: Binding(get: { selectedImage }, set: { replaceReceiptImage($0) }))
                    .overlay { ReceiptCameraGuideOverlay(accent: accentColor).allowsHitTesting(false) }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedItem, matching: .images)
            .onChange(of: selectedItem) { _, item in loadImage(from: item) }
            .sheet(item: $editingProduct) { product in
                ReceiptProductEditor(product: product) { edited in
                    if let index = extractedItems.firstIndex(where: { $0.id == edited.id }) {
                        extractedItems[index] = edited
                    } else { extractedItems.append(edited) }
                    saveError = nil
                }
            }
            .alert("تعذر الوصول إلى الكاميرا", isPresented: $showCameraError) {
                if cameraDenied {
                    Button("فتح الإعدادات") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                Button("حسناً", role: .cancel) {}
            } message: {
                Text(cameraDenied ? "اسمح بالوصول إلى الكاميرا من الإعدادات لتصوير الفواتير." : "الكاميرا غير متاحة الآن. اختر صورة من المكتبة.")
            }
            .sheet(isPresented: $showBarcodeScanner, onDismiss: finishBarcodeDismissal) {
                BarcodeScannerView(supportedTypes: [.ean13, .ean8, .upce, .code128]) { code in
                    guard pendingBarcode == nil else { return }
                    pendingBarcode = code
                    showBarcodeScanner = false
                } onFailure: { message in
                    pendingBarcodeError = message
                    showBarcodeScanner = false
                }
            }
            .alert("خطأ في الباركود", isPresented: Binding(
                get: { !barcodeErrorMessage.isEmpty },
                set: { if !$0 { barcodeErrorMessage = "" } }
            )) {
                Button("حسناً") { barcodeErrorMessage = "" }
            } message: { Text(LocalizedStringKey(barcodeErrorMessage)) }
            .sheet(isPresented: $showBarcodeResults) {
                BarcodeResultsView(results: barcodeResults)
            }
            .sheet(isPresented: $showShoppingListPlaceholder) {
                ShoppingListPlaceholderView()
            }
            .sheet(isPresented: $showBestOffers) {
                BestOffersView()
            }
        }
    }

    private var receiptScannerContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            scannerHeaderView

            VStack(alignment: .leading, spacing: 14) {
                receiptImageCard
                imageSourceButtons
                if isImportingImage {
                    ProgressView("جاري تحميل الصورة...").tint(accentColor)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                if let imageError {
                    Label(LocalizedStringKey(imageError), systemImage: "exclamationmark.circle")
                        .font(.subheadline).foregroundStyle(.red)
                }
                if selectedImage != nil {
                    Text("تأكد من وضوح الفاتورة وظهور جميع أطرافها")
                        .font(.caption).foregroundStyle(secondaryTextColor)
                    analyzeButton
                }
                if isLoading { analysisLoadingCard }
                if analysisFailed { analysisErrorCard }
                if let saveError {
                    Label(LocalizedStringKey(saveError), systemImage: "exclamationmark.circle")
                        .font(.subheadline).foregroundStyle(.red)
                }
                if savedSuccessfully {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("تم حفظ الفاتورة بنجاح", systemImage: "checkmark.circle.fill")
                            .font(.headline).foregroundStyle(accentColor)
                        Button("عرض السجل") { showSavedReceipts = true }.frame(minHeight: 44)
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardSurface())
                }
            }

            if hasAnalyzed && !isLoading {
                Text(analysisFailed ? "نتيجة التحليل السابقة" : "نتيجة التحليل")
                    .font(.title2.bold())
                receiptSummaryCard.disabled(isSavingReceipt)
                if extractedItems.isEmpty {
                    Text("لا توجد منتجات للمراجعة. أضف منتجًا أو أعد التحليل.")
                        .font(.subheadline).foregroundStyle(secondaryTextColor)
                }
                productsSection.disabled(isSavingReceipt)
                addProductButton.disabled(receiptBusy)
                saveReceiptButton
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var receiptPreviewScreen: some View {
        VStack(spacing: 18) {
            HStack {
                Text("معاينة الفاتورة").font(.headline)
                Spacer()
                Button("إغلاق") { showPreview = false }
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(primaryTextColor)

            Group {
                if let selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(10)
                } else {
                    ContentUnavailableView("لا توجد صورة للمعاينة", systemImage: "doc.viewfinder")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(cardColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(borderColor, lineWidth: 1))

            HStack(spacing: 12) {
                Button(action: retakeReceiptPhoto) {
                    Label("إعادة التصوير", systemImage: "camera")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(primaryTextColor)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(cardColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(borderColor, lineWidth: 1))
                }
                Button(action: analyzeReceiptFromPreview) {
                    Label("تحليل الفاتورة", systemImage: "sparkles")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(primaryActionTextColor)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(selectedImage == nil || receiptBusy)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(backgroundColor.ignoresSafeArea())
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func retakeReceiptPhoto() {
        showPreview = false
        replaceReceiptImage(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { openReceiptCamera() }
    }

    private func analyzeReceiptFromPreview() {
        showPreview = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { processImage() }
    }

    // MARK: - Main receipt screen

    private var accentColor: Color {
        colorScheme == .dark
        ? Color(red: 0.40, green: 0.63, blue: 0.51)
        : Color(red: 0.20, green: 0.48, blue: 0.36)
    }

    private var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.025, green: 0.04, blue: 0.04)
        : Color(red: 0.965, green: 0.975, blue: 0.97)
    }

    private var cardColor: Color {
        colorScheme == .dark
        ? Color(red: 0.075, green: 0.095, blue: 0.095)
        : Color.white
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : Color(red: 0.07, green: 0.10, blue: 0.09)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.58) : .black.opacity(0.56)
    }

    private var borderColor: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08)
    }

    private var screenBackground: some View {
        backgroundColor
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(accentColor.opacity(0.07))
                    .frame(width: 320, height: 320)
                    .blur(radius: 60)
                    .offset(x: 140, y: -140)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    /// ينشئ خلفية البطاقة وحدودها وفق تنسيق الشاشة.
    private func cardSurface(cornerRadius: CGFloat = 18) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(cardColor)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
    }

    private var scannerHeaderView: some View {
        HStack(spacing: 10) {
            Button { showReceiptScanner = false } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(primaryTextColor)
                    .frame(width: 44, height: 44)
                    .background(cardColor, in: Circle())
                    .overlay(Circle().strokeBorder(borderColor, lineWidth: 1))
            }
            .accessibilityLabel("رجوع إلى الرئيسية")

            VStack(alignment: .leading, spacing: 5) {
                Text("مسح فاتورة").font(.title3.bold()).foregroundStyle(primaryTextColor)
                Text("صوّر فاتورتك وسنستخرج المنتجات والأسعار تلقائياً.")
                    .font(.caption).foregroundStyle(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { showSavedReceipts = true } label: { headerIcon("clock.arrow.circlepath") }
                .accessibilityLabel("سجل الفواتير")
            Button { showBarcodeScanner = true } label: { headerIcon("barcode.viewfinder") }
                .accessibilityLabel("مسح الباركود")
        }
        .buttonStyle(.plain)
        .disabled(receiptBusy || presentingReceiptSheet || isFetchingBarcode)
        .padding(.vertical, 4)
    }

    /// ينشئ أيقونة رأس الشاشة وفق تنسيق الشاشة.
    private func headerIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(accentColor)
            .frame(width: 48, height: 48)
            .background(cardColor, in: Circle())
            .overlay(Circle().strokeBorder(accentColor.opacity(0.18), lineWidth: 1))
    }

    private var receiptImageCard: some View {
        Group {
            if let image = selectedImage {
                Button {
                    showPreview = true
                } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("معاينة الفاتورة")
                .background(cardSurface(cornerRadius: 22))
                .overlay(alignment: .topLeading) {
                    Button {
                        replaceReceiptImage(nil)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.red.opacity(0.85))
                            .frame(width: 26, height: 26)
                            .background(cardColor, in: Circle())
                            .overlay(Circle().strokeBorder(borderColor, lineWidth: 1))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("إزالة صورة الفاتورة")
                    .padding(4)
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(cardColor)
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 1))
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.viewfinder")
                            .font(.system(size: 56, weight: .light))
                            .foregroundStyle(accentColor)
                            .padding(.bottom, 4)
                        Text("ضع الفاتورة داخل الإطار")
                            .font(.headline).foregroundStyle(primaryTextColor)
                        Text("تأكد من ظهور جميع المنتجات والأسعار بوضوح")
                            .font(.subheadline).foregroundStyle(secondaryTextColor)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)

                    ReceiptScanFrameCorners()
                        .stroke(accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .padding(14)
                        .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, minHeight: 270)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .disabled(receiptBusy)
    }

    private var imageSourceButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { cameraButton; galleryButton }
            VStack(spacing: 12) { cameraButton; galleryButton }
        }
        .buttonStyle(.plain)
        .disabled(receiptBusy || presentingReceiptSheet)
    }
    private var cameraButton: some View {
        Button { openReceiptCamera() } label: {
            imageSourceLabel("تصوير فاتورة", symbol: "camera.fill", emphasized: true)
        }
    }
    private var galleryButton: some View {
        Button { showPhotoPicker = true } label: {
            imageSourceLabel(selectedImage == nil ? "اختيار من الصور" : "تغيير الصورة", symbol: "photo", emphasized: false)
        }
    }

    /// ينشئ عنوان زر اختيار مصدر الصورة وفق تنسيق الشاشة.
    private func imageSourceLabel(_ title: LocalizedStringKey, symbol: String, emphasized: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(emphasized ? primaryActionTextColor : accentColor)
            Text(title)
                .foregroundStyle(emphasized ? primaryActionTextColor : primaryTextColor)
        }
        .font(.body.weight(.semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 17)
        .background(emphasized ? accentColor : cardColor, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(emphasized ? accentColor : borderColor, lineWidth: 1)
        }
        .shadow(color: emphasized ? accentColor.opacity(0.18) : .clear, radius: 10, y: 4)
    }

    private var analyzeButton: some View {
        Button {
            processImage()
        } label: {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView().tint(primaryActionTextColor)
                    Text("جاري تحليل الفاتورة...")
                } else {
                    Image(systemName: "sparkles")
                    Text("تحليل الفاتورة")
                }
            }
            .font(.body.bold())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 19)
            .foregroundStyle(selectedImage == nil && !isLoading ? secondaryTextColor : primaryActionTextColor)
            .background {
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient(
                        colors: selectedImage == nil && !isLoading
                        ? [cardColor, cardColor]
                        : [accentColor, accentColor.opacity(0.80)],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    ))
            }
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(borderColor, lineWidth: 1))
            .shadow(color: accentColor.opacity(selectedImage == nil ? 0 : 0.14), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(selectedImage == nil || receiptBusy || presentingReceiptSheet || retryCoolingDown)
    }

    private var primaryActionTextColor: Color {
        colorScheme == .dark ? Color(red: 0.025, green: 0.04, blue: 0.04) : .white
    }

    private var receiptSummaryCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "storefront.fill")
                    .font(.title3)
                    .foregroundStyle(accentColor)
                    .frame(width: 44, height: 44)
                    .background(accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text("المتجر")
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                    Text(storeName.isEmpty ? "غير معروف" : storeName)
                        .font(.headline)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Image(systemName: "location.fill")
                    .foregroundStyle(accentColor)
                TextField("اسم المدينة", text: $cityName)
                    .font(.subheadline)
                    .accessibilityLabel("اسم المدينة")
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 12))

            Rectangle().fill(borderColor).frame(height: 1)

            HStack(alignment: .center) {
                Label("\(extractedItems.count) منتجات", systemImage: "list.bullet.rectangle")
                    .font(.subheadline)
                    .foregroundStyle(secondaryTextColor)
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(extractedItems.contains(where: { !$0.priceAvailable }) ? "المجموع الجزئي" : "إجمالي المنتجات")
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                    HStack(spacing: 5) {
                        Text(SmartBillFormatting.money(extractedItems.filter(\.priceAvailable).reduce(0) { $0 + $1.price }))
                            .monospacedDigit()
                    }
                    .font(.title2.bold())
                    .foregroundStyle(accentColor)
                    .environment(\.layoutDirection, .leftToRight)
                }
            }
        }
        .padding(18)
        .background(cardSurface(cornerRadius: 22))
    }

    private var productsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("المنتجات")
                    .font(.title3.bold())
                Spacer()
                Text("\(extractedItems.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(accentColor.opacity(0.12), in: Capsule())
            }
            ForEach(extractedItems) { item in
                productRow(item)
            }
        }
    }

    /// ينشئ صف بيانات المنتج وفق تنسيق الشاشة.
    private func productRow(_ item: Product) -> some View {
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(SmartBillFormatting.digits(item.name)).font(.headline)
                    SmartBillCategoryLabel(category: item.category).font(.caption).foregroundStyle(accentColor)
                        .padding(6).background(accentColor.opacity(0.10), in: Capsule())
                }
                Spacer(minLength: 8)
                Text(item.priceAvailable ? SmartBillFormatting.money(item.price) : "غير متوفر")
                    .font(.subheadline.bold()).monospacedDigit()
            }
            HStack {
                Button { editingProduct = item } label: { Label("تعديل", systemImage: "pencil") }
                Spacer()
                Button(role: .destructive) { extractedItems.removeAll { $0.id == item.id }; saveError = nil } label: {
                    Label("حذف", systemImage: "trash")
                }
            }.font(.caption).buttonStyle(.borderless).frame(minHeight: 44)
        }.padding(16).background(cardSurface(cornerRadius: 16))
    }

    private var addProductButton: some View {
        Button {
            editingProduct = Product(id: UUID().uuidString.hashValue, name: "", price: 0, category: "أخرى")
        } label: {
            Label("إضافة منتج", systemImage: "plus")
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(accentColor).background(cardSurface())
        }.buttonStyle(.plain)
    }

    private var saveReceiptButton: some View {
        Button {
            if !isSavingReceipt {
                showSaveConfirmation = true
            }
        } label: {
            HStack(spacing: 10) {
                if isSavingReceipt {
                    ProgressView().tint(accentColor)
                    Text("جاري الحفظ...")
                } else {
                    Image(systemName: "square.and.arrow.down")
                    Text("حفظ الفاتورة")
                }
            }
            .font(.body.bold())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .foregroundStyle(primaryTextColor)
            .background(accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 18))
            .background(cardColor, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(accentColor.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(receiptBusy || extractedItems.isEmpty)
        .alert("تأكيد الحفظ", isPresented: $showSaveConfirmation) {
            Button("إلغاء", role: .cancel) {}
            Button("حفظ") {
                guard !isSavingReceipt else { return }
                saveReceiptToServer(store: storeName, items: extractedItems)
            }
        } message: {
            Text("هل تريد حفظ الفاتورة؟")
        }
    }

    var filteredItems: [Product] {
        extractedItems.filter {
            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var analysisLoadingCard: some View {
        TimelineView(.periodic(from: .now, by: 1.6)) { timeline in
            let activeStep = Int(timeline.date.timeIntervalSinceReferenceDate / 1.6) % 3
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ProgressView().tint(accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("جاري تحليل الفاتورة").font(.headline)
                        Text("قد يستغرق هذا بضع ثوانٍ").font(.caption).foregroundStyle(secondaryTextColor)
                    }
                }
                ForEach(Array(["جاري قراءة الفاتورة", "استخراج المنتجات والأسعار", "التحقق من البيانات"].enumerated()), id: \.offset) { index, message in
                    HStack(spacing: 10) {
                        Image(systemName: index == activeStep ? "arrow.triangle.2.circlepath" : "circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(index == activeStep ? accentColor : secondaryTextColor.opacity(0.65))
                        Text(message)
                            .font(.subheadline.weight(index == activeStep ? .semibold : .regular))
                            .foregroundStyle(index == activeStep ? primaryTextColor : secondaryTextColor)
                    }
                    .animation(.easeInOut(duration: 0.25), value: activeStep)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardSurface())
        }
    }
    private var analysisErrorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("تعذر تحليل الفاتورة", systemImage: "exclamationmark.circle").font(.headline)
            if let analysisFailureMessage {
                Text(LocalizedStringKey(analysisFailureMessage))
            } else {
                Text("لم نعثر على منتجات واضحة في الفاتورة.")
            }
            Text("يمكنك إعادة المحاولة أو مراجعة الصورة وإضافة المنتجات يدويًا.").foregroundStyle(secondaryTextColor)
            Button(retryCoolingDown ? "إعادة المحاولة بعد لحظات" : "إعادة المحاولة") { processImage() }
                .frame(minHeight: 44).disabled(retryCoolingDown)
            Button("اختيار صورة أخرى") { showPhotoPicker = true }.frame(minHeight: 44)
        }.font(.subheadline).padding(18).background(cardSurface()).disabled(receiptBusy)
    }

    private func openReceiptCamera() {
        guard !receiptBusy, !presentingReceiptSheet else { return }
        cameraDenied = AVCaptureDevice.authorizationStatus(for: .video) == .denied
        guard UIImagePickerController.isSourceTypeAvailable(.camera), !cameraDenied,
              AVCaptureDevice.authorizationStatus(for: .video) != .restricted else {
            showCameraError = true; return
        }
        showCamera = true
    }

    /// تغيير الصورة يلغي نتائج الصورة السابقة، ولا يبدأ التحليل تلقائيًا.
    private func replaceReceiptImage(_ image: UIImage?) {
        guard !isLoading, !isSavingReceipt else { return }
        selectedImage = image; extractedItems = []; storeName = ""
        hasAnalyzed = false; analysisFailed = false; analysisFailureMessage = nil; savedSuccessfully = false
        imageError = nil; saveError = nil
        guard image != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard selectedImage != nil, !showCamera, !showPhotoPicker else { return }
            showPreview = true
        }
    }

    /// يحافظ على الصورة السابقة عند فشل الاستيراد ويرفض استجابة اختيار قديم.
    func loadImage(from item: PhotosPickerItem?) {
        guard let item, !isLoading, !isSavingReceipt else { return }
        let requestID = UUID(); imageRequestID = requestID
        isImportingImage = true; imageError = nil
        Task {
            defer {
                if imageRequestID == requestID { isImportingImage = false; selectedItem = nil }
            }
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
                let displayImage = await image.byPreparingForDisplay() ?? image
                guard imageRequestID == requestID else { return }
                replaceReceiptImage(displayImage)
            } catch {
                guard imageRequestID == requestID else { return }
                imageError = "تعذر تحميل الصورة. اختر صورة صالحة وحاول مرة أخرى."
            }
        }
    }

    /// VisionManager يمتلك إعادة المحاولة الداخلية؛ لا نضاعف طلباته من الواجهة.
    func processImage() {
        guard let image = selectedImage, !receiptBusy, !presentingReceiptSheet, !retryCoolingDown else { return }
        isLoading = true; analysisFailed = false; analysisFailureMessage = nil; saveError = nil; savedSuccessfully = false
        ai.process(image: image) { store, items in
            DispatchQueue.main.async {
                isLoading = false
                guard !items.isEmpty else {
                    analysisFailed = true
                    analysisFailureMessage = ai.lastFailureMessage
                    // ننتظر انتهاء ذاكرة VisionManager القصيرة قبل طلب محاولة جديدة صريحة.
                    retryCoolingDown = true
                    Task {
                        try? await Task.sleep(for: .seconds(3))
                        retryCoolingDown = false
                    }
                    return
                }
                analysisFailureMessage = nil
                storeName = store
                extractedItems = items.map { Product(id: UUID().uuidString.hashValue, name: $0.0, price: $0.1 ?? 0, category: $0.2, priceAvailable: $0.1 != nil) }
                hasAnalyzed = true
            }
        }
    }

    /// مسار الحفظ الوحيد لهذه الشاشة؛ لا يمسح المسودة إلا بعد تأكيد نجاح الخادم.
    func saveReceiptToServer(store: String, items: [Product]) {
        guard !receiptBusy else { return }
        guard !items.isEmpty, items.allSatisfy({ $0.priceAvailable && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.price.isFinite && $0.price >= 0 && $0.price <= 100_000 }) else {
            saveError = "راجع أسماء المنتجات وأسعارها قبل الحفظ."; return
        }
        guard let url = URL(string: "\(ServerConfig.baseURL)/save_receipt.php") else {
            saveError = "تعذر حفظ الفاتورة. حاول مرة أخرى."; return
        }
        let signature = "\(store)|\(cityName)|" + items.map { "\($0.name)|\($0.price)|\($0.category)" }.sorted().joined(separator: ";")
        guard signature != lastSavedSignature || Date().timeIntervalSince(lastSaveTime) >= 60 else {
            saveError = "تم إرسال هذه الفاتورة مؤخرًا. راجع السجل قبل إعادة الحفظ."; return
        }
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let body: [String: Any] = ["store": store, "city": cityName,
            "total": items.reduce(0) { $0 + $1.price }, "date": formatter.string(from: Date()),
            "items": items.map { ["name": $0.name, "price": $0.price, "category": $0.category] as [String: Any] }]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            saveError = "تعذر تجهيز الفاتورة للحفظ."; return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = data
        isSavingReceipt = true; saveError = nil
        lastSavedSignature = signature; lastSaveTime = Date()
        Task {
            defer { isSavingReceipt = false }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      ReceiptSaveAcknowledgement.succeeded(data) else {
                    saveError = "لم يؤكد الخادم حفظ الفاتورة. بياناتك محفوظة هنا؛ راجع السجل قبل إعادة المحاولة."
                    return
                }
                savedSuccessfully = true
                selectedImage = nil; selectedItem = nil; extractedItems = []; storeName = ""
                hasAnalyzed = false; analysisFailed = false
            } catch {
                saveError = "تعذر تأكيد الحفظ بسبب الاتصال. راجع السجل قبل إعادة المحاولة لتجنب التكرار."
            }
        }
    }

    /// يمثل نتيجة البحث عن منتج بالباركود من خادم Smart Bill.
    nonisolated struct StoreProduct: Identifiable, Decodable {
        let id = UUID()
        let store: String
        let price: Double
        let name: String
        let barcode: String

        /// يربط خصائص النموذج بمفاتيح JSON المستخدمة في القراءة أو الكتابة.
        enum CodingKeys: String, CodingKey {
            case store
            case price
            case name
            case barcode
        }

        /// PHP قد يعيد DECIMAL كنص؛ الباركود يظل String ولا يفقد الأصفار الأولى.
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            store = try values.decode(String.self, forKey: .store)
            name = try values.decode(String.self, forKey: .name)
            barcode = try values.decode(String.self, forKey: .barcode)
            if let number = try? values.decode(Double.self, forKey: .price) { price = number }
            else {
                let text = try values.decode(String.self, forKey: .price)
                guard let number = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    throw DecodingError.dataCorruptedError(forKey: .price, in: values, debugDescription: "Invalid price")
                }
                price = number
            }
            guard price.isFinite, price >= 0 else {
                throw DecodingError.dataCorruptedError(forKey: .price, in: values, debugDescription: "Invalid price")
            }
        }
    }

    /// نبدأ البحث بعد انتهاء إغلاق sheet حتى لا تضيع نافذة النتائج أثناء الانتقال.
    private func finishBarcodeDismissal() {
        if let error = pendingBarcodeError {
            pendingBarcodeError = nil; pendingBarcode = nil
            barcodeErrorMessage = error
        } else if let code = pendingBarcode {
            pendingBarcode = nil
            handleScannedBarcode(code)
        }
    }
    func handleScannedBarcode(_ code: String) {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, !isFetchingBarcode else { return }
        scannedBarcode = code
        fetchProductByBarcode(code)
    }
    func fetchProductByBarcode(_ code: String) {
        guard !isFetchingBarcode else { return }
        let barcode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !barcode.isEmpty else { return }
        var components = URLComponents(string: "\(ServerConfig.baseURL)/get_product_by_barcode.php")
        components?.queryItems = [URLQueryItem(name: "barcode", value: barcode)]
        guard let url = components?.url else { barcodeErrorMessage = "تعذر تجهيز طلب البحث"; return }
        isFetchingBarcode = true; barcodeErrorMessage = ""; barcodeResults = []
        #if DEBUG
        print("Looking up barcode: \(barcode)")
        #endif
        Task {
            defer { isFetchingBarcode = false }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"; request.timeoutInterval = 25
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    barcodeErrorMessage = "استجابة غير صالحة من الخادم"; return
                }
                #if DEBUG
                print("Barcode lookup HTTP: \(http.statusCode)")
                #endif
                guard (200...299).contains(http.statusCode) else {
                    barcodeErrorMessage = "تعذر البحث عن المنتج بسبب خطأ في الخادم"; return
                }
                let decoder = JSONDecoder()
                let products: [StoreProduct]
                do {
                    if let array = try? decoder.decode([StoreProduct].self, from: data) { products = array }
                    else { products = [try decoder.decode(StoreProduct.self, from: data)] }
                } catch {
                    #if DEBUG
                    print("Barcode lookup: JSON decoding failed")
                    #endif
                    barcodeErrorMessage = "تعذر قراءة بيانات المنتج من الخادم"; return
                }
                #if DEBUG
                print("Barcode lookup succeeded: \(products.count) result(s)")
                #endif
                barcodeResults = products.sorted { $0.price < $1.price }
                showBarcodeResults = true
            } catch {
                #if DEBUG
                print("Barcode lookup: network failed")
                #endif
                barcodeErrorMessage = "تعذر الاتصال بالخادم، حاول مرة أخرى"
            }
        }
    }

}

/// تُرسل أوامر التشغيل والإيقاف بالتتابع خارج الخيط الرئيسي.
/// إعداد المدخلات والمخرجات يكتمل قبل التشغيل؛ لا يعاد ضبط الجلسة أثناء الالتقاط.
nonisolated private final class BarcodeSessionRunner: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "smartbill.barcode.session")
    func start() { queue.async { if !self.session.isRunning { self.session.startRunning() } } }
    func stop() { queue.async { if self.session.isRunning { self.session.stopRunning() } } }
}

/// نفس الماسح الحالي؛ SwiftUI وحده يملك إغلاق العرض.
struct BarcodeScannerView: UIViewControllerRepresentable {
    var supportedTypes: [AVMetadataObject.ObjectType]
    var onCodeScanned: (String) -> Void
    var onFailure: (String) -> Void
    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.supportedTypes = supportedTypes
        controller.onCodeScanned = onCodeScanned
        controller.onFailure = onFailure
        return controller
    }
    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
    static func dismantleUIViewController(_ uiViewController: ScannerViewController, coordinator: ()) {
        uiViewController.stopScanning()
    }
    final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        private let runner = BarcodeSessionRunner()
        private var previewLayer: AVCaptureVideoPreviewLayer?
        var supportedTypes: [AVMetadataObject.ObjectType] = []
        var onCodeScanned: ((String) -> Void)?
        var onFailure: ((String) -> Void)?
        private var didSend = false
        private var visible = false
        private var configured = false
        private var requestingPermission = false

        override func viewDidLoad() { super.viewDidLoad(); view.backgroundColor = .black }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            visible = true
            guard !didSend else { return }
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: setupCamera()
            case .notDetermined:
                guard !requestingPermission,
                      Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil else {
                    fail("تعذر الوصول إلى الكاميرا"); return
                }
                requestingPermission = true
                AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                    DispatchQueue.main.async {
                        guard let self, self.visible, !self.didSend else { return }
                        self.requestingPermission = false
                        if allowed { self.setupCamera() }
                        else { self.fail("اسمح بالوصول إلى الكاميرا من الإعدادات لمسح الباركود") }
                    }
                }
            default: fail("اسمح بالوصول إلى الكاميرا من الإعدادات لمسح الباركود")
            }
        }
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer?.frame = view.bounds
        }
        private func setupCamera() {
            guard visible, !didSend else { return }
            if configured { runner.start(); return }
            let session = runner.session
            session.beginConfiguration()
            session.sessionPreset = .high
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
                session.commitConfiguration(); fail("تعذر تشغيل كاميرا الباركود"); return
            }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                session.commitConfiguration(); fail("تعذر تجهيز قارئ الباركود"); return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            let types = supportedTypes.filter { output.availableMetadataObjectTypes.contains($0) }
            guard types.contains(.ean13) else {
                session.commitConfiguration(); fail("قراءة EAN-13 غير متاحة على هذه الكاميرا"); return
            }
            output.metadataObjectTypes = types
            session.commitConfiguration()
            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = view.bounds
            view.layer.addSublayer(preview); previewLayer = preview
            configured = true
            #if DEBUG
            print("Barcode scanner enabled types: \(types.map(\.rawValue))")
            #endif
            runner.start()
        }
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard visible, !didSend else { return }
            guard let code = metadataObjects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue })
                .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).first(where: { !$0.isEmpty }) else { return }
            didSend = true
            runner.stop()
            #if DEBUG
            print("Detected barcode: \(code)")
            #endif
            onCodeScanned?(code)
        }
        private func fail(_ message: String) {
            guard !didSend else { return }
            didSend = true; runner.stop()
            #if DEBUG
            print("Barcode scanner: camera setup failed")
            #endif
            onFailure?(message)
        }
        func stopScanning() { visible = false; runner.stop() }
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated); stopScanning()
        }
    }
}

/// يعرض المنتجات والأسعار التي أعادها بحث الباركود.
struct BarcodeResultsView: View {
    let results: [ContentView.StoreProduct]

    var body: some View {
        NavigationView {
            VStack(alignment: .leading) {
                if results.isEmpty {
                    Text("المنتج غير موجود")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    List(results) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(SmartBillFormatting.digits(item.name))
                                    .font(.headline)
                                Text(SmartBillFormatting.digits(item.store))
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            HStack(spacing: 2) {
                                Text(SmartBillFormatting.money(item.price))
                                    .bold()
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("نتائج الباركود")
        }
    }
}

/// يعرض عناصر نتيجة التحليل داخل نافذة مستقلة.
struct ResultSheetView: View {
    
    var store: String
    @State var items: [Product]
    var onSave: (() -> Void)?
    @State private var showSavedAlert = false
    @State private var newName = ""
    @State private var newPrice = ""
    @State private var showAdd = false
    
    var body: some View {
        VStack(spacing: 16) {
            
            // Handle (top drag indicator)
            Capsule()
                .fill(Color.gray.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, 8)
            
            // Title
            Text("النتائج")
                .font(.title.bold())
            
            // Store Card
            VStack(alignment: .leading, spacing: 6) {
                Text("المتجر")
                    .foregroundColor(.gray)
                
                Text(store.isEmpty ? "غير معروف" : store)
                    .font(.headline)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .cornerRadius(14)
            
            // Table Header
            HStack {
                Text("المنتج")
                    .bold()
                Spacer()
                Text("السعر")
                    .bold()
            }
            .padding(.horizontal)
            
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(items.indices, id: \.self) { index in
                        HStack {
                            TextField("اسم المنتج", text: Binding(
                                get: { items[index].name },
                                set: { items[index].name = $0 }
                            ))
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                TextField("0.0", text: Binding(
                                    get: { String(format: "%.2f", locale: SmartBillFormatting.locale, items[index].price) },
                                    set: { items[index].price = Double($0) ?? 0 }
                                ))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                Text("⃁")
                            }
                            .environment(\.layoutDirection, .leftToRight)
                            .frame(width: 90)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }
                }
            }
            
            Button {
                showAdd = true
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("إضافة منتج")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(14)
            }
            
            // Save Button
            Button {
                onSave?()
                showSavedAlert = true
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.down.fill")
                    Text("حفظ الفاتورة")
                        .bold()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                .foregroundColor(.white)
                .cornerRadius(18)
                .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            
        }
        .alert("تم الحفظ", isPresented: $showSavedAlert) {
            Button("تمام", role: .cancel) {}
        }
        .sheet(isPresented: $showAdd) {
            VStack(spacing: 16) {
                TextField("اسم المنتج", text: $newName)
                    .textFieldStyle(.roundedBorder)
                
                TextField("السعر", text: $newPrice)
                    .onChange(of: newPrice) { _, value in newPrice = SmartBillFormatting.digits(value) }
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                
                Button("إضافة") {
                    let price = Double(newPrice) ?? 0
                    items.append(Product(id: UUID().uuidString.hashValue, name: newName, price: price, category: "manual"))
                    newName = ""
                    newPrice = ""
                    showAdd = false
                }
            }
            .padding()
        }
        .padding()
    }
}


// MARK: - Saved receipts styling

/// يجمع ألوان ومكونات واجهات الفواتير للوضعين الفاتح والداكن.
private struct ReceiptTheme {
    let colorScheme: ColorScheme

    var accentColor: Color {
        colorScheme == .dark
        ? Color(red: 0.40, green: 0.63, blue: 0.51)
        : Color(red: 0.20, green: 0.48, blue: 0.36)
    }

    var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.025, green: 0.04, blue: 0.04)
        : Color(red: 0.965, green: 0.975, blue: 0.97)
    }

    var cardColor: Color {
        colorScheme == .dark
        ? Color(red: 0.075, green: 0.095, blue: 0.095)
        : .white
    }

    var primaryTextColor: Color {
        colorScheme == .dark ? .white : Color(red: 0.07, green: 0.10, blue: 0.09)
    }

    var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.58) : .black.opacity(0.56)
    }

    var borderColor: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08)
    }

    var background: some View {
        backgroundColor
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(accentColor.opacity(0.06))
                    .frame(width: 280, height: 280)
                    .blur(radius: 60)
                    .offset(x: 120, y: -130)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    /// ينشئ خلفية البطاقة وحدودها وفق تنسيق الشاشة.
    func cardSurface(emphasized: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(cardColor)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(accentColor.opacity(emphasized ? 0.10 : 0))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(emphasized ? accentColor.opacity(0.28) : borderColor, lineWidth: 1)
            }
    }

    /// ينشئ الأيقونة الموحدة وفق تنسيق الشاشة.
    func icon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(accentColor)
            .frame(width: 50, height: 50)
            .background(accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityHidden(true)
    }
}

/// يعرض قيمة مالية بتنسيق مناسب لواجهات الفواتير.
private struct ReceiptAmount: View {
    let value: Double

    var body: some View {
        HStack(spacing: 5) {
            Text(SmartBillFormatting.money(value))
                .monospacedDigit()
        }
        .environment(\.layoutDirection, .leftToRight)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(String(format: "%.2f", locale: SmartBillFormatting.locale, value)) ريال سعودي")
    }
}

/// يحمل الفواتير المحفوظة ويتيح فتح تفاصيل كل فاتورة.
struct SavedReceiptsView: View {
    @State private var receipts: [Receipt] = []
    @State private var isLoading = false
    @State private var selectedReceipt: Receipt?
    @State private var searchText = ""
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.dismiss) private var dismiss

    private var theme: ReceiptTheme { ReceiptTheme(colorScheme: colorScheme) }

    private var filteredReceipts: [Receipt] {
        guard !searchText.isEmpty else { return receipts }
        return receipts.filter {
            $0.store.localizedCaseInsensitiveContains(searchText)
            || $0.city.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                headerView
                searchBar

                if !receipts.isEmpty {
                    summaryCard
                }

                if isLoading {
                    centeredState {
                        ProgressView()
                            .tint(theme.accentColor)
                            .controlSize(.large)
                        Text("جاري تحميل الفواتير...")
                            .font(.subheadline)
                            .foregroundStyle(theme.secondaryTextColor)
                    }
                } else if receipts.isEmpty {
                    emptyState(
                        symbol: "doc.text.magnifyingglass",
                        title: "لا توجد فواتير محفوظة",
                        subtitle: "بعد حفظ أول فاتورة ستظهر هنا"
                    )
                } else if filteredReceipts.isEmpty {
                    emptyState(
                        symbol: "magnifyingglass",
                        title: "لا توجد نتائج",
                        subtitle: "جرّب البحث باسم متجر أو مدينة مختلفة"
                    )
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredReceipts) { receipt in
                                Button {
                                    selectedReceipt = receipt
                                } label: {
                                    receiptCard(receipt)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("فتح تفاصيل الفاتورة")
                            }
                        }
                        .padding(.bottom, 20)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(theme.primaryTextColor)
            .background(theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                fetchReceipts()
            }
            .sheet(item: $selectedReceipt) { receipt in
                ReceiptDetailView(receipt: receipt)
            }
        }
        .tint(theme.accentColor)
    }

    private var headerView: some View {
        HStack(spacing: 12) {
            theme.icon("doc.text.fill")
            VStack(alignment: .leading, spacing: 5) {
                Text("الفواتير")
                    .font(.system(.title, design: .rounded, weight: .bold))
                Text("سجل فواتيرك السابقة")
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryTextColor)
            }
            Spacer(minLength: 0)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.secondaryTextColor)
                    .frame(width: 44, height: 44)
                    .background(theme.cardColor, in: Circle())
                    .overlay(Circle().strokeBorder(theme.borderColor, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("إغلاق الفواتير")
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.accentColor)
            TextField("ابحث عن متجر أو مدينة", text: $searchText)
                .font(.subheadline)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.secondaryTextColor)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("مسح البحث")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 54)
        .background(theme.cardSurface())
    }

    private var summaryCard: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                receiptCount
                Spacer(minLength: 12)
                spendingTotal
            }
            VStack(alignment: .leading, spacing: 16) {
                receiptCount
                spendingTotal
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(theme.cardSurface(emphasized: true))
    }

    private var receiptCount: some View {
        Label("\(receipts.count) فاتورة", systemImage: "doc.text")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(theme.accentColor)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var spendingTotal: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(receipts.contains(where: { !$0.totalIsComplete }) ? "المجموع الجزئي للمشتريات" : "إجمالي المشتريات")
                .font(.caption)
                .foregroundStyle(theme.secondaryTextColor)
            if receipts.contains(where: \.hasKnownTotal) {
                ReceiptAmount(value: receipts.reduce(0) { $0 + $1.total })
                    .font(.title2.bold())
                    .foregroundStyle(theme.accentColor)
            } else {
                Text(receipts.isEmpty ? SmartBillFormatting.money(Double.zero) : "غير متوفر")
                    .font(.title2.bold())
                    .foregroundStyle(theme.accentColor)
            }
        }
    }

    /// ينشئ بطاقة الفاتورة وفق تنسيق الشاشة.
    private func receiptCard(_ receipt: Receipt) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                theme.icon("storefront.fill")
                VStack(alignment: .leading, spacing: 8) {
                    Text(receipt.store.isEmpty ? "متجر غير معروف" : receipt.store)
                        .font(.headline)
                    Label(receipt.city.isEmpty ? "لا توجد مدينة" : receipt.city, systemImage: "location.fill")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryTextColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: layoutDirection == .rightToLeft ? "chevron.left" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.secondaryTextColor)
                    .padding(.top, 6)
                    .accessibilityHidden(true)
            }

            Label(formatDate(receipt.date), systemImage: "clock")
                .font(.caption)
                .foregroundStyle(theme.secondaryTextColor)

            Rectangle().fill(theme.borderColor).frame(height: 1)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    itemCount(for: receipt)
                    Spacer(minLength: 8)
                    receiptTotal(receipt)
                }
                VStack(alignment: .leading, spacing: 10) {
                    itemCount(for: receipt)
                    receiptTotal(receipt)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cardSurface())
    }

    @ViewBuilder
    /// ينشئ عدد عناصر الفاتورة وفق تنسيق الشاشة.
    private func itemCount(for receipt: Receipt) -> some View {
        // An empty array may mean the API omitted items; don't present it as a known count.
        if !receipt.items.isEmpty {
            Label("\(receipt.items.count) منتجات", systemImage: "cart.fill")
                .font(.caption)
                .foregroundStyle(theme.secondaryTextColor)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// ينشئ إجمالي الفاتورة وفق تنسيق الشاشة.
    private func receiptTotal(_ receipt: Receipt) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(receipt.totalIsComplete ? "الإجمالي" : "مجموع جزئي")
                .font(.caption)
                .foregroundStyle(theme.secondaryTextColor)
            if receipt.hasKnownTotal {
                ReceiptAmount(value: receipt.total)
                    .font(.title3.bold())
                    .foregroundStyle(theme.accentColor)
            } else {
                Text("غير متوفر")
                    .font(.title3.bold())
                    .foregroundStyle(theme.secondaryTextColor)
            }
        }
    }

    /// ينشئ محتوى حالة وسط الشاشة وفق تنسيق الشاشة.
    private func centeredState<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 16, content: content)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// ينشئ حالة عدم وجود بيانات وفق تنسيق الشاشة.
    private func emptyState(symbol: String, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        centeredState {
            Image(systemName: symbol)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(theme.accentColor)
                .frame(width: 96, height: 96)
                .background(theme.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 28))
                .accessibilityHidden(true)
            Text(title)
                .font(.title3.bold())
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(theme.secondaryTextColor)
        }
    }

    /// يحول تاريخ الخادم إلى نص عرض وفق التنسيقات المدعومة.
    func formatDate(_ dateString: String) -> String {
        SmartBillFormatting.relativeDate(dateString)
    }

    /// يحمل الفواتير المحفوظة من مسار PHP ويحدث قائمة السجل.
    func fetchReceipts() {
        guard let url = URL(string: "\(ServerConfig.baseURL)/get_receipts.php") else { return }
        
        isLoading = true
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            defer { DispatchQueue.main.async { isLoading = false } }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
            
            let result = json.map { item -> Receipt in
                
                let itemsArray = item["items"] as? [[String: Any]] ?? []
                
                let products = itemsArray.map {
                    Product.receiptProduct(
                        id: UUID().uuidString.hashValue,
                        name: $0["name"] as? String ?? "",
                        rawPrice: $0["price"],
                        category: $0["category"] as? String ?? ""
                    )
                }
                
                let total = Product.knownReceiptTotal(products)
                let totalIsComplete = Product.receiptPricesAreComplete(products)

                let cityValue = (
                    item["city"] as? String ??
                    item["city_name"] as? String ??
                    item["location"] as? String ?? ""
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                #if DEBUG
                print("Receipt history loaded: \(products.count) products; total complete: \(totalIsComplete)")
                #endif

                return Receipt(
                    serverId: item["id"] as? Int ?? 0,
                    store: item["store"] as? String ?? "",
                    total: total,
                    totalIsComplete: totalIsComplete,
                    date: item["date"] as? String ?? "",
                    items: products,
                    city: cityValue
                )
            }
            DispatchQueue.main.async {
                receipts = result
            }
        }.resume()
    }
}

// MARK: - Receipt Model

/// يمثل فاتورة محملة من الخادم مع المتجر والتاريخ والعناصر والمدينة.
struct Receipt: Identifiable {
    var id = UUID()
    var serverId: Int
    var store: String
    var total: Double
    var totalIsComplete: Bool
    var date: String
    var items: [Product]
    var city: String

    var hasKnownTotal: Bool { items.contains(where: \.priceAvailable) }
}
// MARK: - Detail View

/// يعرض بيانات فاتورة واحدة ويحمل عناصرها من الخادم.
struct ReceiptDetailView: View {
    var receipt: Receipt
    @State private var items: [Product] = []
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    private var theme: ReceiptTheme { ReceiptTheme(colorScheme: colorScheme) }
    private var total: Double { Product.knownReceiptTotal(items) }
    private var totalIsComplete: Bool { Product.receiptPricesAreComplete(items) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    summaryCard
                    productsSection
                    bottomTotalCard
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .foregroundStyle(theme.primaryTextColor)
            .background(theme.background)
            .navigationTitle("تفاصيل الفاتورة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.backgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("إغلاق تفاصيل الفاتورة")
                }
            }
            .onAppear {
                if receipt.items.isEmpty {
                    fetchItems()
                } else {
                    items = receipt.items
                }
            }
        }
        .tint(theme.accentColor)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                theme.icon("storefront.fill")
                VStack(alignment: .leading, spacing: 10) {
                    Text(receipt.store.isEmpty ? "متجر غير معروف" : receipt.store)
                        .font(.title3.bold())
                    Label(receipt.city.isEmpty ? "لا توجد مدينة" : receipt.city, systemImage: "location.fill")
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryTextColor)
                    Label(formatDate(receipt.date), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryTextColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Rectangle().fill(theme.borderColor).frame(height: 1)
            totalSummary
        }
        .padding(18)
        .background(theme.cardSurface())
    }

    private var productsSection: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            Text("المنتجات")
                .font(.title3.bold())
                .padding(.bottom, 2)
            ForEach(items.indices, id: \.self) { index in
                productRow(items[index])
            }
        }
    }

    /// ينشئ صف بيانات المنتج وفق تنسيق الشاشة.
    private func productRow(_ product: Product) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                productDescription(product)
                Spacer(minLength: 0)
                productPrice(product)
            }
            VStack(alignment: .leading, spacing: 12) {
                productDescription(product)
                productPrice(product)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cardSurface())
    }

    /// ينشئ اسم المنتج وتصنيفه وفق تنسيق الشاشة.
    private func productDescription(_ product: Product) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(SmartBillFormatting.digits(product.name))
                .font(.body.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if !product.category.isEmpty {
                SmartBillCategoryLabel(category: product.category)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(theme.accentColor.opacity(0.12), in: Capsule())
            }
        }
    }

    /// ينشئ سعر المنتج وفق تنسيق الشاشة.
    private func productPrice(_ product: Product) -> some View {
        Group {
            if product.priceAvailable {
                ReceiptAmount(value: product.price)
            } else {
                Text("غير متوفر")
            }
        }
        .font(.body.weight(.semibold))
    }

    private var totalSummary: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                totalLabel
                Spacer(minLength: 12)
                totalAmount
            }
            VStack(alignment: .leading, spacing: 12) {
                totalLabel
                totalAmount
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var totalLabel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(totalIsComplete ? "الإجمالي" : "مجموع جزئي")
                .font(.headline)
            Text("\(items.count) منتجات")
                .font(.caption)
                .foregroundStyle(theme.secondaryTextColor)
        }
    }

    private var totalAmount: some View {
        Group {
            if items.contains(where: \.priceAvailable) {
                ReceiptAmount(value: total)
            } else {
                Text("غير متوفر")
                    .foregroundStyle(theme.secondaryTextColor)
            }
        }
        .font(.title2.bold())
        .foregroundStyle(theme.accentColor)
    }

    private var bottomTotalCard: some View {
        totalSummary
            .padding(20)
            .background(theme.cardSurface(emphasized: true))
    }

    /// يحول تاريخ الخادم إلى نص عرض وفق التنسيقات المدعومة.
    func formatDate(_ dateString: String) -> String {
        SmartBillFormatting.relativeDate(dateString)
    }

    /// يحمل عناصر الفاتورة باستخدام معرفها على الخادم.
    func fetchItems() {
        guard let url = URL(string: "\(ServerConfig.baseURL)/get_items.php?receipt_id=\(receipt.serverId)") else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
            
            let result = json.map { item -> Product in
                Product.receiptProduct(
                    id: UUID().uuidString.hashValue,
                    name: item["name"] as? String ?? "",
                    rawPrice: item["price"],
                    category: item["category"] as? String ?? ""
                )
            }
            
            DispatchQueue.main.async {
                items = result
            }
        }.resume()
    }
}

private struct ReceiptScanFrameCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let length = min(rect.width, rect.height) * 0.12
        var path = Path()
        path.move(to: CGPoint(x: 0, y: length)); path.addLine(to: .zero); path.addLine(to: CGPoint(x: length, y: 0))
        path.move(to: CGPoint(x: rect.maxX - length, y: 0)); path.addLine(to: CGPoint(x: rect.maxX, y: 0)); path.addLine(to: CGPoint(x: rect.maxX, y: length))
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
        path.move(to: CGPoint(x: length, y: rect.maxY)); path.addLine(to: CGPoint(x: 0, y: rect.maxY)); path.addLine(to: CGPoint(x: 0, y: rect.maxY - length))
        return path
    }
}

private struct ReceiptCameraGuideOverlay: View {
    let accent: Color
    @State private var scanDown = false

    var body: some View {
        GeometryReader { geometry in
            let frameWidth = geometry.size.width * 0.76
            let frameHeight = geometry.size.height * 0.62
            VStack(spacing: 12) {
                Text("ضع الفاتورة داخل الإطار")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 5)
                ZStack {
                    ReceiptScanFrameCorners()
                        .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: frameWidth, height: frameHeight)
                    Rectangle()
                        .fill(accent.opacity(0.9))
                        .frame(width: frameWidth - 24, height: 2)
                        .shadow(color: accent.opacity(0.8), radius: 6)
                        .offset(y: scanDown ? frameHeight * 0.43 : -frameHeight * 0.43)
                        .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: scanDown)
                }
                Text("تأكد من ظهور جميع المنتجات والأسعار بوضوح")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { scanDown = true }
        }
    }
}

#Preview {
    ContentView()
}

// MARK: - Home dashboard

private struct HomeDashboardView: View {
    let onScanReceipt: () -> Void
    let onComparePrices: () -> Void
    let onOpenShoppingList: () -> Void
    let onOpenBestOffers: () -> Void
    let onOpenReceipts: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var receiptModel = HomeReceiptHistoryModel()
    @StateObject private var productsModel = StoreProductsViewModel()
    @State private var selectedReceipt: Receipt?
    @State private var selectedProduct: StoreProduct?

    private var style: SmartBillStyle { SmartBillStyle(scheme: colorScheme) }
    private var discountedProducts: [StoreProduct] {
        productsModel.items
            .filter { $0.priceReduction != nil }
            .sorted { ($0.discountPercentage ?? 0) > ($1.discountPercentage ?? 0) }
    }
    private var spendingTotal: Double? {
        guard receiptModel.hasLoaded,
              receiptModel.error == nil || !receiptModel.receipts.isEmpty else { return nil }
        return receiptModel.receipts.reduce(0) { $0 + $1.total }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                HomeHeaderView()
                VStack(alignment: .leading, spacing: 24) {
                    FinancialSummaryView(
                        spending: spendingTotal,
                        savings: nil,
                        spendingIsPartial: receiptModel.receipts.contains { !$0.totalIsComplete },
                        style: style
                    )
                    QuickActionsView(
                        onScanReceipt: onScanReceipt,
                        onComparePrices: onComparePrices,
                        onShoppingList: onOpenShoppingList,
                        onBestOffers: onOpenBestOffers,
                        style: style
                    )
                    RecentReceiptsView(
                        title: "أحدث الفواتير",
                        receipts: Array(receiptModel.receipts.prefix(3)),
                        isLoading: receiptModel.isLoading,
                        error: receiptModel.error,
                        hasLoaded: receiptModel.hasLoaded,
                        style: style,
                        onRetry: { Task { await receiptModel.load(force: true) } },
                        onSeeAll: onOpenReceipts,
                        onSelect: { selectedReceipt = $0 }
                    )
                    SavingsOpportunitiesView(
                        products: discountedProducts,
                        isLoading: productsModel.loading,
                        error: productsModel.error,
                        style: style,
                        onOpen: onOpenBestOffers
                    )
                    DiscountedProductsView(
                        products: Array(discountedProducts.prefix(8)),
                        isLoading: productsModel.loading,
                        error: productsModel.error,
                        style: style,
                        onSeeAll: onOpenBestOffers,
                        onRetry: { Task { await productsModel.load(search: "", store: "", reset: true) } },
                        onSelect: { selectedProduct = $0 }
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 30)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .background(style.background)
        .refreshable {
            async let receiptRefresh: Void = receiptModel.load(force: true)
            async let productRefresh: Void = productsModel.load(search: "", store: "", reset: true)
            _ = await (receiptRefresh, productRefresh)
        }
        .task { await receiptModel.load() }
        .task { await productsModel.load(search: "", store: "") }
        .sheet(item: $selectedReceipt) { receipt in
            ReceiptDetailView(receipt: receipt)
        }
        .sheet(item: $selectedProduct) { product in
            StoreProductDetails(item: product)
        }
    }
}

private struct HomeHeaderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image("login_logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .padding(6)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    Text("SmartBill")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .environment(\.layoutDirection, .leftToRight)
                }
                Spacer(minLength: 0)
                Image(systemName: "bell.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.12), in: Circle())
                    .accessibilityLabel("الإشعارات")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("مرحباً بعودتك 👋")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Text("تتبع مشترياتك، قارن الأسعار، ووفر أكثر")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [Color(red: 0.035, green: 0.18, blue: 0.12), Color(red: 0.08, green: 0.34, blue: 0.23)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(.white.opacity(0.045))
                    .frame(width: 190, height: 190)
                    .blur(radius: 1)
                    .offset(x: 64, y: -80)
            }
            .ignoresSafeArea(edges: .top)
        }
    }
}

private struct FinancialSummaryView: View {
    let spending: Double?
    let savings: Double?
    let spendingIsPartial: Bool
    let style: SmartBillStyle

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            summaryCard(
                title: "إجمالي التوفير",
                symbol: "sparkles",
                value: savings.map { SmartBillFormatting.money($0) } ?? "غير متاح",
                detail: savings == nil ? "لا تتوفر بيانات التوفير الفعلي" : nil,
                highlighted: true
            )
            summaryCard(
                title: "إجمالي الإنفاق",
                symbol: "creditcard.fill",
                value: spending.map(SmartBillFormatting.money) ?? "—",
                detail: spendingIsPartial ? "مجموع جزئي من الفواتير" : "من الفواتير المحفوظة",
                highlighted: false
            )
        }
    }

    private func summaryCard(
        title: String,
        symbol: String,
        value: String,
        detail: String?,
        highlighted: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(style.accent)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(style.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(style.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .environment(\.layoutDirection, .leftToRight)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(style.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(highlighted ? Color(red: 0.91, green: 0.97, blue: 0.93) : style.card)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(highlighted ? style.accent.opacity(0.10) : style.border, lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(0.035), radius: 12, y: 5)
    }
}

private struct QuickActionsView: View {
    let onScanReceipt: () -> Void
    let onComparePrices: () -> Void
    let onShoppingList: () -> Void
    let onBestOffers: () -> Void
    let style: SmartBillStyle

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("الخدمات السريعة")
                .font(.headline)
                .foregroundStyle(style.primary)
            LazyVGrid(columns: columns, spacing: 10) {
                action("مسح فاتورة", symbol: "doc.viewfinder", action: onScanReceipt)
                action("مقارنة الأسعار", symbol: "arrow.left.arrow.right", action: onComparePrices)
                action("قائمة مشترياتي", symbol: "cart", action: onShoppingList)
                action("أفضل العروض", symbol: "tag", action: onBestOffers)
            }
        }
    }

    private func action(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(style.accent)
                    .frame(width: 48, height: 48)
                    .background(style.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(style.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .top)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(style.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(style.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(title))
    }
}

private struct RecentReceiptsView: View {
    let title: String
    let receipts: [Receipt]
    let isLoading: Bool
    let error: String?
    let hasLoaded: Bool
    let style: SmartBillStyle
    let onRetry: () -> Void
    let onSeeAll: () -> Void
    let onSelect: (Receipt) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeading(title: title, actionTitle: receipts.isEmpty ? nil : "عرض الكل", style: style, action: onSeeAll)
            if isLoading && receipts.isEmpty {
                HomeStateCard(style: style) {
                    ProgressView().tint(style.accent)
                    Text("جاري تحميل الفواتير")
                        .font(.subheadline)
                        .foregroundStyle(style.secondary)
                }
            } else if let error, receipts.isEmpty {
                HomeStateCard(style: style) {
                    Image(systemName: "wifi.exclamationmark").foregroundStyle(style.secondary)
                    Text(error).font(.subheadline).foregroundStyle(style.secondary).multilineTextAlignment(.center)
                    Button("إعادة المحاولة", action: onRetry).font(.subheadline.weight(.semibold))
                }
            } else if hasLoaded && receipts.isEmpty {
                HomeStateCard(style: style) {
                    Image(systemName: "doc.text").foregroundStyle(style.accent)
                    Text("لا توجد فواتير محفوظة بعد")
                        .font(.subheadline).foregroundStyle(style.secondary)
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(receipts) { receipt in
                        Button { onSelect(receipt) } label: { receiptRow(receipt) }
                            .buttonStyle(.plain)
                            .accessibilityHint(Text("فتح تفاصيل الفاتورة"))
                    }
                }
            }
        }
    }

    private func receiptRow(_ receipt: Receipt) -> some View {
        HStack(spacing: 12) {
            StoreMark(name: receipt.store, style: style)
            VStack(alignment: .leading, spacing: 5) {
                Text(receipt.store.isEmpty ? "متجر غير معروف" : receipt.store)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(style.primary)
                    .lineLimit(1)
                Text(SmartBillFormatting.relativeDate(receipt.date))
                    .font(.caption)
                    .foregroundStyle(style.secondary)
                Text("\(receipt.items.count) منتجات")
                    .font(.caption2)
                    .foregroundStyle(style.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 5) {
                Text(receipt.hasKnownTotal ? SmartBillFormatting.money(receipt.total) : "غير متاح")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(style.accent)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(receipt.totalIsComplete ? "الإجمالي" : "مجموع جزئي")
                    .font(.caption2)
                    .foregroundStyle(style.secondary)
            }
            Image(systemName: "chevron.left")
                .font(.caption.weight(.semibold))
                .foregroundStyle(style.secondary.opacity(0.75))
        }
        .padding(14)
        .background(style.surface)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct SavingsOpportunitiesView: View {
    let products: [StoreProduct]
    let isLoading: Bool
    let error: String?
    let style: SmartBillStyle
    let onOpen: () -> Void

    private var largestReduction: Double? {
        products.compactMap(\.priceReduction).max()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeading(title: "فرص توفير لك", style: style)
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "basket.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color(red: 0.08, green: 0.39, blue: 0.27))
                    .frame(width: 56, height: 56)
                    .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 7) {
                    Text(cardTitle)
                        .font(.headline)
                        .foregroundStyle(Color(red: 0.06, green: 0.24, blue: 0.16))
                    Text(cardSubtitle)
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.17, green: 0.35, blue: 0.26).opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                    if !products.isEmpty {
                        Text("أكبر فرق عن السعر السابق: \(SmartBillFormatting.money(largestReduction ?? 0))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color(red: 0.07, green: 0.37, blue: 0.25))
                            .monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            Button(action: onOpen) {
                HStack(spacing: 8) {
                    Text("عرض المنتجات")
                    Image(systemName: "arrow.left")
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Color(red: 0.09, green: 0.39, blue: 0.27), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.85, green: 0.95, blue: 0.89))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color(red: 0.18, green: 0.48, blue: 0.34).opacity(0.12), lineWidth: 1)
                }
        }
    }

    private var cardTitle: String {
        if isLoading && products.isEmpty { return "نبحث عن تخفيضات في المتاجر" }
        if error != nil && products.isEmpty { return "تعذر تحميل فرص التوفير" }
        return products.isEmpty ? "لا توجد تخفيضات معروضة حالياً" : "عُثر على \(products.count) عرض مخفض"
    }

    private var cardSubtitle: String {
        if isLoading && products.isEmpty { return "يتم جلب الأسعار الحالية من كتالوج المتاجر" }
        if error != nil && products.isEmpty { return "حاول مرة أخرى أو افتح كتالوج المنتجات." }
        return "مقارنة السعر الحالي بالسعر السابق في المنتجات المحملة من كتالوج المتاجر."
    }
}

private struct DiscountedProductsView: View {
    let products: [StoreProduct]
    let isLoading: Bool
    let error: String?
    let style: SmartBillStyle
    let onSeeAll: () -> Void
    let onRetry: () -> Void
    let onSelect: (StoreProduct) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeading(title: "منتجات انخفض سعرها", actionTitle: products.isEmpty ? nil : "عرض الكل", style: style, action: onSeeAll)
            if isLoading && products.isEmpty {
                HomeStateCard(style: style) {
                    ProgressView().tint(style.accent)
                    Text("جاري تحميل المنتجات")
                        .font(.subheadline)
                        .foregroundStyle(style.secondary)
                }
            } else if let error, products.isEmpty {
                HomeStateCard(style: style) {
                    Text(error).font(.subheadline).foregroundStyle(style.secondary).multilineTextAlignment(.center)
                    Button("إعادة المحاولة", action: onRetry).font(.subheadline.weight(.semibold))
                }
            } else if products.isEmpty {
                HomeStateCard(style: style) {
                    Image(systemName: "tag").foregroundStyle(style.accent)
                    Text("لا توجد منتجات مخفضة ضمن الأسعار المحملة")
                        .font(.subheadline).foregroundStyle(style.secondary).multilineTextAlignment(.center)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(products) { product in
                            Button { onSelect(product) } label: {
                                DiscountedProductCard(product: product, style: style)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .environment(\.layoutDirection, .rightToLeft)
            }
        }
    }
}

private struct DiscountedProductCard: View {
    let product: StoreProduct
    let style: SmartBillStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .topTrailing) {
                CachedProductImage(source: product.image_url)
                    .frame(maxWidth: .infinity)
                    .frame(height: 112)
                    .padding(8)
                Text("−\(product.discountPercentage ?? 0)%")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color(red: 0.06, green: 0.37, blue: 0.25))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(red: 0.86, green: 0.96, blue: 0.90), in: Capsule())
                    .padding(8)
            }
            .frame(height: 128)
            .background(style.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(product.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(style.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
            Text(product.amount.map(SmartBillFormatting.money) ?? "السعر غير متاح")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(style.accent)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            HStack(spacing: 6) {
                if let previous = product.previousAmount {
                    Text(SmartBillFormatting.money(previous))
                        .font(.caption2)
                        .foregroundStyle(style.secondary)
                        .strikethrough()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            Text(product.store_name)
                .font(.caption2)
                .foregroundStyle(style.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(width: 172, alignment: .leading)
        .background(style.surface)
    }
}

private struct HomeSectionHeading: View {
    let title: String
    var actionTitle: String? = nil
    let style: SmartBillStyle
    var action: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(style.primary)
            Spacer(minLength: 0)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(style.accent)
                    .buttonStyle(.plain)
            }
        }
    }
}

private struct HomeStateCard<Content: View>: View {
    let style: SmartBillStyle
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 10) { content() }
            .font(.subheadline)
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(style.surface)
    }
}

private struct StoreMark: View {
    let name: String
    let style: SmartBillStyle

    private var mark: String? {
        let normalized = name.lowercased()
        if normalized.contains("panda") || name.contains("باندا") { return "P" }
        if normalized.contains("tamimi") || name.contains("تميمي") || name.contains("التميمي") { return "T" }
        if normalized.contains("danube") || name.contains("دانوب") { return "D" }
        return nil
    }

    var body: some View {
        Group {
            if let mark {
                Text(mark)
                    .font(.system(.title3, design: .rounded, weight: .heavy))
                    .foregroundStyle(style.accent)
            } else {
                Image(systemName: "storefront.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(style.accent)
            }
        }
        .frame(width: 48, height: 48)
        .background(style.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct ShoppingListPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    private var style: SmartBillStyle { SmartBillStyle(scheme: colorScheme) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "cart.badge.plus")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(style.accent)
                    .frame(width: 88, height: 88)
                    .background(style.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                Text("قائمة مشترياتك")
                    .font(.title3.bold())
                    .foregroundStyle(style.primary)
                Text("قائمة التسوق غير متاحة حالياً.")
                    .font(.subheadline)
                    .foregroundStyle(style.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(style.background)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("إغلاق") { dismiss() }
                }
            }
        }
        .tint(style.accent)
    }
}

private struct BestOffersView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var model = StoreProductsViewModel()
    @State private var selectedProduct: StoreProduct?

    private var style: SmartBillStyle { SmartBillStyle(scheme: colorScheme) }
    private var offers: [StoreProduct] {
        model.items
            .filter { $0.priceReduction != nil }
            .sorted { ($0.discountPercentage ?? 0) > ($1.discountPercentage ?? 0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("عروض الأسعار الأقل من السعر السابق المسجل في كتالوج المتاجر.")
                        .font(.subheadline)
                        .foregroundStyle(style.secondary)
                    if model.loading && model.items.isEmpty {
                        HomeStateCard(style: style) {
                            ProgressView().tint(style.accent)
                            Text("جاري تحميل العروض").foregroundStyle(style.secondary)
                        }
                    } else if let error = model.error, model.items.isEmpty {
                        HomeStateCard(style: style) {
                            Text(LocalizedStringKey(error)).foregroundStyle(style.secondary).multilineTextAlignment(.center)
                            Button("إعادة المحاولة") { Task { await model.load(search: "", store: "", reset: true) } }
                        }
                    } else if offers.isEmpty && !model.hasMore {
                        HomeStateCard(style: style) {
                            Image(systemName: "tag").foregroundStyle(style.accent)
                            Text("لا توجد منتجات مخفضة ضمن الأسعار المحملة")
                                .foregroundStyle(style.secondary).multilineTextAlignment(.center)
                        }
                    } else if offers.isEmpty {
                        HomeStateCard(style: style) {
                            Image(systemName: "magnifyingglass").foregroundStyle(style.accent)
                            Text("لم تظهر عروض مخفضة في المنتجات المحملة بعد")
                                .foregroundStyle(style.secondary).multilineTextAlignment(.center)
                        }
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(offers) { item in
                                Button { selectedProduct = item } label: {
                                    BestOfferRow(product: item, style: style)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if let error = model.error, !model.items.isEmpty {
                        Text(LocalizedStringKey(error)).font(.caption).foregroundStyle(style.secondary)
                    }
                    if model.hasMore && !model.loading {
                        Button("تحميل المزيد من المنتجات") {
                            Task { await model.load(search: "", store: "", reset: false) }
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    if model.loading && !model.items.isEmpty {
                        ProgressView().tint(style.accent).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                }
                .padding(20)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(style.background)
            .refreshable { await model.load(search: "", store: "", reset: true) }
            .navigationTitle("أفضل العروض")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("إغلاق") { dismiss() }
                }
            }
            .task { await model.load(search: "", store: "") }
            .sheet(item: $selectedProduct) { item in StoreProductDetails(item: item) }
        }
        .tint(style.accent)
    }
}

private struct BestOfferRow: View {
    let product: StoreProduct
    let style: SmartBillStyle

    var body: some View {
        HStack(spacing: 13) {
            ZStack(alignment: .topTrailing) {
                CachedProductImage(source: product.image_url)
                    .frame(width: 74, height: 74)
                    .padding(6)
                    .background(style.background, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                Text("−\(product.discountPercentage ?? 0)%")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(style.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(style.card, in: Capsule())
                    .offset(x: 3, y: -3)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(product.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(style.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(product.store_name)
                    .font(.caption)
                    .foregroundStyle(style.secondary)
                    .lineLimit(1)
                HStack(spacing: 7) {
                    Text(product.amount.map(SmartBillFormatting.money) ?? "السعر غير متاح")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(style.accent)
                        .monospacedDigit()
                    if let previous = product.previousAmount {
                        Text(SmartBillFormatting.money(previous))
                            .font(.caption2)
                            .foregroundStyle(style.secondary)
                            .strikethrough()
                            .monospacedDigit()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.left")
                .font(.caption.weight(.semibold))
                .foregroundStyle(style.secondary)
        }
        .padding(13)
        .background(style.surface)
    }
}

private extension StoreProduct {
    var previousAmount: Double? {
        guard let old_price,
              let value = Double(old_price.trimmingCharacters(in: .whitespacesAndNewlines)),
              value.isFinite, value > 0,
              let amount, value > amount else { return nil }
        return value
    }

    var priceReduction: Double? {
        guard let previousAmount, let amount else { return nil }
        return previousAmount - amount
    }

    var discountPercentage: Int? {
        guard let previousAmount, let priceReduction else { return nil }
        return Int((priceReduction / previousAmount * 100).rounded())
    }
}

@MainActor
private final class HomeReceiptHistoryModel: ObservableObject {
    @Published private(set) var receipts: [Receipt] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var error: String?

    func load(force: Bool = false) async {
        guard !isLoading, force || !hasLoaded else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

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
                var items = decodeProducts(inline)
                if inline.isEmpty || inline.contains(where: { !($0["category"] is String) }) {
                    guard id > 0 else { throw URLError(.cannotParseResponse) }
                    if let cached = itemCache[id] {
                        items = cached
                    } else {
                        let itemRows = try await fetchRows(endpoint: "get_items.php", query: [
                            URLQueryItem(name: "receipt_id", value: String(id))
                        ])
                        items = decodeProducts(itemRows)
                        itemCache[id] = items
                    }
                }
                let totalIsComplete = Product.receiptPricesAreComplete(items)
                let itemsTotal = Product.knownReceiptTotal(items)
                let serverTotal = numericValue(row["total"])
                let city = (row["city"] as? String ?? row["city_name"] as? String ?? row["location"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                loaded.append(Receipt(
                    serverId: id,
                    store: row["store"] as? String ?? "",
                    total: totalIsComplete ? serverTotal ?? itemsTotal : itemsTotal,
                    totalIsComplete: totalIsComplete,
                    date: row["date"] as? String ?? "",
                    items: items,
                    city: city
                ))
            }
            receipts = loaded
            hasLoaded = true
        } catch is CancellationError {
        } catch {
            self.error = "تعذر تحميل الفواتير. تحقق من اتصال الإنترنت وحاول مرة أخرى."
            hasLoaded = true
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
}
