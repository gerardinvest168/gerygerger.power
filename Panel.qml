import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "asus.gerygerger.power"
  ipcTarget: "omarchy.power"
  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the togglePercentage method below.
  manageIpc: false
  property var batteryInfo: ({})
  property var systemInfo: ({})
  property var profiles: []
  property string activeProfile: ""
  property int profileIndex: 0
  property int chargeLimit: -1
  property bool cursorActive: false
  property bool chargeLimitVerified: false

  // ---------- Auto-dim ----------
  // When enabled, fades brightness to autoDimTarget% after
  // autoDimThreshold seconds of no input activity (keyboard/mouse),
  // and restores it when activity resumes.
  property bool autoDimEnabled: setting("autoDimEnabled", false) === true
  property int autoDimThreshold: parseInt(setting("autoDimThreshold", "300"), 10) // default 5 min
  property int autoDimTarget: parseInt(setting("autoDimTarget", "50"), 10)         // default 50%
  property bool autoDimActive: false          // true while we've dimmed
  property int autoDimFrom: 100              // brightness we dimmed from (for restore)
  readonly property string idleCheckScript: Quickshell.env("HOME") + "/.config/omarchy/plugins/gerygerger.power/idle-check.sh"
  Timer {
    id: autoDimTimer
    interval: 10000                       // poll every 10 s
    running: root.autoDimEnabled
    repeat: true
    triggeredOnStart: false
    onTriggered: root.runAutoDimCheck()
  }
  function runAutoDimCheck() {
    if (!root.brightnessAvailable || root.autoDimThreshold <= 0) return
    idleProc.running = true
  }

  // ---------- Charge limit monitor ----------
  // Polls every 5 minutes. If the charge limit is set, the battery is on
  // AC power, and the battery percentage is above the limit while charging,
  // re-applies the limit to force the EC to stop charging.
  Timer {
    id: chargeLimitMonitorTimer
    interval: 300000                      // 5 minutes
    running: root.chargeThresholdActive && root.chargeLimit > 0
    repeat: true
    triggeredOnStart: false
    onTriggered: root.monitorChargeLimit()
  }

  function monitorChargeLimit() {
    if (!root.chargeThresholdActive || root.chargeLimit <= 0) return
    if (!root.batteryInfo.percentage) return
    var pct = parseInt(String(root.batteryInfo.percentage), 10)
    if (pct > root.chargeLimit && !root.discharging && root.batteryInfo.rate > 0) {
      applyChargeLimit(root.chargeLimit)
    }
  }
  readonly property var chargeLimitOptions: [
    { percent: 50, label: "50%" },
    { percent: 80, label: "80%" },
    { percent: 100, label: "Off" }
  ]

  property int brightness: 0
  property bool brightnessAvailable: false
  property real wheelAccumulator: 0
  property bool sliderDragging: false
  property bool showOsdOnNextSet: false
  readonly property string brightnessScript: Quickshell.env("HOME") + "/.config/omarchy/plugins/gerygerger.power/brightness.sh"
  readonly property bool showPercentage: setting("showPercentage", false) === true
  // Idle config — mirrors ~/.config/omarchy/shell.json "idle" block.
  readonly property string readIdleScript: Quickshell.env("HOME") + "/.config/omarchy/plugins/gerygerger.power/read-idle-config.sh"
  readonly property string updateIdleScript: Quickshell.env("HOME") + "/.config/omarchy/plugins/gerygerger.power/update-idle-config.sh"
  property int idleScreensaver: 150   // seconds; 0 disables the screensaver
  property int idleLock: 300          // seconds; 0 disables locking
  // With the percentage shown the button paints a text block wider than an
  // icon, so the open-panel mark takes the painted width instead of the
  // icon-sized fraction of the slot the fallback assumes.
  readonly property real openPanelIndicatorWidth: showPercentage && !button.vertical ? button.glyphPaintedWidth : 0
  readonly property bool batteryPresent: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent)
  }

  function upowerStates() {
    return {
      Charging: UPowerDeviceState.Charging,
      Discharging: UPowerDeviceState.Discharging,
      FullyCharged: UPowerDeviceState.FullyCharged,
      PendingCharge: UPowerDeviceState.PendingCharge
    }
  }

  function selectProfileByDelta(delta) {
    profileIndex = Model.selectProfileIndex(profileIndex, delta, profiles)
  }

  function activateSelectedProfile() {
    if (profileIndex < 0 || profileIndex >= profiles.length) return
    setProfile(profiles[profileIndex])
  }

  function batteryIcon() {
    var device = UPower.displayDevice
    return Model.batteryIcon(device, root.discharging, upowerStates())
  }

  function modeLabel() {
    var device = UPower.displayDevice
    return Model.modeLabel(device, root.discharging, upowerStates())
  }

  function profileIcon(name) {
    return Model.profileIcon(name)
  }

  readonly property bool fullyCharged: {
    var device = UPower.displayDevice
    return device && device.isPresent && device.state === UPowerDeviceState.FullyCharged && !root.chargeThresholdActive
  }
  readonly property bool discharging: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent && UPower.onBattery)
  }
  readonly property bool chargeThresholdActive: {
    var device = UPower.displayDevice
    return Model.chargeThresholdActive(device, root.discharging, upowerStates())
  }
  readonly property bool batteryFull: fullyCharged || (!root.discharging && batteryFraction >= 1)
  readonly property bool batteryFlowIdle: batteryFull || chargeThresholdActive

  // 0..1 charge level, used by the visual progress bar.
  readonly property real batteryFraction: {
    var d = UPower.displayDevice
    return Model.batteryFraction(d)
  }

  readonly property bool charging: {
    var d = UPower.displayDevice
    return d && d.isPresent && !UPower.onBattery && !root.batteryFlowIdle
  }

  readonly property color batteryFillColor: {
    return root.bar ? root.bar.foreground : Color.foreground
  }

  // Cute agent-flavored phrases shown in the hero status line, rotated on a
  // timer so the panel feels alive when current is flowing (either direction).
  readonly property var chargingPhrases: [
    "Pumping power",
    "Injecting electrons",
    "Pouring juice",
    "Amassing watts",
    "Hoarding joules",
    "Sucking volts",
    "Topping reserves",
    "Soaking amps",
    "Inhaling kilowatts"
  ]
  readonly property var onBatteryPhrases: [
    "Slurping power",
    "Spending joules",
    "Draining watts",
    "Burning electrons",
    "Sipping juice",
    "Spending coulombs",
    "Bleeding amps",
    "Guzzling volts",
    "Munching reserves"
  ]
  property int phraseIndex: 0

  // Whichever list is "active" given the current power state.
  readonly property var activePhrases: {
    if (fullyCharged) return []
    if (charging) return chargingPhrases
    if (discharging) return onBatteryPhrases
    return []
  }
  readonly property bool rotatingPhrases: activePhrases.length > 0

  readonly property string heroStatusText: {
    if (fullyCharged) return "Fully charged"
    if (rotatingPhrases) return activePhrases[phraseIndex % activePhrases.length]
    return modeLabel()
  }

  function refresh() {
    if (!batteryPresent) return

    if (!batteryProc.running) batteryProc.running = true
    if (!profilesProc.running) profilesProc.running = true
    if (!systemProc.running) systemProc.running = true
    if (!brightnessGetProc.running) brightnessGetProc.running = true
    if (root.chargeLimit < 0 && !limitInfoProc.running) limitInfoProc.running = true
  }

  function updateKeyValue(raw, targetName) {
    var next = Model.parseKeyValue(raw)
    // Keep last known good data if a refresh briefly returns nothing — happens
    // around AC plug/unplug events. Avoids the section collapsing mid-transition.
    if (Object.keys(next).length === 0) return
    if (targetName === "battery") batteryInfo = next
    else systemInfo = next
  }

  function updateProfiles(raw) {
    var parsed = Model.parseProfiles(raw, profileIndex)
    // Same guard as battery: preserve the last known profile list across
    // transient empty payloads so the buttons don't blink out.
    if (parsed.profiles.length === 0) return
    profiles = parsed.profiles
    activeProfile = parsed.activeProfile
    profileIndex = parsed.profileIndex
    if (opened && !cursorActive) {
      var idx = profiles.indexOf(activeProfile)
      if (idx >= 0) profileIndex = idx
    }
  }

  function setProfile(profile) {
    if (!profile || actionProc.running) return
    actionProc.command = ["omarchy-powerprofiles-set", root.discharging ? "battery" : "ac", profile]
    actionProc.running = true
  }

  function applyChargeLimit(percent) {
    if (limitProc.running) return
    chargeLimit = percent
    // Apply via asusctl AND sync the kernel's charge_control_end_threshold
    // so both the ASUS EC and the kernel enforce the same limit.
    var bashCmd = "asusctl battery limit " + String(percent)
    for (var i = 0; i < 3; i++) {
      bashCmd += " && echo " + String(percent) + " > /sys/class/power_supply/BAT" + String(i) + "/charge_control_end_threshold 2>/dev/null || true"
    }
    limitProc.command = ["bash", "-c", bashCmd]
    limitProc.running = true
  }

  function parseChargeLimit(raw) {
    var match = String(raw || "").match(/(\d+)\s*%/)
    if (match) chargeLimit = parseInt(match[1], 10)
  }

  function verifyChargeLimit() {
    // Read back the kernel's charge_control_end_threshold and compare
    // to what we just set. If they match, the limit is verified.
    if (chargeLimit <= 0) { chargeLimitVerified = false; return }
    var ec = parseInt(String(batteryInfo.threshold || "-1"), 10)
    chargeLimitVerified = (ec === chargeLimit)
  }

  function clampBrightness(value) {
    var n = Number(value)
    if (!isFinite(n)) return 15
    return Math.max(15, Math.min(100, Math.round(n)))
  }

  function brightnessName(percent) {
    var p = Math.round(percent)
    if (p >= 95) return "Sun blast"
    if (p >= 80) return "Solar flare"
    if (p >= 65) return "Golden hour"
    if (p >= 45) return "Even day"
    if (p >= 30) return "Soft glow"
    if (p >= 20) return "Lamp light"
    if (p >= 10) return "Candlelit"
    return "Night owl"
  }

  function setBrightness(value, withOsd) {
    var percent = clampBrightness(value)
    root.brightness = percent
    if (root.autoDimActive) root.autoDimFrom = percent
    if (brightnessSetProc.running) return
    root.showOsdOnNextSet = withOsd === true
    brightnessSetProc.command = ["bash", root.brightnessScript, "", "set", String(percent)]
    brightnessSetProc.running = true
  }

  function toggleAutoDim() {
    root.autoDimEnabled = !root.autoDimEnabled
    root.settings = Object.assign({}, root.settings, { autoDimEnabled: root.autoDimEnabled })
    if (!root.autoDimEnabled && root.autoDimActive) {
      root.setBrightness(root.autoDimFrom, false)
      root.autoDimActive = false
    }
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  function showBrightnessOsd(percent) {
    if (!root.bar || !root.bar.shell) return
    root.bar.shell.summon("omarchy.osd", JSON.stringify({ icon: "brightness", value: percent }))
  }

  function togglePercentage() {
    root.settings = Object.assign({}, root.settings, { showPercentage: !root.showPercentage })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  // ---------- Idle config helpers ----------
  property var idleConfig: ({ screensaver: 150, lock: 300 })

  function setIdleScreensaver(seconds) {
    root.idleScreensaver = seconds
    root.settings = Object.assign({}, root.settings, {
      idleScreensaver: seconds,
      idleLock: root.idleLock
    })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
    idleWriteProc.command = ["bash", "-c", root.updateIdleScript + " screensaver " + String(seconds)]
    idleWriteProc.running = true
  }

  function setIdleLock(seconds) {
    root.idleLock = seconds
    root.settings = Object.assign({}, root.settings, {
      idleScreensaver: root.idleScreensaver,
      idleLock: seconds
    })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
    idleWriteProc.command = ["bash", "-c", root.updateIdleScript + " lock " + String(seconds)]
    idleWriteProc.running = true
  }

  IpcHandler {
    target: "omarchy.power"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function togglePercentage() { root.togglePercentage() }
  }

  onOpenedChanged: {
    if (opened) {
      if (!batteryPresent) {
        close()
        return
      }

      refresh()
      var idx = profiles.indexOf(activeProfile)
      profileIndex = idx >= 0 ? idx : 0
      cursorActive = false
      if (!idleConfigProc.running) idleConfigProc.running = true
    }
  }

  onBatteryPresentChanged: if (!batteryPresent) close()

  visible: batteryPresent
  implicitWidth: batteryPresent ? button.implicitWidth : 0
  implicitHeight: batteryPresent ? button.implicitHeight : 0

  Process {
    id: batteryProc
    command: ["omarchy-battery-status", "--shell"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "battery") }
  }

  Process {
    id: profilesProc
    command: ["omarchy-powerprofiles-list", "--active-state"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateProfiles(text) }
  }

  Process {
    id: systemProc
    command: ["omarchy-system-stats"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "system") }
  }

  Process {
    id: actionProc
    onExited: root.refresh()
  }

  Process {
    id: limitInfoProc
    command: ["asusctl", "battery", "info"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: { root.parseChargeLimit(text); root.verifyChargeLimit() } }
  }

  Process {
    id: limitProc
    onExited: {
      root.refresh()
      if (!limitInfoProc.running) limitInfoProc.running = true
    }
  }

  Process {
    id: brightnessGetProc
    command: ["bash", root.brightnessScript, "", "get"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var value = parseInt(String(text || "").trim(), 10)
        if (isFinite(value) && value >= 0 && value <= 100) {
          if (!root.sliderDragging) root.brightness = value
          root.brightnessAvailable = true
        } else {
          root.brightnessAvailable = false
        }
      }
    }
  }

  Process {
    id: idleProc
    command: ["bash", root.idleCheckScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var idleSecs = parseInt(String(text || "").trim(), 10)
        if (!isFinite(idleSecs) || idleSecs < 0) idleSecs = 0
        var threshold = root.autoDimThreshold
        if (threshold <= 0) return  // "Off": never auto-dim
        if (idleSecs >= threshold && !root.autoDimActive) {
          root.autoDimFrom = root.brightness
          root.setBrightness(root.autoDimTarget, false)
          root.autoDimActive = true
        } else if (idleSecs < threshold && root.autoDimActive) {
          root.autoDimActive = false
          root.setBrightness(root.autoDimFrom, false)
        }
      }
    }
  }

  Process {
    id: brightnessSetProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var value = parseInt(String(text || "").trim(), 10)
        if (isFinite(value) && value >= 0 && value <= 100 && !root.sliderDragging)
          root.brightness = value
      }
    }
    onRunningChanged: if (!running && root.showOsdOnNextSet) {
        root.showOsdOnNextSet = false
        root.showBrightnessOsd(root.brightness)
      }
  }

  // ---------- Idle config reader/writer ----------
  Process {
    id: idleConfigProc
    command: ["bash", "-c", root.readIdleScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(String(text || "{}"))
          if (data.screensaver !== undefined) root.idleScreensaver = data.screensaver
          if (data.lock !== undefined) root.idleLock = data.lock
        } catch (e) {}
      }
    }
  }

  Process {
    id: idleWriteProc
    onExited: {
      // Re-read after write to keep state consistent
      if (!idleConfigProc.running) idleConfigProc.running = true
    }
  }

  Timer { interval: 5000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  // Rotate the status phrase while the panel is open and we're in a
  // rotating state (charging or on battery). The text swap is wrapped in a
  // fade so the changeover reads as one organism rather than a hard cut.
  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && root.rotatingPhrases
    repeat: true
    triggeredOnStart: false
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: {
        var n = root.activePhrases.length
        if (n > 0) root.phraseIndex = (root.phraseIndex + 1) % n
      }
    }
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  // If we leave a rotating state mid-swap, halt the animation and snap back
  // to full opacity so "FULLY CHARGED" is legible immediately rather than
  // appearing dimmed.
  Connections {
    target: root
    function onRotatingPhrasesChanged() {
      if (!root.rotatingPhrases) {
        phraseSwap.stop()
        heroStatus.opacity = 1.0
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.showPercentage && !vertical
      ? Math.round(root.batteryFraction * 100) + "% " + root.batteryIcon()
      : root.batteryIcon()
    slotSize: Style.bar.iconSlot * (root.showPercentage && !vertical ? 2 : 1)
    tooltipText: ""
    onPressed: function(b) {
      if (!root.batteryPresent) return
      if (b === Qt.RightButton) root.togglePercentage()
      else root.toggle()
    }
    onWheelMoved: function(delta) {
      if (!root.brightnessAvailable) return
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      root.setBrightness(root.brightness + wheel.steps * 5, true)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.batteryPresent
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (brightnessSlider._hot && root.brightnessAvailable) {
          if (dx !== 0) root.setBrightness(root.brightness + dx * 5, true)
          return
        }
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dx !== 0) root.selectProfileByDelta(dx)
        else if (dy !== 0) root.selectProfileByDelta(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateSelectedProfile()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: battery icon · title/status · percentage ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroPercent.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.batteryIcon()
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 200 } }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroPercent.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Asus Battery & Display"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              id: heroStatus
              textFormat: Text.PlainText
              text: "Control by Gerygerger"
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Text {
            id: heroPercent
            textFormat: Text.PlainText
            text: root.batteryInfo.percentage || "—"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 200 } }
          }
        }

        // ---------- Battery progress bar ----------
        Item {
          width: parent.width
          implicitHeight: Style.space(8)

          Rectangle {
            id: barTrack
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
          }

          Rectangle {
            id: barFill
            anchors.left: barTrack.left
            anchors.verticalCenter: barTrack.verticalCenter
            height: barTrack.height
            radius: barTrack.radius
            color: root.batteryFillColor
            width: Math.max(barTrack.height, barTrack.width * root.batteryFraction)

            Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 220 } }

            // Subtle pulse while charging — visible signal that energy is flowing in.
            SequentialAnimation on opacity {
              running: root.charging && !root.fullyCharged && root.opened
              loops: Animation.Infinite
              alwaysRunToEnd: true
              NumberAnimation { from: 1.0; to: 0.55; duration: 950; easing.type: Easing.InOutSine }
              NumberAnimation { from: 0.55; to: 1.0; duration: 950; easing.type: Easing.InOutSine }
            }
          }
        }

        // ---------- Stats ----------
        // Visibility is intentionally only gated by "we've ever loaded data" so
        // the section never collapses mid-transition. fullyCharged is *not* part
        // of the condition: UPower briefly reports FullyCharged on plug-in when
        // the battery sits above the charge-control start threshold, and we
        // refuse to flicker the whole panel for that ~1s window.
        Row {
          visible: root.batteryInfo.percentage !== undefined
          width: parent.width
          spacing: Style.space(20)

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair { label: "Battery size"; value: root.batteryInfo.size || "" }
            InfoPair { label: "Charge cycles"; value: root.batteryInfo.cycles || "—" }
          }

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair {
              label: root.chargeThresholdActive ? "Charge limit" : (root.discharging ? "Time left" : "Time to full")
              value: root.chargeThresholdActive ? (root.chargeLimit > 0 ? root.chargeLimit + "%" : (root.batteryInfo.threshold || "-")) : (root.batteryFlowIdle ? "-" : (root.batteryInfo.time || "—"))
            }
            InfoPair {
              label: root.chargeThresholdActive ? "Battery state" : (root.discharging ? "Discharging" : "Charging")
              value: root.chargeThresholdActive ? (root.chargeLimitVerified ? "Holding ✓" : "Holding ⚠") : (root.batteryFull ? "-" : (root.batteryInfo.rate || ""))
            }
          }
        }

        // ---------- Brightness ----------
        PanelSeparator {
          foreground: root.bar.foreground
        }

        Column {
          visible: root.brightnessAvailable
          width: parent.width
          spacing: Style.space(6)

          Item {
            width: parent.width
            implicitHeight: Math.max(brightnessHeader.implicitHeight, brightnessPercent.implicitHeight)

            PanelSectionHeader {
              id: brightnessHeader
              text: "BRIGHTNESS"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Text {
              id: brightnessPercent
              textFormat: Text.PlainText
              text: Math.round(brightnessSlider.dragging ? brightnessSlider.liveValue : root.brightness) + "%"
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          CursorSurface {
            id: brightnessRow
            width: parent.width
            height: brightnessSlider.implicitHeight + Style.spacing.controlGap
            foreground: root.bar.foreground
            outline: true
            hasCursor: brightnessSlider._hot

            PanelSlider {
              id: brightnessSlider
              bar: root.bar
              anchors.fill: parent
              anchors.leftMargin: Style.spacing.sm
              anchors.rightMargin: Style.spacing.sm
              minimum: 15
              maximum: 100
              step: 1
              integer: true
              value: root.brightness
              onMoved: function(value) {
                root.sliderDragging = true
                root.brightness = Math.round(value)
              }
              onReleased: function(value) {
                root.sliderDragging = false
                root.setBrightness(value, false)
              }
            }
          }

          // ---------- Auto-dim toggle + editor ----------
          Row {
            visible: root.brightnessAvailable
            width: parent.width
            spacing: Style.space(8)
            y: brightnessRow.implicitHeight + Style.space(4)

            Text {
              id: autoDimLabel
              text: "Auto-dim"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              opacity: root.autoDimEnabled ? 1.0 : 0.35
              verticalAlignment: Text.AlignVerticalCenter
              Behavior on opacity { NumberAnimation { duration: 150 } }
            }

            // Click to toggle on/off
            Text {
              property int chipWidth: 56
              x: 0
              color: root.autoDimEnabled ? root.bar.foreground : Qt.rgba(0.4, 0.4, 0.4, 0.5)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: root.autoDimEnabled
              text: root.autoDimEnabled ? (root.autoDimActive ? "ON ●" : "ON  ") : "OFF"
              Behavior on color { ColorAnimation { duration: 150 } }
              Behavior on text { NumberAnimation { duration: 150 } }

              MouseArea {
                anchors.fill: parent
                onClicked: root.toggleAutoDim()
              }
            }

            // Threshold editor (minutes + Off)
            Row {
              visible: root.autoDimEnabled
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: [
                  { label: "5m",  seconds: 300  },
                  { label: "15m", seconds: 900  },
                  { label: "30m", seconds: 1800 },
                  { label: "1 Hr", seconds: 3600 },
                  { label: "Off",  seconds: 0    }
                ]
                Text {
                  required property var modelData
                  text: modelData.label
                  color: root.autoDimThreshold === modelData.seconds
                    ? root.bar.foreground
                    : Qt.rgba(0.45, 0.45, 0.45, 0.6)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: root.autoDimThreshold === modelData.seconds
                  verticalAlignment: Text.AlignVerticalCenter
                  Behavior on color { ColorAnimation { duration: 120 } }

                  MouseArea {
                    anchors.fill: parent
                    onClicked: {
                      root.autoDimThreshold = modelData.seconds
                      root.settings = Object.assign({}, root.settings, {
                        autoDimThreshold: modelData.seconds,
                        autoDimTarget: root.autoDimTarget,
                        autoDimEnabled: root.autoDimEnabled
                      })
                      if (root.bar && root.bar.shell)
                        root.bar.shell.updateEntryInline(root.moduleName, root.settings)
                    }
                  }
                }
              }
            }

            // Target editor (percent)
            Row {
              visible: root.autoDimEnabled
              spacing: Style.space(2)
              height: 20

              Text {
                text: "→"
                color: Qt.rgba(0.55, 0.55, 0.55, 1.0)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                verticalAlignment: Text.AlignVerticalCenter
              }

              Text {
                text: root.autoDimTarget + "%"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                verticalAlignment: Text.AlignVerticalCenter
              }

              Text {
                text: "−"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                verticalAlignment: Text.AlignVerticalCenter

                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    var v = root.autoDimTarget - 5
                    if (v < 5) v = 5
                    root.autoDimTarget = v
                    root.settings = Object.assign({}, root.settings, {
                      autoDimThreshold: root.autoDimThreshold,
                      autoDimTarget: v,
                      autoDimEnabled: root.autoDimEnabled
                    })
                    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
                  }
                }
              }

              Text {
                text: "+"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                verticalAlignment: Text.AlignVerticalCenter

                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    var v = root.autoDimTarget + 5
                    if (v > 100) v = 100
                    root.autoDimTarget = v
                    root.settings = Object.assign({}, root.settings, {
                      autoDimThreshold: root.autoDimThreshold,
                      autoDimTarget: v,
                      autoDimEnabled: root.autoDimEnabled
                    })
                    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
                  }
                }
              }
            }
          }
        }

        // ---------- Power profile picker ----------
        PanelSeparator {
          foreground: root.bar.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "POWER PROFILE"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            id: profileRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: root.profiles.length > 0
              ? (width - spacing * (root.profiles.length - 1)) / root.profiles.length
              : 0

            Repeater {
              model: root.profiles
              Button {
                required property var modelData
                required property int index
                width: profileRow.cellWidth
                iconText: root.profileIcon(String(modelData))
                iconSize: Style.font.title
                text: String(modelData).charAt(0).toUpperCase() + String(modelData).slice(1)
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: root.activeProfile === modelData
                hasCursor: root.cursorActive && root.profileIndex === index
                onClicked: root.setProfile(modelData)
                onHovered: function(h) {
                  if (h) {
                    root.cursorActive = true
                    root.profileIndex = index
                  }
                }
              }
            }
          }
        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "CHARGE LIMIT"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            id: limitRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: root.chargeLimitOptions.length > 0
              ? (width - spacing * (root.chargeLimitOptions.length - 1)) / root.chargeLimitOptions.length
              : 0

            Repeater {
              model: root.chargeLimitOptions
              Button {
                required property var modelData
                required property int index
                width: limitRow.cellWidth
                text: modelData.label
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: root.chargeLimit === modelData.percent
                onClicked: root.applyChargeLimit(modelData.percent)
              }
            }
          }
        }

        // ---------- Idle config ----------
        PanelSeparator {
          foreground: root.bar.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "IDLE"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          // Screensaver timeout
          Row {
            width: parent.width
            spacing: Style.space(6)

            Text {
              text: "Screensaver"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              opacity: 0.7
              verticalAlignment: Text.AlignVerticalCenter
              width: parent.width * 0.28
            }

            Repeater {
              model: [
                { label: "5m",  seconds: 300  },
                { label: "15m", seconds: 900  },
                { label: "30m", seconds: 1800 },
                { label: "1 Hr", seconds: 3600 },
                { label: "Off",  seconds: 0    }
              ]
              Text {
                required property var modelData
                text: modelData.label
                color: root.idleScreensaver === modelData.seconds
                  ? root.bar.foreground
                  : Qt.rgba(0.45, 0.45, 0.45, 0.6)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: root.idleScreensaver === modelData.seconds
                verticalAlignment: Text.AlignVerticalCenter
                Behavior on color { ColorAnimation { duration: 120 } }

                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    root.idleScreensaver = modelData.seconds
                    root.settings = Object.assign({}, root.settings, {
                      idleScreensaver: modelData.seconds,
                      idleLock: root.idleLock
                    })
                    if (root.bar && root.bar.shell)
                      root.bar.shell.updateEntryInline(root.moduleName, root.settings)
                    idleWriteProc.command = ["bash", "-c", root.updateIdleScript + " screensaver " + String(modelData.seconds)]
                    idleWriteProc.running = true
                  }
                }
              }
            }
          }

          // Lock timeout
          Row {
            width: parent.width
            spacing: Style.space(6)

            Text {
              text: "Lock"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              opacity: 0.7
              verticalAlignment: Text.AlignVerticalCenter
              width: parent.width * 0.28
            }

            Repeater {
              model: [
                { label: "5m",  seconds: 300  },
                { label: "15m", seconds: 900  },
                { label: "30m", seconds: 1800 },
                { label: "1 Hr", seconds: 3600 },
                { label: "Off",  seconds: 0    }
              ]
              Text {
                required property var modelData
                text: modelData.label
                color: root.idleLock === modelData.seconds
                  ? root.bar.foreground
                  : Qt.rgba(0.45, 0.45, 0.45, 0.6)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: root.idleLock === modelData.seconds
                verticalAlignment: Text.AlignVerticalCenter
                Behavior on color { ColorAnimation { duration: 120 } }

                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    root.idleLock = modelData.seconds
                    root.settings = Object.assign({}, root.settings, {
                      idleScreensaver: root.idleScreensaver,
                      idleLock: modelData.seconds
                    })
                    if (root.bar && root.bar.shell)
                      root.bar.shell.updateEntryInline(root.moduleName, root.settings)
                    idleWriteProc.command = ["bash", "-c", root.updateIdleScript + " lock " + String(modelData.seconds)]
                    idleWriteProc.running = true
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    opacity: 0.6
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
