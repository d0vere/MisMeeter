import SwiftUI
import WidgetKit

@main
struct MisMeeterWidgetBundle: WidgetBundle {
    var body: some Widget {
        MisMeeterStatusWidget()
        MisMeeterLiveActivity()
        MisMeeterReceiveMuteControl()
        MisMeeterMicrophoneMuteControl()
    }
}
