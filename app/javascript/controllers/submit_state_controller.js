import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    defaultText: { type: String, default: "Processando..." }
  }

  connect() {
    this.submitting = false
    this.controlStates = []
    this.submitterState = null
    this.submitter = null
    this.disableFrame = null

    this.boundHandleSubmit = this.handleSubmit.bind(this)
    this.boundHandleTurboSubmitEnd = this.handleTurboSubmitEnd.bind(this)
    this.boundReset = this.reset.bind(this)

    this.element.addEventListener("submit", this.boundHandleSubmit)
    this.element.addEventListener("turbo:submit-end", this.boundHandleTurboSubmitEnd)
    document.addEventListener("turbo:before-cache", this.boundReset)
    window.addEventListener("pageshow", this.boundReset)

    this.reset()
  }

  disconnect() {
    this.element.removeEventListener("submit", this.boundHandleSubmit)
    this.element.removeEventListener("turbo:submit-end", this.boundHandleTurboSubmitEnd)
    document.removeEventListener("turbo:before-cache", this.boundReset)
    window.removeEventListener("pageshow", this.boundReset)

    this.reset()
  }

  handleSubmit(event) {
    if (this.submitting) {
      event.preventDefault()
      return
    }

    this.submitter = event.submitter || this.firstEnabledSubmitter()
    this.captureState()
    this.submitting = true
    this.applyPendingState()
  }

  handleTurboSubmitEnd(event) {
    if (event.target !== this.element || !this.submitting) return
    if (event.detail.success) return

    this.reset()
  }

  reset() {
    if (this.disableFrame) {
      cancelAnimationFrame(this.disableFrame)
      this.disableFrame = null
    }

    this.restoreControls()
    this.restoreSubmitter()

    this.element.removeAttribute("aria-busy")
    this.element.classList.remove("pointer-events-none")
    delete this.element.dataset.submitStatePending

    this.submitting = false
    this.controlStates = []
    this.submitterState = null
    this.submitter = null
  }

  captureState() {
    this.controlStates = this.formControls().map((element) => ({
      element,
      disabled: element.disabled
    }))

    if (!this.submitter) return

    this.submitterState = {
      element: this.submitter,
      disabled: this.submitter.disabled,
      content: this.submitterContent(this.submitter)
    }
  }

  applyPendingState() {
    this.element.dataset.submitStatePending = "true"
    this.element.setAttribute("aria-busy", "true")
    this.element.classList.add("pointer-events-none")

    if (this.submitter) {
      this.submitter.dataset.submitStateActive = "true"
      this.submitter.setAttribute("aria-disabled", "true")
      this.setSubmitterContent(this.submitter, this.loadingTextFor(this.submitter))
    }

    // Wait one frame so native/Turbo form serialization keeps the original
    // control state, including any submit button name/value pairs.
    this.disableFrame = requestAnimationFrame(() => {
      this.controlStates.forEach(({ element }) => {
        if (this.skipDisabling(element)) return

        element.disabled = true
        element.dataset.submitStateDisabled = "true"
      })
    })
  }

  restoreControls() {
    this.controlStates.forEach(({ element, disabled }) => {
      if (!element.isConnected) return

      element.disabled = disabled
      delete element.dataset.submitStateDisabled
    })
  }

  restoreSubmitter() {
    if (!this.submitterState) return
    if (!this.submitterState.element.isConnected) return

    this.submitterState.element.disabled = this.submitterState.disabled
    this.restoreSubmitterContent(this.submitterState.element, this.submitterState.content)
    this.submitterState.element.removeAttribute("aria-disabled")
    delete this.submitterState.element.dataset.submitStateActive
    delete this.submitterState.element.dataset.submitStateDisabled
  }

  formControls() {
    return Array.from(this.element.elements).filter((element) => element instanceof HTMLElement)
  }

  firstEnabledSubmitter() {
    return this.formControls().find((element) => this.isSubmitter(element) && !element.disabled)
  }

  isSubmitter(element) {
    if (element instanceof HTMLButtonElement) {
      return (element.type || "submit") === "submit"
    }

    if (!(element instanceof HTMLInputElement)) return false

    return [ "submit", "image" ].includes(element.type)
  }

  skipDisabling(element) {
    return element instanceof HTMLInputElement && element.type === "hidden"
  }

  loadingTextFor(element) {
    return element.dataset.submitStateLoadingText || this.defaultTextValue
  }

  submitterContent(element) {
    if (element instanceof HTMLInputElement) return { type: "value", value: element.value }

    return { type: "html", value: element.innerHTML }
  }

  setSubmitterContent(element, content) {
    if (element instanceof HTMLInputElement) {
      element.value = content
      return
    }

    element.textContent = content
  }

  restoreSubmitterContent(element, content) {
    if (content.type === "value") {
      element.value = content.value
      return
    }

    element.innerHTML = content.value
  }
}
