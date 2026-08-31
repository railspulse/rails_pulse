import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source"]
  static values = {
    label: { type: String, default: "copy" },
    copiedLabel: { type: String, default: "copied!" },
    errorLabel: { type: String, default: "copy failed" },
    resetDelay: { type: Number, default: 1500 }
  }

  disconnect() {
    if (this.resetTimeout) clearTimeout(this.resetTimeout)
  }

  async copy(event) {
    const button = event.currentTarget
    const text = this.hasSourceTarget ? this.sourceTarget.textContent : ""

    try {
      await this.write(text)
      this.flash(button, this.copiedLabelValue)
    } catch {
      this.flash(button, this.errorLabelValue)
    }
  }

  // navigator.clipboard is undefined on insecure origins, which is where a
  // mounted dashboard often lives (http://staging.internal). Fall back to the
  // legacy execCommand path there rather than silently doing nothing.
  async write(text) {
    if (navigator.clipboard && window.isSecureContext) {
      return navigator.clipboard.writeText(text)
    }

    const textarea = document.createElement("textarea")
    textarea.value = text
    textarea.setAttribute("readonly", "")
    textarea.style.position = "fixed"
    textarea.style.opacity = "0"
    document.body.appendChild(textarea)
    textarea.select()

    try {
      if (!document.execCommand("copy")) throw new Error("execCommand copy failed")
    } finally {
      document.body.removeChild(textarea)
    }
  }

  flash(button, message) {
    button.textContent = message
    if (this.resetTimeout) clearTimeout(this.resetTimeout)
    this.resetTimeout = setTimeout(() => {
      button.textContent = this.labelValue
    }, this.resetDelayValue)
  }
}
