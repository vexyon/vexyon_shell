pragma Singleton

import QtQuick
import Quickshell
import qs.services

// Wall clock. Single 1s timer shared by every widget that shows time.
Singleton {
    id: root
    property string time: ""
    property string date: ""
    property var now: new Date()
    // Dígits separats per al rellotge estil DMS (amplada fixa per dígit)
    property string hh: ""
    property string mm: ""
    property string ss: ""

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            var d = new Date();
            root.now = d;
            root.time = Qt.formatDateTime(d, "HH:mm");
            // day/month names follow the shell language, not the system locale
            root.date = d.toLocaleDateString(I18n.locale, "ddd d MMM");
            root.hh = Qt.formatDateTime(d, "HH");
            root.mm = Qt.formatDateTime(d, "mm");
            root.ss = Qt.formatDateTime(d, "ss");
        }
    }
}
