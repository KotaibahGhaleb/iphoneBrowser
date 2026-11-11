import SwiftUI
import WebKit

struct SettingsView: View {
    @Binding var home: String
    @Binding var adblock: Bool
    @Binding var hoverPreview: Bool
    @Binding var incognito: Bool
    @Binding var appLock: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("الخصوصية") {
                    Toggle("قفل بالبصمة / الرمز عند الفتح", isOn: $appLock)
                    Toggle("وضع التخفي (بدون حفظ كوكيز وجلسات)", isOn: $incognito)
                    Button("مسح بيانات التصفح الآن", role: .destructive) {
                        WKWebsiteDataStore.default().removeData(
                            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                            modifiedSince: .distantPast
                        ) {}
                    }
                    Text("المحتوى يُحجب تلقائياً بلون أسود في مبدّل التطبيقات.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("الإعلانات") {
                    Toggle("حظر الإعلانات والنوافذ المنبثقة", isOn: $adblock)
                }

                Section("التصفح") {
                    Toggle("لمسة مطوّلة = معاينة الفيديو (Hover)", isOn: $hoverPreview)
                    Text("اضغط مطوّلاً على صورة المقطع لتشغيل المعاينة، وارفع إصبعك لإيقافها.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("الصفحة الرئيسية") {
                    TextField("رابط الصفحة", text: $home)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("اكتب «start» لصفحة المواقع المدمجة، أو أي رابط كامل.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("الإعدادات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("تم") { dismiss() }
                }
            }
        }
    }
}
