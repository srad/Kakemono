export function runFullyKioskCommand(cmd, win = window) {
  const fullyCommand = win.fully?.[cmd]

  if (typeof fullyCommand === "function") {
    fullyCommand.call(win.fully)
    return
  }

  if (cmd === "reloadPage") {
    win.location?.reload?.()
  }
}

export function bindFullyKioskEvents(win = window) {
  win.addEventListener("phx:fully_kiosk", ({ detail }) => {
    runFullyKioskCommand(detail?.cmd, win)
  })
}
