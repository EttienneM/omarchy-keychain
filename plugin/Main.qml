import QtQuick
import Quickshell
import Quickshell.Io

// Data layer. Every fact comes from the omarchy-keychain-* scripts, so the shell
// process never handles a password itself - `copy` pipes straight into wl-copy
// and its stdout is deliberately never collected here.
Item {
  id: root
  visible: false

  property var settings: ({})
  readonly property string bin: (Quickshell.env("HOME") || "") + "/.local/bin/"

  property var status: ({})
  property var codes: []
  property var logins: []
  property bool busy: false
  property bool loaded: false

  readonly property bool signedIn: status.signed_in === true
  readonly property bool needsAuth: status.needs_auth === true
  readonly property bool stale: status.stale === true
  readonly property int credentials: Number(status.credentials || 0)
  readonly property int totpCount: Number(status.totp_count || 0)
  readonly property string username: String(status.username || "")
  readonly property int vaultAge: Number(status.vault_age_seconds || 0)
  readonly property var lastSync: status.last_sync || ({})

  function parseJson(text, fallback) {
    try {
      var v = JSON.parse(String(text || ""))
      return v === null ? fallback : v
    } catch (e) {
      return fallback
    }
  }

  // ---------------------------------------------------------------- status

  Process {
    id: statusProc
    running: false
    command: [root.bin + "omarchy-keychain-status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.status = root.parseJson(text, ({}))
        root.loaded = true
      }
    }
  }

  function refreshStatus() {
    if (!statusProc.running) statusProc.running = true
  }

  // ----------------------------------------------------------------- codes

  Process {
    id: codesProc
    running: false
    command: [root.icpBin, "codes"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.codes = root.parseJson(text, [])
    }
  }

  readonly property string icpBin:
    (Quickshell.env("ICP_HOME") || ((Quickshell.env("HOME") || "") + "/Code/Omakeychain/src"))
    + "/.venv/bin/icp"

  function refreshCodes() {
    if (!codesProc.running) codesProc.running = true
  }

  // ---------------------------------------------------------------- logins

  Process {
    id: loginsProc
    running: false
    command: [root.icpBin, "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.logins = root.parseJson(text, [])
    }
  }

  function refreshLogins() {
    if (!loginsProc.running) loginsProc.running = true
  }

  // --------------------------------------------------------------- actions

  Process {
    id: syncProc
    running: false
    command: [root.bin + "omarchy-keychain-sync"]
    onExited: {
      root.busy = false
      root.refreshStatus()
    }
  }

  function syncNow() {
    if (syncProc.running) return
    root.busy = true
    syncProc.running = true
  }

  // Detached, not a Process: wl-copy forks a server to own the selection, and that
  // server dies with the process group when a tracked Process finishes - leaving an
  // empty clipboard. execDetached gives it its own session so the selection survives.
  // It also means the secret never passes through this process, which is the point.
  function copySecret(domain, username, kind) {
    Quickshell.execDetached([root.bin + "omarchy-keychain-copy", String(domain || ""),
                             String(username || ""), String(kind || "password")])
  }

  function authenticate(action) {
    Quickshell.execDetached([root.bin + "omarchy-keychain-auth", String(action || "login")])
  }

  Component.onCompleted: refreshStatus()
}
