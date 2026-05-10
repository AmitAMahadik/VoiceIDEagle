import SwiftUI

struct ScoreBarView: View {
    let name: String
    let score: Float
    let isMatched: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(isMatched ? .semibold : .regular)
                Spacer()
                Text("\(Int((score * 100).rounded()))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(isMatched ? Color.accentColor : .secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.tertiarySystemFill))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isMatched ? Color.accentColor : Color.secondary)
                        .frame(width: proxy.size.width * CGFloat(max(0, min(1, score))))
                        .animation(.easeOut(duration: 0.2), value: score)
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(name) confidence \(Int((score * 100).rounded())) percent"))
    }
}
