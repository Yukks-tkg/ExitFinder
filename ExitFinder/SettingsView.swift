import SwiftUI
import StoreKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @State private var tipStore = TipStore.shared
    @State private var showThanks = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                List {
                    Section {
                        if tipStore.products.isEmpty {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else {
                            ForEach(tipStore.products, id: \.id) { product in
                                Button {
                                    Task {
                                        await tipStore.purchase(product)
                                    }
                                } label: {
                                    HStack {
                                        Text(product.displayName)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text(product.displayPrice)
                                            .foregroundStyle(.primary)
                                    }
                                }
                                .disabled(tipStore.isPurchasing)
                            }
                        }
                    } header: {
                        Text(L10n.text("support.tip_title"))
                    } footer: {
                        Text(L10n.text("support.tip_body"))
                            .font(.caption)
                    }

                    Section(L10n.text("support.title")) {
                        Button {
                            requestReview()
                        } label: {
                            Label(L10n.text("support.review"), systemImage: "star")
                        }
                        Button {
                            var contact = URLComponents()
                            contact.scheme = "mailto"
                            contact.path = "y.takagi.jp@outlook.jp"
                            contact.queryItems = [URLQueryItem(name: "subject", value: L10n.text("support.email_subject"))]
                            if let url = contact.url {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label(L10n.text("support.contact"), systemImage: "envelope")
                        }
                    }

                    Section(L10n.text("legal.title")) {
                        Button {
                            if let url = URL(string: "https://immense-engineer-7f8.notion.site/31f0dee3bb098035867afb1858d4f245?pvs=74") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label(L10n.text("legal.terms"), systemImage: "doc.text")
                        }
                        Button {
                            if let url = URL(string: "https://immense-engineer-7f8.notion.site/31f0dee3bb0980709680dcd27ebcb89f") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label(L10n.text("legal.privacy"), systemImage: "hand.raised")
                        }
                    }
                }

                // フッター：バージョン情報
                VStack(spacing: 4) {
                    Text(L10n.format("app.version", [Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"]))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("© 2026 Yuki Takagi")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 32)
            }
            .navigationTitle(L10n.text("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .alert(L10n.text("support.thanks_title"), isPresented: $showThanks) {
                Button(L10n.text("action.close"), role: .cancel) {}
            } message: {
                Text(L10n.text("support.thanks_body"))
            }
            .onChange(of: tipStore.purchaseSuccess) { _, success in
                if success {
                    showThanks = true
                    tipStore.purchaseSuccess = false
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.text("action.close")) { dismiss() }
                }
            }
        }
    }
}

