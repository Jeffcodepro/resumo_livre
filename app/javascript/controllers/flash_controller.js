import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    timeout: { type: Number, default: 5000 },
    sticky:  { type: Boolean, default: false } // 👈 novo
  }

  connect() {
    // Só autodesaparece se NÃO for sticky e timeout > 0
    if (!this.stickyValue && this.timeoutValue > 0) {
      this.timer = setTimeout(() => this.close(), this.timeoutValue)
    }
  }

  disconnect() {
    if (this.timer) clearTimeout(this.timer)
  }

  close() {
    this.element.classList.add("flash-fade-out")
    this.element.addEventListener("animationend", () => {
      this.element.remove()
    }, { once: true })
  }
}
