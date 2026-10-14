import StipendCore
import SwiftUI

struct UsagePanelView: View {
    let meter: Meter
    let display: UsageDisplay
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch display {
            case .signedOut:
                Text("未检测到本机 Cursor 登录")
            case .unavailable:
                Text("用量暂时无法更新")
            case .ready(let snapshot):
                ready(snapshot)
            }
        }
        .padding(14)
        .frame(width: meter == .grokBot ? 220 : 320, alignment: .leading)
    }

    @ViewBuilder
    private func ready(_ snapshot: UsageSnapshot) -> some View {
        switch meter {
        case .cursorModels:
            pool(PoolPanelCopy.make(pool: snapshot.cursorModels, isStale: snapshot.cursorStale))
        case .otherModels:
            pool(PoolPanelCopy.make(pool: snapshot.otherModels, isStale: snapshot.cursorStale))
        case .grokBot:
            grok(GrokPanelCopy.make(usage: snapshot.grokBot, now: now, isStale: snapshot.grokStale))
        }
    }

    private func pool(_ model: PoolPanelModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.percentText).font(.title.monospacedDigit())
                Spacer()
                Text(model.periodTokensText).font(.title2.monospacedDigit())
            }
            HStack {
                Text(model.todayShareText)
                Spacer()
                Text(model.todayTokensText).monospacedDigit()
            }
            .font(.body)
            ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    Text(row.name).lineLimit(1).frame(maxWidth: 110, alignment: .leading)
                    ProgressBar(fraction: row.fraction)
                    Text(row.percentText).frame(width: 44, alignment: .trailing)
                    Text(row.tokensText).frame(width: 56, alignment: .trailing)
                }
                .font(.callout.monospacedDigit())
            }
            if let stale = model.staleText {
                Text(stale).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func grok(_ model: GrokPanelModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.percentText).font(.title.monospacedDigit())
            if let allowance = model.allowanceText {
                Text(allowance).font(.body)
            }
            if let reset = model.resetText {
                Text(reset).font(.body)
            }
            if let stale = model.staleText {
                Text(stale).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ProgressBar: View {
    var fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(Color.accentColor)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 6)
    }
}
