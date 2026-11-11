// foamy-kit 0.9.0 a28be39b8b93167cebdaee410234eb50e625bd96621175c67fb8152649e38619 — do not edit; change foamy-kit and run sync
import QtQuick

// Epoch-aligned ticks avoid SystemClock's negative delays in the repeated
// local hour when daylight saving ends. Disabled clocks resume with fresh time.
Timer {
  id: root

  property bool enabled: true
  property int step: 60000
  property date date: new Date()

  function msUntilNextTick(nowMs) {
    return step - nowMs % step
  }

  function refresh() {
    stop()
    if (!enabled)
      return
    date = new Date()
    interval = msUntilNextTick(Date.now())
    start()
  }

  onEnabledChanged: refresh()
  onStepChanged: refresh()
  onTriggered: refresh()
  Component.onCompleted: refresh()
}
