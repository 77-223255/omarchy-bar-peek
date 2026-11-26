import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons as Commons
import qs.plugins.bar as Native

// Bar Peek: the stock Omarchy bar, popped out over the windows from whichever
// screen edge it sits on, without ever moving a window.
//
// It inherits the installed bar, so widgets, theme, popouts, the tray drawer,
// drag-to-rearrange and the bar-off state all stay Omarchy-owned. Only the
// placement of the bar's layer surface changes:
//
//   * The bar keeps its hidden state, so the host keeps ExclusionMode.Ignore and
//     windows own the whole screen. Revealing is a margin animation, never a
//     remap, so nothing is re-tiled on any edge and the first frame is already
//     in place.
//   * A bar that is shown with the hotkey is drawn over the windows too,
//     unless `reserveSpace` is turned on.
//   * A trigger strip on the bar's own edge catches the pointer and slides the
//     bar in; it slides out shortly after the pointer leaves.
Native.Bar {
  id: root

  // ---- tuning -------------------------------------------------------------

  // How long the pointer may leave the bar before it hides again.
  property int hideDelayMs: 40
  // Slide in and out duration. Short on purpose: the reveal should read as a
  // pop, not as a journey.
  property int slideMs: 80
  // Thickness of the edge strip that catches the pointer.
  property int triggerThickness: 2
  // false: the bar never reserves desktop space, so windows never move.
  // true: a bar shown with the hotkey reserves space like the stock bar.
  property bool reserveSpace: false
  // Draw the revealed bar above fullscreen windows as well.
  property bool aboveFullscreen: true

  // ---- derived ------------------------------------------------------------

  readonly property bool verticalEdge: position === "left" || position === "right"
  readonly property string marginName: position
  readonly property int thickness: Math.max(1, triggerThickness)

  // ---- host bar windows ---------------------------------------------------

  // BarPanel is an inline component of the host bar. Its Variants expose the
  // per-screen windows without copying the bar or reaching into the shell host.
  property var panelVariants: null
  readonly property var barWindows: panelVariants ? panelVariants.instances : []
  readonly property bool attached: barWindows.length > 0
  property int discoveryAttempts: 0
  property bool gaveUp: false

  function isBarWindow(candidate) {
    // Grouped properties such as `margins` or the attached `WlrLayershell` are
    // not visible to the `in` operator, so only the plain ones are tested here;
    // the overriding bindings below address the groups by name.
    return !!candidate && "screen" in candidate && "contentItem" in candidate
  }

  function isPanelVariants(candidate) {
    if (!candidate || !("instances" in candidate)) return false
    const list = candidate.instances
    if (!list || typeof list.length !== "number") return false
    for (let index = 0; index < list.length; index += 1)
      if (root.isBarWindow(list[index])) return true
    return false
  }

  function findBarWindows() {
    for (const child of root.data) {
      if (child === peek) continue
      if (!root.isPanelVariants(child)) continue
      root.panelVariants = child
      return true
    }
    return false
  }

  Component.onCompleted: Qt.callLater(root.findBarWindows)

  Connections {
    target: Quickshell
    function onScreensChanged() { Qt.callLater(root.findBarWindows) }
  }

  // The host builds its bar asynchronously after this plugin loads, and a
  // monitor hotplug rebuilds it. Retry for a few seconds, then fail safe: a bar
  // parked off-screen with no reveal attached would leave the user stranded.
  Timer {
    id: discovery
    interval: 400
    repeat: true
    running: !root.attached && !root.gaveUp
    onTriggered: {
      root.discoveryAttempts += 1
      if (root.findBarWindows() || root.discoveryAttempts < 12) return
      root.gaveUp = true
      discovery.stop()
      console.warn("bar-peek: no bar windows found; leaving the bar visible")
      if (root.barHidden) Commons.Util.execDetached("omarchy toggle bar off")
    }
  }

  IpcHandler {
    target: "bar-peek"
    function status(): string {
      return JSON.stringify({
        position: root.position, hidden: root.barHidden,
        attached: root.attached, gaveUp: root.gaveUp,
        reserveSpace: root.reserveSpace, screens: peek.instances.map(peeked => ({
          name: peeked.window && peeked.window.screen ? peeked.window.screen.name : "",
          revealed: peeked.revealed, held: peeked.held, offset: peeked.offset,
          exclusion: peeked.window ? peeked.window.exclusionMode : -1,
          hover: peeked.hoverState
        }))
      })
    }
  }

  // ---- per screen ---------------------------------------------------------

  Variants {
    id: peek
    model: root.barWindows

    delegate: Component {
      Item {
        id: screenPeek

        required property var modelData
        readonly property var window: modelData

        // Attach only once the host window is fully constructed, so the
        // overriding bindings land on settled properties.
        property bool ready: false
        Component.onCompleted: Qt.callLater(() => ready = true)

        // The bar is parked until the pointer asks for it.
        property bool revealed: false

        // What the regression check reads. `bar` is the native hover state, the
        // other two belong to the trigger strip.
        readonly property var hoverState: ({
          bar: barHover.hovered,
          edge: edgeHover.hovered,
          catching: strip.catching
        })

        // Hold the bar open while it is being used: pointer on the bar, pointer
        // still on the trigger strip, an open popout, or a widget being dragged
        // around the bar.
        readonly property bool held: barHover.hovered
          || (strip.catching && edgeHover.hovered)
          || (root.activePopout !== null && root.targetBelongsToWindow(root.activePopout, window))
          || root.barDragWindow === window
          || root.barMoveWindow === window

        property real offset: root.barHidden && !revealed ? -root.barSize : 0

        Behavior on offset {
          NumberAnimation { duration: root.slideMs; easing.type: Easing.OutCubic }
        }

        Connections {
          target: root
          function onBarHiddenChanged() { screenPeek.revealed = false }
          function onPositionChanged() { screenPeek.revealed = false }
        }

        // Park and reveal: the whole slide is this one margin.
        Binding {
          target: screenPeek.window
          property: "margins." + root.marginName
          value: Math.round(screenPeek.offset)
          when: screenPeek.ready
          restoreMode: Binding.RestoreBindingOrValue
        }

        // Windows must never be pushed aside, whatever the bar's own state is.
        Binding {
          target: screenPeek.window
          property: "exclusionMode"
          value: ExclusionMode.Ignore
          when: screenPeek.ready && !root.reserveSpace
          restoreMode: Binding.RestoreBindingOrValue
        }

        // Above the windows, so a revealed bar is usable over a fullscreen app.
        Binding {
          target: screenPeek.window.WlrLayershell
          property: "layer"
          value: WlrLayer.Overlay
          when: screenPeek.ready && root.barHidden && root.aboveFullscreen
          restoreMode: Binding.RestoreBindingOrValue
        }

        // Observe hover from an ancestor: a sibling overlay would suppress the
        // bar's own hover handlers, the tray drawer's included.
        HoverHandler {
          id: barHover
          parent: screenPeek.window.contentItem
          blocking: false
          onHoveredChanged: if (hovered && root.barHidden) screenPeek.revealed = true
        }

        Timer {
          interval: root.hideDelayMs
          running: screenPeek.revealed && !screenPeek.held
          onTriggered: if (!screenPeek.held) screenPeek.revealed = false
        }

        // The strip along the bar's edge that catches the pointer.
        PanelWindow {
          id: strip

          readonly property bool catching: visible && (!screenPeek.revealed || !barHover.hovered)

          screen: screenPeek.window.screen
          visible: screenPeek.ready && root.barHidden && root.attached
          color: "transparent"
          implicitWidth: root.thickness
          implicitHeight: root.thickness
          anchors {
            top: root.position === "top" || root.verticalEdge
            bottom: root.position === "bottom" || root.verticalEdge
            left: root.position === "left" || !root.verticalEdge
            right: root.position === "right" || !root.verticalEdge
          }
          exclusionMode: ExclusionMode.Ignore
          // Hand input back once the pointer is on the bar, so a widget in the
          // bar's outermost pixels stays clickable. Clearing the mask at the end
          // of the animation alone may not deliver a new pointer enter.
          mask: Region {
            width: root.verticalEdge ? root.thickness : (strip.catching ? strip.width : 0)
            height: root.verticalEdge ? (strip.catching ? strip.height : 0) : root.thickness
          }
          WlrLayershell.namespace: "omarchy-bar-peek-edge"
          WlrLayershell.layer: WlrLayer.Overlay
          WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

          HoverHandler {
            id: edgeHover
            onHoveredChanged: if (hovered) screenPeek.revealed = true
          }
        }
      }
    }
  }
}
