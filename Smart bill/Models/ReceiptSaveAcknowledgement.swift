//
//  ReceiptSaveAcknowledgement.swift
//  Smart Bill
//
//  Purpose:
//  التحقق من إقرار حفظ الفاتورة دون اعتبار كل استجابة HTTP ناجحة حفظًا مؤكدًا.
//
//  Responsibilities:
//  - قبول حقول النجاح الصريحة أو رد success النصي.
//  - رفض رسائل الخطأ والمحتوى غير المتوقع دون عرضه للمستخدم.
//
import Foundation

nonisolated enum ReceiptSaveAcknowledgement {
    static func succeeded(_ data: Data) -> Bool {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let success = object["success"] as? Bool { return success }
            if let status = object["status"] as? String { return status.lowercased() == "success" }
            return false
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "success"
    }
}
