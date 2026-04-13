//
//  ContentView.swift
//  Smart bill
//
//  Created by abdulaziz on 30/03/2026.
//

import SwiftUI
import PhotosUI
import UIKit

struct ContentView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var recognizedText: String = ""
    @State private var isLoading = false
    @State private var showCamera = false
    @State private var extractedItems: [(name: String, price: String)] = []
    @State private var storeName: String = ""
    @State private var searchText: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Smart Bill")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.blue)

            TextField("Search product...", text: $searchText)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal)

            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: 220)
                    .shadow(radius: 4)

                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 200)
                        .cornerRadius(12)
                } else {
                    VStack {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("No Image Selected")
                            .foregroundColor(.gray)
                    }
                }
            }

            PhotosPicker(selection: $selectedItem, matching: .images) {
                Text("اضف من الصور ")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .shadow(radius: 3)
            }
            .onChange(of: selectedItem) { newItem in
                loadImage(from: newItem)
            }

            Button {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    DispatchQueue.main.async {
                        showCamera = true
                    }
                } else {
                    print("Camera not available")
                }
            } label: {
                Text("الكاميرا")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .shadow(radius: 3)
            }

            Button {
                sendToGoogleVision()
            } label: {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    Text("اطبع الفاتورة")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(12)
            .shadow(radius: 3)
            .disabled(selectedImage == nil)

            ScrollView {
                if !storeName.isEmpty {
                    Text(storeName)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(10)
                }
                if extractedItems.isEmpty {
                    Text(recognizedText.isEmpty ? "لا يوجد فاتوره....." : recognizedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        let filteredItems = extractedItems.filter {
                            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
                        }

                        ForEach(filteredItems.indices, id: \.self) { index in
                            let item = filteredItems[index]
                            HStack {
                                Text(item.name)
                                    .font(.body)
                                Spacer()
                                Text(item.price)
                                    .fontWeight(.bold)
                            }
                            .padding()
                            .background(Color.white)
                            .cornerRadius(10)
                            .shadow(radius: 2)
                        }
                    }
                    .padding()
                }
            }

            Spacer()
        }
        .padding()
        .preferredColorScheme(.light)
        .sheet(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera) { image in
                selectedImage = image
                showCamera = false
            }
        }
    }

    func loadImage(from item: PhotosPickerItem?) {
        guard let item = item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                selectedImage = uiImage
            }
        }
    }

    func sendToGoogleVision() {
        guard let image = selectedImage,
              let imageData = image.jpegData(compressionQuality: 1.0) else { return }

        isLoading = true

        let base64 = imageData.base64EncodedString()
        let apiKey = "AIzaSyD0MDplXCRzwOyuX_CqDE5y9v994ToY68Y"
        let url = URL(string: "https://vision.googleapis.com/v1/images:annotate?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "requests": [
                [
                    "image": ["content": base64],
                    "features": [
                        ["type": "DOCUMENT_TEXT_DETECTION"]
                    ],
                    "imageContext": [
                        "languageHints": ["ar"]
                    ]
                ]
            ]
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error:", error)
            }
            if let data = data {
                print(String(data: data, encoding: .utf8) ?? "")
            }

            DispatchQueue.main.async {
                isLoading = false
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responses = json["responses"] as? [[String: Any]],
                  let textAnnotations = responses.first?["textAnnotations"] as? [[String: Any]],
                  let first = textAnnotations.first,
                  let text = first["description"] as? String else { return }

            DispatchQueue.main.async {
                recognizedText = text
                extractedItems = extractItems(from: text)
                storeName = extractStoreName(from: text)
            }
        }.resume()
    }

    func extractItems(from text: String) -> [(name: String, price: String)] {
        let lines = text.components(separatedBy: "\n")
        var items: [(String, String)] = []

        let priceRegex = try! NSRegularExpression(pattern: "(\\d+\\.\\d{2}|\\d+\\,\\d{2}|\\d+)")

        for line in lines {
            let lower = line.lowercased()
            let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanLine.isEmpty { continue }

            if lower.contains("total") ||
               lower.contains("vat") ||
               lower.contains("tax") ||
               lower.contains("discount") ||
               lower.contains("subtotal") {
                continue
            }
            if lower.contains("الصنف") ||
               lower.contains("فاتورة") ||
               lower.contains("السعر") ||
               lower.contains("عدد") ||
               lower.contains("items") ||
               lower.contains("qty") {
                continue
            }

            let parts = cleanLine.components(separatedBy: " ").filter { !$0.isEmpty }

            var detectedPrice: String?
            var nameParts: [String] = []

            for part in parts {
                let normalized = part.replacingOccurrences(of: ",", with: ".")

                // تجاهل كلمات غير مفيدة
                if part.contains("SAR") || part.contains("ر.س") {
                    continue
                }

                if normalized.range(of: #"^\d+(\.\d{1,2})?$"#, options: .regularExpression) != nil {
                    detectedPrice = normalized
                } else {
                    // اجمع كل الكلمات حتى لو فيها أرقام بسيطة (مثل 1L أو 500ml)
                    if part.rangeOfCharacter(from: .letters) != nil {
                        nameParts.append(part)
                    }
                }
            }

            if let price = detectedPrice {
                let name = nameParts
                    .joined(separator: " ")
                    .replacingOccurrences(of: "  ", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                let hasOnlyNumbers = name.trimmingCharacters(in: .whitespaces)
                    .range(of: #"^\d+$"#, options: .regularExpression) != nil

                if name.count > 2 && !hasOnlyNumbers {
                    items.append((name, price))
                }
            }
        }

        return items
    }
    
    func extractStoreName(from text: String) -> String {
        let lines = text.components(separatedBy: "\n")

        for line in lines.prefix(5) {
            let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if clean.isEmpty { continue }

            if clean.rangeOfCharacter(from: .letters) != nil &&
               !clean.lowercased().contains("tax") &&
               !clean.lowercased().contains("vat") &&
               !clean.lowercased().contains("total") {

                return clean
            }
        }

        return "Unknown Store"
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType
    var onImagePicked: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator

        picker.cameraCaptureMode = .photo
        picker.videoQuality = .typeHigh
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

#Preview {
    ContentView()
}
