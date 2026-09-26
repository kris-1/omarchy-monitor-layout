import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Ui
import qs.Commons

// "Identify", as in Windows' display settings: a large number and name in the
// corner of each listed display, so the tiles can be matched to the screens on
// the desk. Click-through and never takes the keyboard.
Scope {
  id: root

  // [{ output, number, label }]; displays not listed show nothing.
  property var entries: []
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  function entryFor(output) {
    for (var i = 0; i < entries.length; i++)
      if (entries[i].output === output) return entries[i]
    return null
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: badge
        required property var modelData

        readonly property var entry: root.entryFor(modelData.name)
        property var shown: null

        onEntryChanged: if (entry) shown = entry

        screen: modelData
        visible: !!entry || card.opacity > 0
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "omarchy-monitor-identify"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}

        anchors {
          left: true
          bottom: true
        }
        margins {
          left: Style.space(40)
          bottom: Style.space(40)
        }
        implicitWidth: card.width
        implicitHeight: card.height

        BorderSurface {
          id: card
          width: row.implicitWidth + card.contentLeftInset + card.contentRightInset
          height: row.implicitHeight + card.contentTopInset + card.contentBottomInset
          color: Color.popups.background
          borderSpec: Border.flat(Color.accent, Math.max(1, Style.space(2)))
          padding: Style.space(24)
          radius: Style.cornerRadius
          opacity: badge.entry ? 1.0 : 0

          Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
          }

          Row {
            id: row
            x: card.contentLeftInset
            y: card.contentTopInset
            spacing: Style.space(24)

            Text {
              textFormat: Text.PlainText
              text: badge.shown ? String(badge.shown.number) : ""
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.display * 4
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              spacing: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter

              Text {
                textFormat: Text.PlainText
                text: badge.shown ? badge.shown.label : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                font.bold: true
              }

              Text {
                textFormat: Text.PlainText
                text: badge.modelData.name.toUpperCase()
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
              }
            }
          }
        }
      }
    }
  }
}
