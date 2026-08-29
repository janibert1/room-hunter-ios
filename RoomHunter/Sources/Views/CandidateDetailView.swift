import SwiftUI

/// Shows the listing's photos + original raw text (per Jan's spec: the draft
/// screen isn't just Gemini's summary, it's the real thing) with Yes/No.
/// "No" is a clean single tap with no confirmation -- low stakes, nothing is
/// sent. "Yes" leads into DraftReviewView, where the real friction belongs
/// (that's the screen with an actual send button).
struct CandidateDetailView: View {
    let candidate: Candidate
    let api: APIClient
    let onDecided: () -> Void

    @State private var isSubmittingNo = false
    @State private var showDraft = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !candidate.photos.isEmpty {
                        TabView {
                            ForEach(candidate.photos, id: \.self) { url in
                                AsyncImage(url: URL(string: url)) { phase in
                                    if let image = phase.image {
                                        image.resizable().aspectRatio(contentMode: .fit)
                                    } else {
                                        Rectangle().fill(.quaternary)
                                    }
                                }
                            }
                        }
                        .tabViewStyle(.page)
                        .frame(height: 240)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(candidate.title).font(.title2.bold())
                        HStack {
                            if let price = candidate.formattedPrice { Text(price).foregroundStyle(.secondary) }
                            if let location = candidate.location { Text("· \(location)").foregroundStyle(.secondary) }
                        }
                        Text(candidate.source.uppercased()).font(.caption).foregroundStyle(.tertiary)
                    }

                    if let breakdown = candidate.scoreBreakdown, !breakdown.isEmpty {
                        ScoreBreakdownView(score: candidate.score, breakdown: breakdown)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Original listing").font(.headline)
                        Text(candidate.rawText).font(.body).foregroundStyle(.primary)
                    }

                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red).font(.callout)
                    }
                }
                .padding()
            }
            .navigationTitle("Listing")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button {
                        Task { await decide(false) }
                    } label: {
                        Label("No", systemImage: "xmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSubmittingNo)

                    Button {
                        showDraft = true
                    } label: {
                        Label("Yes", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(.bar)
            }
        }
        .sheet(isPresented: $showDraft) {
            DraftReviewView(candidateId: candidate.id, api: api, onSentOrCancelled: {
                showDraft = false
                onDecided()
            })
        }
    }

    func decide(_ yes: Bool) async {
        isSubmittingNo = true
        do {
            try await api.sendDecision(candidateId: candidate.id, decision: yes)
            onDecided()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmittingNo = false
    }
}

struct ScoreBreakdownView: View {
    let score: Int
    let breakdown: [String: Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Score").font(.headline)
                Spacer()
                ScoreBadge(score: score)
            }
            ForEach(breakdown.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack {
                    Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.subheadline)
                    Spacer()
                    Text("\(value)").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }
}
