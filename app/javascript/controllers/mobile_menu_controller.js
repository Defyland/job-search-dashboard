import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "button", "panel" ]

  connect() {
    this.open = false
    this.boundCloseFromOutside = this.closeFromOutside.bind(this)
    this.boundCloseFromEscape = this.closeFromEscape.bind(this)

    document.addEventListener("click", this.boundCloseFromOutside)
    document.addEventListener("keydown", this.boundCloseFromEscape)
    this.sync()
  }

  disconnect() {
    document.removeEventListener("click", this.boundCloseFromOutside)
    document.removeEventListener("keydown", this.boundCloseFromEscape)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()

    this.open = !this.open
    this.sync()
  }

  close() {
    this.open = false
    this.sync()
  }

  closeFromOutside(event) {
    if (this.element.contains(event.target)) return

    this.close()
  }

  closeFromEscape(event) {
    if (event.key !== "Escape") return

    this.close()
  }

  sync() {
    this.buttonTarget.setAttribute("aria-expanded", this.open ? "true" : "false")
    this.panelTarget.hidden = !this.open
  }
}
