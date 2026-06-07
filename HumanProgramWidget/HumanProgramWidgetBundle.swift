import WidgetKit
import SwiftUI

@main
struct HumanProgramWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayCountWidget()
        TodayListWidget()
    }
}
