import SwiftUI

struct ContentView: View {
  @State private var result = "n/a"

  var body: some View {
    VStack(spacing: 16) {
      Text("LiteRT CPU")
        .font(.title)

      Text(result)
        .font(.system(.body, design: .monospaced))

      Button("Run inference") {
        do {
          let output = try LiteRTRunner.runOnCPU()
          result = output.map { String($0) }.joined(separator: ", ")
        } catch {
          result = "Error: \(error)"
        }
      }
      .buttonStyle(.borderedProminent)
    }
    .padding()
  }
}
