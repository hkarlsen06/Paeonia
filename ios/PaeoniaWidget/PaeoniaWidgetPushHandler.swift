#if WIDGET_EXTENSION
import WidgetKit

struct PaeoniaWidgetPushHandler: WidgetPushHandler {
    func pushTokenDidChange(_ pushInfo: WidgetPushInfo, widgets: [WidgetInfo]) {
        PaeoniaWidgetPushTokenStore.shared.save(
            tokenData: pushInfo.token,
            widgetKinds: widgets.map(\.kind)
        )
    }
}
#endif
