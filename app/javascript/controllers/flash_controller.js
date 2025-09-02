import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { timeout: { type: Number, default: 5000 } }

  connect() {
    this.timer = setTimeout(() => this.close(), this.timeoutValue)
  }

  disconnect() {
    if (this.timer) clearTimeout(this.timer)
  }

  close() {
    // anima e remove ao final
    this.element.classList.add("flash-fade-out")
    this.element.addEventListener("animationend", () => {
      this.element.remove()
    }, { once: true })
  }
}
