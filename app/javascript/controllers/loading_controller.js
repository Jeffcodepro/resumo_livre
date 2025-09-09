// app/javascript/controllers/loading_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { fallback: { type: Number, default: 15000 } } // ms

  connect() {
    this._busy = new Set()

    // Em qualquer navegação/render Turbo bem-sucedida, garantimos que tudo fique "idle"
    this._onTurboDone = () => this.resetAll()
    document.addEventListener("turbo:load", this._onTurboDone, { passive: true })
    document.addEventListener("turbo:frame-load", this._onTurboDone, { passive: true })
    document.addEventListener("turbo:before-render", this._onTurboDone, { passive: true })
    document.addEventListener("turbo:before-cache", this._onTurboDone, { passive: true })

    // Reanima animações quando a aba volta a ficar visível
    this._onVisibility = () => { if (document.visibilityState === "visible") this.kickAllSpinners() }
    document.addEventListener("visibilitychange", this._onVisibility, { passive: true })
  }

  disconnect() {
    document.removeEventListener("turbo:load", this._onTurboDone)
    document.removeEventListener("turbo:frame-load", this._onTurboDone)
    document.removeEventListener("turbo:before-render", this._onTurboDone)
    document.removeEventListener("turbo:before-cache", this._onTurboDone)
    document.removeEventListener("visibilitychange", this._onVisibility)
  }

  // ---- Eventos Turbo (mesma aba) ----
  turboSubmitStart(e) {
    const submitter = e?.detail?.formSubmission?.submitter || this.guessSubmitter(e?.target)
    if (submitter) {
      this.markNewTabIfNeeded(submitter)
      this.setBusy(submitter)
    }
  }

  turboSubmitEnd(e) {
    const submitter = e?.detail?.formSubmission?.submitter || this.guessSubmitter(e?.target)
    // Independente de sucesso/erro/redirect, desligamos.
    if (submitter) {
      this.setIdle(submitter)
    } else {
      // Sem referência? Desliga todos para não sobrar spinner preso.
      this.resetAll()
    }
  }

  // ---- Compat: nomes antigos/segundo controller ----
  onSubmit(e) { this.submit(e) }
  onLinkClick(e) { this.click(e) }

  // ---- Eventos padrão ----
  submit(e) {
    const el = e.submitter || this.guessSubmitter(e.currentTarget || e.target)
    if (el) {
      this.markNewTabIfNeeded(el)
      this.setBusy(el)
    }
  }

  click(e) {
    const el = e.currentTarget
    this.setBusy(el)
    this.markNewTabIfNeeded(el) // agenda fallback só se abrir nova aba
  }

  // ---- Helpers ----
  isNewTab(el) {
    if (!el) return false
    if (el.tagName === "A") return el.target === "_blank"
    const form = el.form || el.closest("form")
    return form && form.getAttribute("target") === "_blank"
  }
  isMarkedNewTab(el) { return el?.dataset?.newTab === "1" }
  markNewTabIfNeeded(el) {
    if (this.isNewTab(el)) {
      el.dataset.newTab = "1"
      this.scheduleFallback(el) // só nova aba
    }
  }
  guessSubmitter(from) {
    const root = from instanceof Element ? from : document
    return root?.querySelector?.('button[type="submit"]:not([disabled]), input[type="submit"]:not([disabled])')
  }
  messageFor(el) { return el?.dataset?.loadingText || "Aguarde…" }

  setBusy(el) {
    if (!el) return
    this._busy.add(el)

    el.setAttribute("aria-busy", "true")
    el.classList.add("disabled", "has-spinner")
    el.disabled = true

    const msg = this.messageFor(el)
    const label  = el.querySelector(".btn-label")
    let spinEl   = el.querySelector(".btn-spinner")

    if (spinEl || label) {
      if (!spinEl && label) {
        label.insertAdjacentHTML("afterbegin", `<i class="btn-spinner fa fa-spinner fa-spin me-2" aria-hidden="true"></i>`)
        spinEl = el.querySelector(".btn-spinner")
      }
      if (spinEl) spinEl.classList.add("fa-spinner", "fa-spin")
      if (label) {
        if (!label.dataset.originalText) label.dataset.originalText = label.textContent
        label.textContent = msg
      }
    } else {
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
    this.kickSpin(el)
  }

  setIdle(el) {
    if (!el) return
    this._busy.delete(el)

    el.removeAttribute("aria-busy")
    el.classList.remove("disabled", "has-spinner")
    el.disabled = false

    const spinEl = el.querySelector(".btn-spinner")
    const label  = el.querySelector(".btn-label")
    if (spinEl) spinEl.classList.remove("fa-spinner", "fa-spin")
    if (label?.dataset.originalText) label.textContent = label.dataset.originalText

    if (el.dataset.originalHtml)  { el.innerHTML = el.dataset.originalHtml; delete el.dataset.originalHtml }
    if (el.dataset.originalValue) { el.value     = el.dataset.originalValue; delete el.dataset.originalValue }

    if (el._resetTimer) { clearTimeout(el._resetTimer); el._resetTimer = null }
    delete el.dataset.newTab
  }

  resetAll() {
    // Desliga tudo que estiver marcado como ocupado
    this._busy.forEach((el) => this.setIdle(el))
    this._busy.clear()
  }

  kickSpin(el) {
    const parts = el.querySelectorAll(".btn-spinner, .spinner-border")
    parts.forEach((node) => {
      if (node.classList.contains("fa-spin")) {
        node.classList.remove("fa-spin"); void node.offsetWidth; node.classList.add("fa-spin")
      } else if (node.classList.contains("spinner-border")) {
        node.classList.remove("spinner-border"); void node.offsetWidth; node.classList.add("spinner-border")
      }
    })
  }
  kickAllSpinners() {
    document.querySelectorAll('[aria-busy="true"]').forEach((el) => this.kickSpin(el))
  }

  scheduleFallback(el) {
    if (!this.isMarkedNewTab(el)) return
    if (el._resetTimer) clearTimeout(el._resetTimer)
    el._resetTimer = setTimeout(() => this.setIdle(el), this.fallbackValue)
  }
}
