import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.components

// ============================================================================
//  MediaPanel — rediseño "cover hero" (S19; variaciones A/B/C documentadas en
//  PROJECT_STATE.md). La carátula es la cabecera de la tarjeta, fundida hacia
//  `base` con un degradado sobre el que viven título/artista y un chip con la
//  fuente MPRIS; debajo, scrubber fino con tiempos y transporte centrado con
//  play circular en acento. Sin carátula: fondo degradado + icono de nota.
//  El ecualizador de S10 se conserva íntegro pero plegado en un acordeón,
//  colapsado por defecto.
//
//  Backend MPRIS (services/Media.qml) SIN cambios — solo presentación.
// ============================================================================
AnchoredPanel {
    id: mp
    panelKey: "mediaPlayer"
    ns: "vexyon-media"
    panelWidth: 400
    contentMargin: 0          // el cover llega al borde de la tarjeta
    accentColor: Theme.green

    // 10-band genre presets (relative gains, -10..+10) purely to shape the UI
    readonly property var presets: ({
        "Flat":    [0,0,0,0,0,0,0,0,0,0],
        "Bass":    [7,6,5,3,1,0,0,0,0,0],
        "Treble":  [0,0,0,0,0,1,3,5,6,7],
        "Vocal":   [-2,-1,0,2,4,4,3,1,0,-1],
        "Pop":     [-1,0,2,4,4,3,1,0,-1,-1],
        "Rock":    [5,4,2,0,-1,-1,1,3,4,5],
        "Jazz":    [3,2,1,2,-1,-1,0,1,2,3],
        "Classic": [4,3,2,1,0,0,-1,-1,2,3]
    })
    readonly property var bandLabels: ["31","62","125","250","500","1k","2k","4k","8k","16k"]
    property string preset: Config.get("equalizer", "preset", "Flat")
    property var gains: presets[preset] || presets["Flat"]

    function applyPreset(name) {
        mp.preset = name;
        mp.gains = mp.presets[name] || mp.presets["Flat"];
        Config.set("equalizer", "preset", name);
        Quickshell.execDetached(["bash", "-c",
            "command -v easyeffects >/dev/null && easyeffects -l " + JSON.stringify(name) + " >/dev/null 2>&1 || true"]);
    }

    content: Component {
        ColumnLayout {
            id: body
            width: mp.panelWidth
            spacing: 0
            property real introHeader: 1
            property real introContent: 1
            property bool eqOpen: false

            // ================= COVER HERO (fase introHeader) =================
            Item {
                id: hero
                Layout.fillWidth: true
                Layout.preferredHeight: 220
                opacity: body.introHeader

                // carátula a sangre (o fondo degradado si no hay), recortada al
                // radio de la tarjeta: el clip de QML es rectangular, así que
                // sin esto la esquina superior pinta CUADRADA por encima del
                // borde redondeado del AnchoredPanel (radius = Theme.radius+8).
                // El redondeo inferior del recorte queda oculto bajo el
                // degradado hacia base.
                ClippingRectangle {
                    anchors.fill: parent
                    radius: Theme.radius + 8
                    color: "transparent"
                    Image {
                        id: cover
                        anchors.fill: parent
                        source: Media.artUrl
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: status === Image.Ready && Media.artUrl !== ""
                    }
                    Rectangle {
                        anchors.fill: parent
                        visible: !cover.visible
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(Theme.green.r, Theme.green.g, Theme.green.b, 0.16) }
                            GradientStop { position: 1.0; color: Theme.base }
                        }
                        Text {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: -20
                            text: Icons.music
                            color: Qt.rgba(Theme.green.r, Theme.green.g, Theme.green.b, 0.5)
                            font.family: Theme.fontFamily
                            font.pixelSize: 64
                        }
                    }
                }

                // degradado de lectura: transparente → base (funde con la tarjeta)
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.35; color: "transparent" }
                        GradientStop { position: 1.0; color: Theme.base }
                    }
                }

                // chip de fuente (identity MPRIS) arriba a la derecha
                Rectangle {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 12
                    visible: Media.identity !== ""
                    width: srcRow.implicitWidth + 18
                    height: 24
                    radius: 12
                    color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.72)
                    border.width: 1
                    border.color: Qt.rgba(Theme.overlay0.r, Theme.overlay0.g, Theme.overlay0.b, 0.5)
                    RowLayout {
                        id: srcRow
                        anchors.centerIn: parent
                        spacing: 5
                        Text { text: Icons.music; color: Theme.green; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 5 }
                        Text {
                            text: Media.identity
                            color: Theme.subtext1
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 4
                        }
                    }
                }

                // título / artista sobre el degradado
                ColumnLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    anchors.bottomMargin: 8
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: Media.present ? (Media.title || I18n.t("Untitled")) : I18n.t("Nothing playing")
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 5
                        font.bold: true
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: Media.artist !== ""
                        text: Media.artist
                        color: Theme.subtext1
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }
            }

            // ================= CUERPO (fase introContent) ====================
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                Layout.topMargin: 10
                Layout.bottomMargin: 18
                spacing: 12
                opacity: body.introContent
                transform: Translate { y: 14 * (1 - body.introContent) }

                // ---- scrubber ----
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: Media.present
                    spacing: 2
                    Slider {
                        Layout.fillWidth: true
                        value: Media.progress
                        fillColor: Theme.green
                        onMoved: function(v) { Media.seekTo(v); }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: Media.fmtTime(Media.position); color: Theme.subtext0; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 3 }
                        Item { Layout.fillWidth: true }
                        Text { text: Media.fmtTime(Media.length); color: Theme.subtext0; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 3 }
                    }
                }

                // ---- transporte ----
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 22
                    IconButton {
                        icon: Icons.stepBack
                        iconSize: Theme.fontSize + 5
                        implicitWidth: 42; implicitHeight: 42
                        enabled: Media.present
                        onClicked: Media.previous()
                    }
                    Rectangle {
                        Layout.preferredWidth: 56; Layout.preferredHeight: 56
                        radius: 28
                        color: Theme.green
                        scale: ppMa.pressed ? 0.92 : ppMa.containsMouse ? 1.05 : 1.0
                        Behavior on scale { NumberAnimation { duration: Theme.dur(90) } }
                        Text {
                            anchors.centerIn: parent
                            text: Media.playing ? Icons.pause : Icons.play
                            color: Theme.crust
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize + 9
                        }
                        MouseArea {
                            id: ppMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: Media.present
                            onClicked: Media.toggle()
                        }
                    }
                    IconButton {
                        icon: Icons.stepForward
                        iconSize: Theme.fontSize + 5
                        implicitWidth: 42; implicitHeight: 42
                        enabled: Media.present
                        onClicked: Media.next()
                    }
                }

                // ---- ecualizador plegable ----
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: eqCol.implicitHeight + 20
                    radius: Theme.radius
                    color: Theme.surface0
                    border.width: 1
                    border.color: Qt.rgba(Theme.overlay0.r, Theme.overlay0.g, Theme.overlay0.b, 0.4)
                    clip: true
                    Behavior on implicitHeight { NumberAnimation { duration: Theme.dur(200); easing.type: Theme.easing } }

                    ColumnLayout {
                        id: eqCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 10

                        // cabecera del acordeón
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                text: I18n.t("Equalizer")
                                color: Theme.subtext1
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 1
                                font.bold: true
                            }
                            Text {
                                text: mp.preset
                                color: Theme.green
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: body.eqOpen ? Icons.chevronDown : Icons.chevronRight
                                color: Theme.overlay1
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: body.eqOpen = !body.eqOpen
                            }
                        }

                        // contenido plegable: bandas + presets
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: body.eqOpen
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 96
                                spacing: 4
                                Repeater {
                                    model: 10
                                    delegate: ColumnLayout {
                                        required property int index
                                        Layout.fillWidth: true
                                        spacing: 4
                                        Item {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 74
                                            Rectangle {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                width: 5; height: parent.height; radius: 3
                                                color: Theme.surface2
                                                readonly property real g: (mp.gains[index] || 0) / 10
                                                Rectangle {
                                                    width: parent.width; radius: 3; color: Theme.green
                                                    height: Math.abs(parent.g) * (parent.height / 2)
                                                    y: parent.g >= 0 ? (parent.height / 2 - height) : (parent.height / 2)
                                                    Behavior on height { NumberAnimation { duration: Theme.dur(200) } }
                                                    Behavior on y { NumberAnimation { duration: Theme.dur(200) } }
                                                }
                                                Rectangle {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: parent.width + 4; x: -2; height: 1
                                                    color: Theme.overlay1
                                                }
                                            }
                                        }
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: mp.bandLabels[index]
                                            color: Theme.overlay2
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize - 5
                                        }
                                    }
                                }
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 6
                                Repeater {
                                    model: ["Flat","Bass","Treble","Vocal","Pop","Rock","Jazz","Classic"]
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property bool sel: mp.preset === modelData
                                        width: chipT.implicitWidth + 22; height: 30; radius: 15
                                        color: sel ? Theme.green : (chMa.containsMouse ? Theme.surface1 : Theme.surface0)
                                        border.width: sel ? 0 : 1
                                        border.color: Theme.overlay0
                                        Behavior on color { ColorAnimation { duration: Theme.dur(120) } }
                                        Text {
                                            id: chipT
                                            anchors.centerIn: parent
                                            text: I18n.t(parent.modelData)
                                            color: parent.sel ? Theme.crust : Theme.subtext1
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize - 2
                                        }
                                        MouseArea {
                                            id: chMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: mp.applyPreset(parent.modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
