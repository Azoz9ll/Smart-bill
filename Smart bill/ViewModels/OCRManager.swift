//
//  OCRManager.swift
//  Smart Bill
//
//  Purpose:
//  أداة لاستخراج النص من الصور باستخدام Apple Vision محليًا.
//
//  Responsibilities:
//  - التعرف على النص العربي والإنجليزي
//  - إعادة الأسطر كنص عبر completion دون استخراج منتجات منظمة
//

//
//  OCRManager.swift
//  Smart bill
//
//  Created by abdulaziz on 17/04/2026.
//

import Vision
import UIKit

/// أداة لاستخراج النص من الصور باستخدام Apple Vision محليًا.
class OCRManager {

    /// يشغل Vision للتعرف على النص العربي والإنجليزي ثم يعيد الأسطر.
    func recognizeText(from image: UIImage, completion: @escaping (String) -> Void) {

        guard let cgImage = image.cgImage else { return }

        let request = VNRecognizeTextRequest { request, error in

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion("")
                return
            }

            let text = observations.compactMap {
                $0.topCandidates(1).first?.string
            }.joined(separator: "\n")

            print("📄 OCR TEXT:\n", text)

            completion(text)
        }

        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ar", "en"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }
}
