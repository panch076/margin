import SwiftUI

/// The Desmos graphing calculator in the configuration used for the digital SAT.
/// It needs an internet connection; everything else in the app works offline.
struct CalculatorView: View {
    private let address = URL(string: "https://www.desmos.com/testing/cb-digital-sat/graphing")

    var body: some View {
        Group {
            if let address {
                RemoteWebView(url: address)
            } else {
                Text("The calculator is unavailable.")
            }
        }
        .frame(minWidth: 360, minHeight: 360)
    }
}

struct ReferenceView: View {
    private let sheet: [(title: String, lines: [String])] = [
        ("Circle", ["Area  A = πr²", "Circumference  C = 2πr"]),
        ("Rectangle and triangle", ["Rectangle area  A = ℓw", "Triangle area  A = ½bh"]),
        ("Right triangles", ["Pythagorean theorem  c² = a² + b²", "30°-60°-90° sides  x,  x√3,  2x", "45°-45°-90° sides  s,  s,  s√2"]),
        ("Volume", ["Rectangular prism  V = ℓwh", "Cylinder  V = πr²h", "Sphere  V = (4/3)πr³", "Cone  V = (1/3)πr²h", "Pyramid  V = (1/3)ℓwh"]),
        ("Facts", ["A circle has 360 degrees of arc.", "A circle has 2π radians of arc.", "The angles of a triangle add up to 180 degrees."]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(sheet, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.title).font(.headline)
                        ForEach(group.lines, id: \.self) { line in
                            Text(line).font(.system(size: 15))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .frame(minWidth: 340, minHeight: 320)
    }
}
