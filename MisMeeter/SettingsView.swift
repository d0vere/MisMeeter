import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("host") private var host="192.168.1.100"; @AppStorage("port") private var port=6980; @AppStorage("stream") private var stream="Stream1"; @AppStorage("ioBuffer") private var ioBuffer=0.005
    var body: some View { NavigationStack { Form { Section("VBAN") { TextField("Destination IP",text:$host).keyboardType(.numbersAndPunctuation); TextField("Stream name",text:$stream); Stepper("UDP port: \(port)",value:$port,in:1...65535) }; Section("Low latency audio") { Picker("I/O buffer",selection:$ioBuffer) { Text("5 ms").tag(0.005); Text("10 ms").tag(0.010); Text("20 ms").tag(0.020) }; Text("iOS treats this as a preferred value; the actual hardware duration may differ.").font(.footnote).foregroundStyle(.secondary) } }.navigationTitle("Settings").toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } } } }
}