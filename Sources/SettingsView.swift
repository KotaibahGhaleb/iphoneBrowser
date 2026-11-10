import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: ProxyController

    @Binding var modeRaw: String
    @Binding var typeRaw: String
    @Binding var host: String
    @Binding var port: Int
    @Binding var username: String
    @Binding var password: String
    @Binding var home: String
    @Binding var adblock: Bool

    @Environment(\.dismiss) private var dismiss

    private var mode: ProxyMode {
        ProxyMode(rawValue: modeRaw) ?? .auto
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("الإعلانات") {
                    Toggle("حظر الإعلانات والنوافذ المنبثقة", isOn: $adblock)
                }

                Section("الاتصال") {
                    Picker("الوضع", selection: $modeRaw) {
                        ForEach(ProxyMode.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                }

                if mode == .auto {
                    Section("البروكسي التلقائي") {
                        Text(controller.status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("إعادة البحث عن بروكسي") {
                            controller.retry()
                        }
                        Text("التطبيق يجرب بروكسيات مجانية عامة وحدة وحدة. جودتها تتفاوت — إذا بطيء جرّب «إعادة البحث» أو استخدم رابط مرآة (شوف README).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if mode == .manual {
                    Section("بيانات البروكسي") {
                        Picker("النوع", selection: $typeRaw) {
                            ForEach(ManualProxyType.allCases) { type in
                                Text(type.rawValue).tag(type.rawValue)
                            }
                        }
                        TextField("العنوان (Host)", text: $host)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("المنفذ (Port)", value: $port, format: .number)
                            .keyboardType(.numberPad)
                        TextField("اسم المستخدم (اختياري)", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("كلمة المرور (اختياري)", text: $password)
                    }
                }

                if mode == .off {
                    Section {
                        Text("اتصال مباشر بدون بروكسي. استخدمه إذا حطيت رابط مرآة كصفحة رئيسية، أو إذا الموقع غير محظور.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("الصفحة الرئيسية") {
                    TextField("رابط الصفحة", text: $home)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("لو عندك رابط مرآة (مثل Cloudflare Worker) حطه هنا وخلي الوضع «بدون بروكسي».")
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
