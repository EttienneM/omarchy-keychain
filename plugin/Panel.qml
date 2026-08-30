import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "icloud.keychain"
  ipcTarget: "icloud.keychain"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Color.popups.background
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int fs: Math.round(13 * Style.fontScale)

  // Countdowns read this rather than Date.now() so an open panel keeps telling
  // the truth instead of freezing at the moment it was built.
  property double nowMs: Date.now()
  property string query: ""
  // domain|username of the row whose actions are showing, "" for none.
  property string openRow: ""

  // rowKey|kind of the field copied most recently, cleared on a timer so the
  // confirmation fades by itself. Only one can be showing at a time, which is
  // fine - copying a second field means you are done looking at the first.
  property string copiedTag: ""

  function markCopied(tag) {
    root.copiedTag = tag
    copiedReset.restart()
  }

  Timer {
    id: copiedReset
    interval: 2500
    onTriggered: root.copiedTag = ""
  }

  function codeFor(domain, username) {
    var list = vault.codes || []
    for (var i = 0; i < list.length; i++)
      if (list[i].domain === domain && list[i].username === username) return list[i]
    return null
  }

  readonly property bool attention: vault.needsAuth || vault.stale
  // Each credential carries its own period and exact rollover second, so the
  // countdown is derived per row rather than assuming a shared 30s window.
  function secondsFor(entry) {
    var exp = Number(entry && entry.expires || 0)
    if (exp <= 0) return -1
    return Math.max(0, Math.round(exp - root.nowMs / 1000))
  }

  visible: !(root.setting("hideWhenHealthy", false) && !attention)
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function relTime(seconds) {
    var s = Math.max(0, Math.floor(seconds))
    if (s < 90) return s + "s ago"
    if (s < 5400) return Math.round(s / 60) + "m ago"
    if (s < 172800) return Math.round(s / 3600) + "h ago"
    return Math.round(s / 86400) + "d ago"
  }

  readonly property string stateLabel: {
    if (!vault.loaded) return "checking"
    if (!vault.signedIn) return "signed out"
    if (vault.needsAuth) return "needs you"
    if (vault.stale) return "stale"
    return "synced"
  }
  readonly property color stateColor:
    (!vault.signedIn || vault.needsAuth) ? urgent
    : vault.stale ? accent : foreground

  readonly property var filtered: {
    var q = query.trim().toLowerCase()
    var src = vault.logins || []
    var out = []
    for (var i = 0; i < src.length && out.length < 40; i++) {
      var r = src[i]
      if (q === "" || String(r.title).toLowerCase().indexOf(q) >= 0
          || String(r.username).toLowerCase().indexOf(q) >= 0
          || String(r.domain).toLowerCase().indexOf(q) >= 0)
        out.push(r)
    }
    return out
  }

  // NOT `data`: every QQuickItem has a built-in `data` property holding its
  // children, which shadows an id of that name inside any Item scope.
  Main { id: vault; settings: root.settings }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    // Same path the per-field buttons take, reachable from a script.
    function copy(domain: string, username: string, kind: string): void {
      vault.copySecret(domain, username, kind)
    }
  }

  Timer {
    interval: Math.max(15, Number(root.setting("refreshIntervalSec", 60))) * 1000
    running: true; repeat: true
    onTriggered: vault.refreshStatus()
  }
  Timer {
    interval: 1000; running: root.opened; repeat: true
    onTriggered: root.nowMs = Date.now()
  }
  Timer {
    // Codes roll every 30s; refetch just after each boundary.
    interval: 15000; running: root.opened; repeat: true
    onTriggered: vault.refreshCodes()
  }

  onOpenedChanged: if (opened) {
    root.nowMs = Date.now()
    root.query = ""
    root.openRow = ""
    root.copiedTag = ""
    vault.refreshStatus(); vault.refreshCodes(); vault.refreshLogins()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌋"
    active: root.attention
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) vault.syncNow()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: column
          width: parent.width
          spacing: Style.space(14)

          // ------------------------------------------------------- header
          Item {
            width: parent.width
            implicitHeight: Math.max(title.implicitHeight, pill.implicitHeight)

            Column {
              id: title
              anchors.left: parent.left
              spacing: Style.space(2)
              Text {
                text: "iCloud Keychain"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: root.fs + 2
                font.weight: Font.DemiBold
              }
              Text {
                text: vault.username || "not signed in"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: root.fs - 1
                elide: Text.ElideRight
                width: Math.min(implicitWidth, column.width - Style.space(110))
              }
            }

            Rectangle {
              id: pill
              anchors.right: parent.right
              anchors.verticalCenter: title.verticalCenter
              radius: height / 2
              implicitWidth: pillText.implicitWidth + Style.space(16)
              implicitHeight: pillText.implicitHeight + Style.space(6)
              color: root.alpha(root.stateColor, 0.16)
              border.width: 1
              border.color: root.alpha(root.stateColor, 0.5)
              Text {
                id: pillText
                anchors.centerIn: parent
                text: root.stateLabel
                color: root.stateColor
                font.family: root.fontFamily
                font.pixelSize: root.fs - 2
              }
            }
          }

          // -------------------------------------------------------- stats
          Row {
            width: parent.width
            spacing: Style.space(20)

            Repeater {
              model: [
                { k: "logins",     v: vault.credentials > 0 ? String(vault.credentials) : "—" },
                { k: "codes",      v: vault.totpCount > 0 ? String(vault.totpCount) : "—" },
                { k: "synced",     v: vault.vaultAge > 0 ? root.relTime(vault.vaultAge) : "never" }
              ]
              Column {
                spacing: Style.space(1)
                Text {
                  text: modelData.v
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: root.fs + 1
                  font.weight: Font.DemiBold
                }
                Text {
                  text: modelData.k
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: root.fs - 3
                }
              }
            }
          }

          Rectangle {
            width: parent.width; height: 1
            color: root.alpha(root.foreground, 0.12)
          }

          // ------------------------------------------------------ search
          Rectangle {
            width: parent.width
            implicitHeight: Style.space(32)
            radius: Style.space(5)
            color: root.alpha(root.foreground, 0.06)
            border.width: 1
            border.color: search.activeFocus ? root.alpha(root.accent, 0.6)
                                             : root.alpha(root.foreground, 0.12)

            TextInput {
              id: search
              anchors.fill: parent
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              verticalAlignment: TextInput.AlignVCenter
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: root.fs - 1
              selectByMouse: true
              clip: true
              onTextChanged: { root.query = text; root.openRow = ""; root.copiedTag = "" }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Search " + (vault.credentials || 0) + " logins…"
                color: root.dim
                font: parent.font
                visible: parent.text === ""
              }
            }
          }

          // ------------------------------------------------------ actions
          Row {
            width: parent.width
            spacing: Style.space(8)

            Repeater {
              model: [
                { label: vault.busy ? "Syncing\u2026" : "Sync now", act: "sync" },
                { label: "Re-authenticate",                        act: "login" },
                { label: "Hide My Email",                          act: "show" }
              ]

              Button {
                required property var modelData

                text: modelData.label
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: {
                  if (modelData.act === "sync") vault.syncNow()
                  else { vault.authenticate(modelData.act); root.close() }
                }
              }
            }
          }

          // ------------------------------------------------------ results
          Column {
            width: parent.width
            spacing: Style.space(2)
            visible: root.query.trim() !== ""

            Repeater {
              model: root.filtered

              Column {
                id: entry
                width: parent.width
                readonly property var rowData: modelData
                readonly property string rowKey: modelData.domain + "|" + modelData.username
                readonly property bool isOpen: root.openRow === rowKey
                // Only looked up while the row is on screen; the codes list is small.
                readonly property var fieldActions: {
                  var m = [{ label: "Username", kind: "username" },
                           { label: "Password", kind: "password" }]
                  if (modelData.has_totp) m.push({ label: "Code", kind: "totp" })
                  return m
                }
                readonly property var liveCode: modelData.has_totp
                  ? root.codeFor(modelData.domain, modelData.username) : null

                Rectangle {
                  width: parent.width
                  implicitHeight: Style.space(30)
                  radius: Style.space(5)
                  color: entry.isOpen ? root.alpha(root.accent, 0.14)
                       : rowHover.containsMouse ? root.alpha(root.foreground, 0.07) : "transparent"

                  MouseArea {
                    id: rowHover
                    anchors.fill: parent
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.openRow = entry.isOpen ? "" : entry.rowKey
                      root.copiedTag = ""
                    }
                  }

                  Column {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Style.space(120)
                    spacing: 0
                    Text {
                      text: entry.rowData.title
                      color: root.foreground
                      elide: Text.ElideRight
                      width: parent.width
                      font.family: root.fontFamily
                      font.pixelSize: root.fs - 1
                    }
                    Text {
                      // icp's title usually already names the account, so repeating it
                      // wastes the line - fall back to the bare domain when it does.
                      text: String(entry.rowData.title).indexOf(entry.rowData.username) >= 0
                            ? entry.rowData.domain : entry.rowData.username
                      color: root.dim
                      elide: Text.ElideRight
                      width: parent.width
                      font.family: root.fontFamily
                      font.pixelSize: root.fs - 3
                    }
                  }

                  Row {
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(6)

                    // A matching code is shown inline, so a search for the site you are
                    // signing into surfaces its code without any further clicks.
                    Text {
                      visible: entry.liveCode !== null
                      text: entry.liveCode ? entry.liveCode.code : ""
                      color: root.accent
                      font.family: root.fontFamily
                      font.pixelSize: root.fs
                      font.weight: Font.DemiBold
                    }
                    Text {
                      visible: entry.liveCode !== null
                      text: entry.liveCode ? root.secondsFor(entry.liveCode) + "s" : ""
                      color: (entry.liveCode && root.secondsFor(entry.liveCode) <= 5)
                             ? root.urgent : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: root.fs - 3
                    }
                    Text {
                      text: entry.isOpen ? "\u25B4" : "\u25BE"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: root.fs - 2
                    }
                  }
                }

                // --------------------------------------------- per-field copy
                Row {
                  visible: entry.isOpen
                  leftPadding: Style.space(8)
                  topPadding: Style.space(4)
                  bottomPadding: Style.space(8)
                  spacing: Style.space(6)

                  Repeater {
                    model: entry.fieldActions

                    Button {
                      // Qt 6 only injects modelData into a delegate that asks for it by
                      // name; without this the label and kind come back undefined.
                      required property var modelData

                      readonly property string tag: entry.rowKey + "|" + modelData.kind
                      readonly property bool copied: root.copiedTag === tag

                      // The tick is appended rather than replacing the label so the
                      // button keeps its identity while confirming.
                      text: copied ? modelData.label + "  \u2713" : modelData.label
                      active: copied
                      bordered: true
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      fontSize: Style.font.bodySmall
                      onClicked: {
                        vault.copySecret(entry.rowData.domain, entry.rowData.username,
                                         modelData.kind)
                        root.markCopied(tag)
                      }
                    }
                  }
                }
              }
            }

            Text {
              visible: root.filtered.length === 0
              text: "No match"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: root.fs - 1
            }
          }

          Rectangle {
            width: parent.width; height: 1
            color: root.alpha(root.foreground, 0.12)
            visible: root.query.trim() !== ""
          }

        }
      }
    }
  }
}
