import SwiftUI

struct TabSwitcherView: View {
    @ObservedObject var model: BrowserModel
    let config: BrowserConfig
    let home: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.tabs) { tab in
                    Button {
                        model.activate(tab)
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tab.title.isEmpty ? (tab.url?.host ?? "صفحة جديدة") : tab.title)
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                Text(tab.url?.absoluteString ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if model.activeID == tab.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                            Button(role: .destructive) {
                                model.close(tab, config: config, home: home)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            model.close(tab, config: config, home: home)
                        } label: {
                            Label("إغلاق", systemImage: "xmark")
                        }
                    }
                }
            }
            .navigationTitle("التبويبات")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        model.newTab(config: config, home: home)
                        dismiss()
                    } label: {
                        Label("تبويب جديد", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("تم") { dismiss() }
                }
            }
        }
    }
}
