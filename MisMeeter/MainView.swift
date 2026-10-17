import SwiftUI

struct MainView: View {
    @StateObject private var vm=MainViewModel(); @State private var settings=false
    var body: some View { NavigationStack { Form { Section { Picker("Mode",selection:$vm.mode) { ForEach(MainViewModel.Mode.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).disabled(vm.running) }
        Section("Stream") { TextField("Stream name",text:$vm.streamName).disabled(vm.running); if vm.mode == .transmit { TextField("Destination IP",text:$vm.host).keyboardType(.numbersAndPunctuation).disabled(vm.running) }; Stepper("UDP port: \(vm.port)",value:$vm.port,in:1...65535).disabled(vm.running) }
        Section("Audio") { VUMeterView(rms:vm.rms,peak:vm.peak).padding(.vertical,8) }
        Section("Diagnostics") { LabeledContent("Status",value:vm.status); LabeledContent("Packets",value:"\(vm.packets)"); LabeledContent("Lost",value:"\(vm.lost)"); LabeledContent("Playout buffer",value:String(format:"%.1f ms",vm.latencyMS)) }
        Section { Button(vm.running ? "Stop" : "Start") { vm.toggle() }.frame(maxWidth:.infinity).fontWeight(.semibold) }
    }.navigationTitle("MisMeeter").toolbar { Button { settings=true } label:{ Image(systemName:"gearshape") }.disabled(vm.running) }.sheet(isPresented:$settings) { SettingsView() } } }
}