import SwiftUI
import StoreKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                List {
                    Section("サポート") {
                        Button {
                            requestReview()
                        } label: {
                            Label("レビューを書く", systemImage: "star")
                        }
                        Button {
                            if let url = URL(string: "mailto:y.takagi.jp@outlook.jp?subject=駅出口マップへのお問い合わせ") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("お問い合わせ", systemImage: "envelope")
                        }
                    }

                    Section("法的情報") {
                        Button {
                            if let url = URL(string: "https://immense-engineer-7f8.notion.site/31f0dee3bb098035867afb1858d4f245?pvs=74") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("利用規約", systemImage: "doc.text")
                        }
                        Button {
                            if let url = URL(string: "https://immense-engineer-7f8.notion.site/31f0dee3bb0980709680dcd27ebcb89f") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("プライバシーポリシー", systemImage: "hand.raised")
                        }
                    }
                }

                // フッター：バージョン情報
                VStack(spacing: 4) {
                    Text("駅出口マップ \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("© 2026 Yuki Takagi")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 32)
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

