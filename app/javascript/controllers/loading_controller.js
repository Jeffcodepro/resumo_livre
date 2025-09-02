import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { fallback: { type: Number, default: 15000 } } // ms

  connect() {
    this._onFocus = () => this.resetAll()
    window.addEventListener("focus", this._onFocus, { passive: true })
  }
  disconnect() {
    window.removeEventListener("focus", this._onFocus)
  }

  // ---- Eventos Turbo (mesma aba) ----
  turboSubmitStart(e) {
    const submitter = e.detail?.formSubmission?.submitter
    if (submitter) this.setBusy(submitter)
  }
  turboSubmitEnd(e) {
    const submitter = e.detail?.formSubmission?.submitter
    if (submitter && !this.isNewTab(submitter)) this.setIdle(submitter)
  }

  // ---- Compat: nomes antigos/segundo controller ----
  onSubmit(e) { this.submit(e) }
  onLinkClick(e) { this.click(e) }

  // ---- Eventos padrão ----
  submit(e) {
    const submitter = e.submitter
    if (submitter) this.setBusy(submitter)
  }
  click(e) {
    const el = e.currentTarget
    this.setBusy(el)
    if (this.isNewTab(el)) this.scheduleFallback(el)
  }

  // ---- Helpers ----
  isNewTab(el) {
    if (el.tagName === "A") return el.target === "_blank"
    const form = el.form || el.closest("form")
    return form && form.getAttribute("target") === "_blank"
  }

  messageFor(el) {
    // prioridade: data-loading-text do acionador, senão "Aguarde…"
    return el?.dataset?.loadingText || "Aguarde…"
  }

  setBusy(el) {
    if (!el) return
    el.setAttribute("aria-busy", "true")
    el.classList.add("disabled")
    el.disabled = true

    const msg = this.messageFor(el)
    const label = el.querySelector(".btn-label")
    const spinEl = el.querySelector(".btn-spinner")

    // MODO 1: já existe markup (.btn-spinner / .btn-label)
    if (spinEl || label) {
      if (spinEl) spinEl.classList.add("fa-spinner", "fa-spin")
      if (label) {
        if (!label.dataset.originalText) label.dataset.originalText = label.textContent
        label.textContent = msg
      }
    } else {
      // MODO 2: injetar conteúdo (estilo do seu segundo controller)
      if (el.tagName === "BUTTON") {
        if (!el.dataset.originalHtml) el.dataset.originalHtml = el.innerHTML
        if (el.dataset.spin !== "off") {
          el.innerHTML = `
            <span class="spinner-border spinner-border-sm" role="status" aria-hidden="true"></span>
            <span class="ms-2">${msg}</span>
          `
        } else {
          el.textContent = msg
        }
      } else if (el.tagName === "INPUT") {
        if (!el.dataset.originalValue) el.dataset.originalValue = el.value
        el.value = msg
      }
    }
  }

  setIdle(el) {
    if (!el) return
    el.removeAttribute("aria-busy")
    el.classList.remove("disabled")
    el.disabled = false

    const spinEl = el.querySelector(".btn-spinner")
    const label = el.querySelector(".btn-label")

    if (spinEl) spinEl.classList.remove("fa-spinner", "fa-spin")
    if (label?.dataset.originalText) label.textContent = label.dataset.originalText

    // se usamos MODO 2 (injeção), restaura:
    if (el.dataset.originalHtml) { el.innerHTML = el.dataset.originalHtml; delete el.dataset.originalHtml }
    if (el.dataset.originalValue) { el.value = el.dataset.originalValue; delete el.dataset.originalValue }

    if (el._resetTimer) { clearTimeout(el._resetTimer); el._resetTimer = null }
  }

  scheduleFallback(el) {
    if (el._resetTimer) clearTimeout(el._resetTimer)
    el._resetTimer = setTimeout(() => this.setIdle(el), this.fallbackValue)
  }

  resetAll() {
    document.querySelectorAll('.has-spinner[aria-busy="true"]').forEach((el) => this.setIdle(el))
  }
}
