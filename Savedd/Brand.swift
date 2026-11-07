import SwiftUI

/// Exact RGB equivalents of the website's Vespers dark-theme tokens.
enum SaveddBrand {
    static let background = Color(red: 0.071, green: 0.058, blue: 0.102)
    static let card = Color(red: 0.099, green: 0.084, blue: 0.136)
    static let gold = Color(red: 0.840, green: 0.684, blue: 0.320)
    static let foreground = Color(red: 0.942, green: 0.926, blue: 0.898)
    static let muted = Color(red: 0.725, green: 0.692, blue: 0.635)
    static let border = Color(red: 0.187, green: 0.168, blue: 0.232)
}

struct SaveddMark: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 64
        var path = Path()
        path.addEllipse(in: CGRect(x: 10.25, y: 10.25, width: 34.5, height: 34.5))
        var drawing = Path()
        drawing.addPath(path.strokedPath(StrokeStyle(lineWidth: 3.1)))
        var handle = Path()
        handle.move(to: CGPoint(x: 40.4, y: 40.4))
        handle.addLine(to: CGPoint(x: 53.2, y: 53.2))
        drawing.addPath(handle.strokedPath(StrokeStyle(lineWidth: 3.4, lineCap: .round)))
        drawing.addRoundedRect(in: CGRect(x: 25.35, y: 16.8, width: 4.3, height: 21.4), cornerSize: CGSize(width: 1.15, height: 1.15))
        drawing.addRoundedRect(in: CGRect(x: 18.9, y: 22.15, width: 17.2, height: 4.15), cornerSize: CGSize(width: 1.15, height: 1.15))
        return drawing.applying(CGAffineTransform(scaleX: scale, y: scale))
    }
}

struct OnboardingBackground: View {
    var body: some View {
        ZStack {
            SaveddBrand.background
            RadialGradient(colors: [SaveddBrand.gold.opacity(0.13), .clear], center: .top, startRadius: 0, endRadius: 440)
            RadialGradient(colors: [Color.purple.opacity(0.08), .clear], center: .bottomLeading, startRadius: 0, endRadius: 360)
        }
        .ignoresSafeArea()
    }
}

struct GoldButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(SaveddBrand.background)
            .background(SaveddBrand.gold.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
