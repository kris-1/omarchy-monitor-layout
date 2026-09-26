import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Ui
import qs.Commons

// "Keep these display settings?" after a change tried in the properties
// window: a modal card centered on a dimmed screen, counting down to the
// automatic revert, in the manner of Windows' display settings. Revert is
// preselected, so a blind Enter on a display that went dark restores it.
PanelWindow {
  id: root

  property bool open: false
  // Seconds left and the whole countdown, for the text and the bar.
  property int seconds: 0
  property int totalSeconds: 30
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  // 0 = Revert, 1 = Keep changes.
  property int selectedIndex: 0

  signal kept()
  signal reverted()

  function choose(index) {
    if (index === 1) root.kept()
    else root.reverted()
  }

  onOpenChanged: if (open) {
    selectedIndex = 0
    Qt.callLater(function() { if (root.open) keys.forceActiveFocus() })
  }

  visible: open || card.opacity > 0
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "omarchy-monitor-keep-settings"
  WlrLayershell.layer: WlrLayer.Overlay
  // Modal while it counts down: it owns the keyboard.
  WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  Rectangle {
    id: scrim
    anchors.fill: parent
    color: Util.alpha(Color.background, 0.6)
    opacity: card.opacity

    // Modal: clicks outside the card do nothing.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
    }
  }

  Item {
    id: keys
    anchors.fill: parent
    focus: true

    Keys.onPressed: function(event) {
      if (!root.open) return
      if (event.key === Qt.Key_Escape) {
        root.reverted()
      } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Tab
          || event.key === Qt.Key_Backtab || event.text === "h" || event.text === "l") {
        root.selectedIndex = root.selectedIndex === 0 ? 1 : 0
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
        root.choose(root.selectedIndex)
      } else {
        return
      }
      event.accepted = true
    }
  }

  BorderSurface {
    id: card
    width: Math.min(parent.width - Style.space(32), Style.space(420))
    height: content.implicitHeight + card.contentTopInset + card.contentBottomInset
    anchors.centerIn: parent
    color: Color.popups.background
    borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)
    padding: Style.space(20)
    radius: Style.cornerRadius
    opacity: root.open ? 1.0 : 0
    scale: root.open ? 1.0 : 0.96

    Behavior on opacity {
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }
    Behavior on scale {
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    Column {
      id: content
      x: card.contentLeftInset
      y: card.contentTopInset
      width: card.width - card.contentLeftInset - card.contentRightInset
      spacing: Style.space(16)

      Item {
        width: parent.width
        implicitHeight: Math.max(icon.implicitHeight, labels.implicitHeight)

        Text {
          id: icon
          textFormat: Text.PlainText
          text: "󰍹"
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.display
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          id: labels
          anchors.left: icon.right
          anchors.leftMargin: Style.space(14)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: "Keep these display settings?"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            wrapMode: Text.WordWrap
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: "Reverting to the previous settings in " + root.seconds
              + (root.seconds === 1 ? " second." : " seconds.")
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }
        }
      }

      // Runs out with the countdown.
      Item {
        width: parent.width
        height: Math.max(2, Style.space(3))

        Rectangle {
          anchors.fill: parent
          radius: height / 2
          color: Util.alpha(root.foreground, 0.12)
        }

        Rectangle {
          height: parent.height
          radius: height / 2
          width: parent.width * (root.totalSeconds > 0 ? Math.max(0, root.seconds) / root.totalSeconds : 0)
          color: Color.accent

          Behavior on width {
            enabled: root.open
            NumberAnimation { duration: 1000; easing.type: Easing.Linear }
          }
        }
      }

      Row {
        anchors.right: parent.right
        spacing: Style.space(10)

        Repeater {
          model: ["Revert", "Keep changes"]

          BorderSurface {
            required property int index
            required property string modelData

            readonly property bool selected: root.selectedIndex === index

            width: Math.max(Style.space(96), label.implicitWidth + Style.space(28))
            height: Style.space(34)
            color: selected ? Util.alpha(root.foreground, 0.08) : "transparent"
            borderSpec: Border.flat(selected ? Color.accent : Util.alpha(root.foreground, 0.38), Style.normalBorderWidth)
            radius: 0

            Text {
              id: label
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: modelData
              color: selected ? Color.accent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: index === 1
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.selectedIndex = index
              onClicked: root.choose(index)
            }
          }
        }
      }
    }
  }
}
