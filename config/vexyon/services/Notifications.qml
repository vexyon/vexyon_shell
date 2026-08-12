pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.services

// Notification center state: a live freedesktop notification server whose
// notifications are tracked (kept in a history list) plus the Do-Not-Disturb
// flag (persisted in shell.json). The notification-center panel renders the
// list; the bar widget surfaces DND + unread count.
Singleton {
    id: root

    readonly property bool dnd: Config.get("notifications", "dnd", false)
    property int unread: 0

    // tracked notifications (kept in history), exposed to the panel
    readonly property var list: server.trackedNotifications ? server.trackedNotifications.values : []
    readonly property int count: root.list.length

    NotificationServer {
        id: server
        keepOnReload: false
        bodySupported: true
        imageSupported: true
        actionsSupported: true
        onNotification: function(n) {
            n.tracked = true;              // keep it in the history list
            if (!root.dnd) root.unread++;  // count toward the badge unless DND
        }
    }

    function toggleDnd() { Config.set("notifications", "dnd", !root.dnd); }
    function clear() { root.unread = 0; }
    function dismiss(n) { if (n) n.dismiss(); }
    function clearAll() {
        var l = root.list.slice();
        for (var i = 0; i < l.length; i++) if (l[i]) l[i].dismiss();
        root.unread = 0;
    }
}
