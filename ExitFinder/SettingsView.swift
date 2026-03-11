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
                        NavigationLink {
                            TermsOfServiceView()
                        } label: {
                            Label("利用規約", systemImage: "doc.text")
                        }
                        NavigationLink {
                            PrivacyPolicyView()
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

// MARK: - 利用規約

struct TermsOfServiceView: View {
    var body: some View {
        ScrollView {
            Text(termsText)
                .padding()
        }
        .navigationTitle("利用規約")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var termsText: String {
        """
        駅出口マップ 利用規約

        最終更新日: 2025年1月

        第1条（サービスの内容）
        駅出口マップ（以下「本アプリ」）は、ユーザーの現在地または指定した場所の周辺にある駅出口情報を提供するアプリケーションです。

        第2条（データの出典）
        本アプリが提供する駅出口情報は OpenStreetMap（OSM）のデータに基づいています。データの正確性・完全性を保証するものではありません。

        第3条（免責事項）
        1. 本アプリが提供する情報（出口の位置、距離、ルートなど）は参考情報であり、正確性を保証するものではありません。
        2. 本アプリの利用により生じた損害について、開発者は一切の責任を負いません。
        3. ルート案内は Apple MapKit の経路探索に基づいており、実際の道路状況と異なる場合があります。

        第4条（禁止事項）
        本アプリを商業目的で無断転載・複製・再配布することを禁止します。

        第5条（変更）
        本規約は予告なく変更される場合があります。変更後も本アプリを継続利用した場合、変更後の規約に同意したものとみなします。
        """
    }
}

// MARK: - プライバシーポリシー

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            Text(privacyText)
                .padding()
        }
        .navigationTitle("プライバシーポリシー")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var privacyText: String {
        """
        駅出口マップ プライバシーポリシー

        最終更新日: 2025年1月

        1. 取得する情報
        本アプリは以下の情報を取得します:
        • 位置情報（現在地の取得および駅出口検索のため）
        • デバイスの方角情報（方向コーンの表示のため）

        2. 情報の利用目的
        取得した位置情報は、以下の目的にのみ使用します:
        • 周辺の駅出口情報の検索
        • 現在地から出口までのルート表示
        • マップ上での現在地表示

        3. 外部送信
        位置情報（緯度・経度）は Overpass API（OpenStreetMap）に送信され、周辺の駅出口データを取得するために使用されます。それ以外の第三者サービスへのデータ送信は行いません。

        4. データの保存
        本アプリはユーザーの位置情報をサーバーに保存しません。すべての処理はデバイス上またはリアルタイムのAPI通信で行われます。

        5. 第三者への提供
        ユーザーの個人情報を第三者に提供・販売することはありません。

        6. お問い合わせ
        プライバシーに関するお問い合わせは、アプリの配布元までご連絡ください。
        """
    }
}
