import SwiftUI
import WebKit

struct USMapView: UIViewRepresentable {
    let spottedStates: Set<String>

    private static let stateAbbreviations: [String: String] = [
        "Alabama": "al", "Alaska": "ak", "Arizona": "az", "Arkansas": "ar",
        "California": "ca", "Colorado": "co", "Connecticut": "ct",
        "Delaware": "de", "District of Columbia": "dc", "Florida": "fl",
        "Georgia": "ga", "Hawaii": "hi", "Idaho": "id", "Illinois": "il",
        "Indiana": "in", "Iowa": "ia", "Kansas": "ks", "Kentucky": "ky",
        "Louisiana": "la", "Maine": "me", "Maryland": "md",
        "Massachusetts": "ma", "Michigan": "mi", "Minnesota": "mn",
        "Mississippi": "ms", "Missouri": "mo", "Montana": "mt",
        "Nebraska": "ne", "Nevada": "nv", "New Hampshire": "nh",
        "New Jersey": "nj", "New Mexico": "nm", "New York": "ny",
        "North Carolina": "nc", "North Dakota": "nd", "Ohio": "oh",
        "Oklahoma": "ok", "Oregon": "or", "Pennsylvania": "pa",
        "Rhode Island": "ri", "South Carolina": "sc", "South Dakota": "sd",
        "Tennessee": "tn", "Texas": "tx", "Utah": "ut", "Vermont": "vt",
        "Virginia": "va", "Washington": "wa", "West Virginia": "wv",
        "Wisconsin": "wi", "Wyoming": "wy"
    ]

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.clipsToBounds = true
        webView.layer.cornerRadius = 12
        loadMap(into: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        loadMap(into: webView)
    }

    private func loadMap(into webView: WKWebView) {
        var svgContent = USMapSVGData.svgContent
            .replacingOccurrences(of: "width=\"959\" height=\"593\"",
                                  with: "viewBox=\"0 0 959 593\" preserveAspectRatio=\"xMidYMid meet\"")

        if let defsStart = svgContent.range(of: "<defs>"),
           let defsEnd = svgContent.range(of: "</defs>") {
            svgContent.removeSubrange(defsStart.lowerBound...defsEnd.upperBound)
        }

        let spottedAbbreviations = Set(spottedStates.compactMap { Self.stateAbbreviations[$0] })

        let stateCSS = spottedAbbreviations.map { abbr in
            return "g.state path.\(abbr) { fill: #3B82F6 !important; }"
        }.joined(separator: "\n            ")

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            html, body { width: 100%; height: 100%; overflow: hidden; background: #22C55E; }
            svg { display: block; width: 100%; height: auto; }
            g.state path { fill: #FFFFFF !important; }
            g.borders { stroke: #22C55E !important; stroke-width: 1.5; }
            g.borders path { stroke: #22C55E !important; }
            path.separator1 { stroke: #22C55E !important; }
            circle.dc { fill: \(spottedAbbreviations.contains("dc") ? "#3B82F6" : "#FFFFFF") !important; }
            \(stateCSS)
        </style>
        </head>
        <body>
        \(svgContent)
        </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: nil)
    }
}

#Preview {
    USMapView(spottedStates: ["California", "Texas", "New York", "Florida", "Ohio", "Washington"])
        .frame(height: 220)
        .padding()
}
