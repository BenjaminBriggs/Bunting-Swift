import SwiftUI

// This could be much improved to make a better
// json input experience but for now this is fine
struct JSONEditorView: View {
    @Binding var text: String
    var body: some View {
        TextEditor(text: $text)
            .font(.system(.body, design: .monospaced))
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button("Format") {
                        if let pretty = prettyPrintedJSON(text) {
                            text = pretty
                        }
                    }
                }
            }
    }
    
    private func prettyPrintedJSON(_ text: String) -> String? {
        guard let data = text.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        guard JSONSerialization.isValidJSONObject(obj) else { return nil }
        guard let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]) else { return nil }
        return String(data: pretty, encoding: .utf8)
    }
    
    private var isJSONValid: Bool {
        prettyPrintedJSON(text) != nil
    }
}
