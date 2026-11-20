//
//  CameraView.swift
//  Smart Bill
//
//  Purpose:
//  التقاط صورة الفاتورة الأصلية مع معالجة الإذن والإلغاء بأمان.
//
//  Responsibilities:
//  - فحص الإتاحة قبل إنشاء UIImagePickerController.
//  - إغلاق العرض عبر SwiftUI مرة واحدة عند الالتقاط أو الإلغاء.
//  - عرض خطأ عربي وخيار إعدادات صريح عند رفض الإذن.
//
import SwiftUI
import UIKit
import AVFoundation

struct CameraView: View {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var authorized = false
    @State private var checking = true
    @State private var denied = false
    @State private var captureFailed = false
    private var style: SmartBillStyle { SmartBillStyle(scheme: scheme) }

    var body: some View {
        Group {
            if authorized && !captureFailed {
                ImagePicker(sourceType: .camera) { captured in
                    image = captured
                    dismiss()
                } onCancel: {
                    dismiss()
                } onFailure: {
                    captureFailed = true
                }
                .ignoresSafeArea()
            } else {
                VStack(spacing: 18) {
                    if checking { ProgressView("جاري تجهيز الكاميرا...") }
                    else {
                        Label("تعذر الوصول إلى الكاميرا", systemImage: "camera")
                            .font(.headline)
                        Text(denied ? "اسمح بالوصول إلى الكاميرا من الإعدادات لتصوير الفواتير." : "الكاميرا غير متاحة الآن. يمكنك اختيار صورة من المكتبة.")
                        if denied {
                            Button("فتح الإعدادات") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }.buttonStyle(.borderedProminent)
                        }
                    }
                    Button("إغلاق") { dismiss() }.frame(minHeight: 44)
                }
                .multilineTextAlignment(.center).padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(style.background).foregroundStyle(style.primary).tint(style.accent)
            }
        }
        .task { await prepareCamera() }
    }

    /// لا تطلب الإذن إذا كانت الكاميرا أو رسالة الاستخدام غير متاحة.
    private func prepareCamera() async {
        guard checking else { return }
        defer { checking = false }
        guard UIImagePickerController.isSourceTypeAvailable(.camera),
              let usage = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String,
              !usage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: authorized = true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard !Task.isCancelled else { return }
            authorized = granted; denied = !granted
        case .denied: denied = true
        case .restricted: break
        @unknown default: break
        }
    }
}

/// يحتفظ بالصورة الأصلية دون تحرير أو ضغط إضافي ويمنع تكرار callbacks.
struct ImagePicker: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType
    var onImagePicked: (UIImage) -> Void
    var onCancel: () -> Void
    var onFailure: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        guard UIImagePickerController.isSourceTypeAvailable(sourceType) else {
            DispatchQueue.main.async { onFailure() }
            return picker
        }
        picker.sourceType = sourceType
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker
        private var finished = false
        init(_ parent: ImagePicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard !finished else { return }
            finished = true
            guard let image = info[.originalImage] as? UIImage else { parent.onFailure(); return }
            parent.onImagePicked(image)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            guard !finished else { return }
            finished = true
            parent.onCancel()
        }
    }
}
