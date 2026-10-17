import SwiftUI

struct VUMeterView: View {
    let rms:Float; let peak:Float
    private func db(_ x:Float)->Float { 20*log10(max(x,0.000001)) }
    private func n(_ x:Float)->CGFloat { CGFloat(min(max((db(x)+60)/60,0),1)) }
    var body: some View { VStack(alignment:.leading,spacing:8) { GeometryReader { g in ZStack(alignment:.leading) { Capsule().fill(.secondary.opacity(0.18)); Capsule().fill(.green).frame(width:g.size.width*n(rms)); Rectangle().fill(.primary).frame(width:2).offset(x:max(0,g.size.width*n(peak)-1)) } }.frame(height:12); HStack { Text(String(format:"RMS %.1f dB",db(rms))); Spacer(); Text(String(format:"Peak %.1f dB",db(peak))) }.font(.caption.monospacedDigit()).foregroundStyle(.secondary) } }
}