import QtQuick
import Quickshell
import qs.Ui
import qs.Commons

// Bar button + popup holding the ARRANGEMENT section. Keyboard: h/l choose a
// display, Enter picks it up, h/l move it, Enter drops it.
Panel {
  id: root
  moduleName: "monitor-layout"
  ipcTarget: "monitor-layout"

  property bool cursorActive: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) cursorActive = false

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰍺"
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(400))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dx !== 0) arrangement.moveCursor(dx)
      }
      onActivateRequested: if (root.cursorActive) arrangement.activate()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: panelColumn
        width: parent.width
        spacing: Style.space(14)

        // ---------- Hero ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: "󰍺"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Monitor Layout"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: arrangement.tiles.length === 1 ? "1 DISPLAY" : arrangement.tiles.length + " DISPLAYS"
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        Arrangement {
          id: arrangement
          width: parent.width
          visible: available
          bar: root.bar
          active: root.opened
          focused: true
          cursorActive: root.cursorActive
          onFocusRequested: root.cursorActive = true
        }

        Text {
          width: parent.width
          visible: !arrangement.available
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: "Connect another display to arrange it."
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          width: parent.width
          visible: arrangement.available
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: "The pointer crosses between neighbouring displays. The layout is kept when displays are reconnected."
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
