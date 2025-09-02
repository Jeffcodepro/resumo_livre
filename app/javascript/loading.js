// app/javascript/loading.js
(function () {
  const html = document.documentElement;
  const $overlay = () => document.getElementById("loading-overlay");
  const $msg = () => document.getElementById("loading-message");

  function showOverlay(text) {
    if ($msg() && text) $msg().textContent = text;
    html.classList.add("is-loading");
    if ($overlay()) $overlay().style.display = "flex";
  }

  function hideOverlay() {
    html.classList.remove("is-loading");
    if ($overlay()) $overlay().style.display = "none";
  }

  function setBusyVisual(el, text) {
    // Salva o original p/ um possível restore futuro
    if (!el.dataset._busyApplied) {
      if (el.tagName === "BUTTON") {
        el.dataset._originalHtml = el.innerHTML;
      } else if (el.tagName === "INPUT") {
        el.dataset._originalValue = el.value;
      }
      el.dataset._busyApplied = "1";
    }

    // Aplica visual de busy conforme o tipo
    if (el.tagName === "BUTTON") {
      el.innerHTML =
        '<span class="spinner-border spinner-border-sm" role="status" aria-hidden="true"></span>' +
        `<span class="ms-2">${text}</span>`;
    } else if (el.tagName === "INPUT") {
      // input não aceita HTML — mostramos a msg no value
      el.value = text;
    }
    el.setAttribute("aria-busy", "true");
    el.disabled = true;
    el.classList.add("disabled");
  }

  function disableAllButtons(container, clickedBtn) {
    container.querySelectorAll('button, input[type="submit"], a.btn').forEach((el) => {
      // Deixa todos desabilitados
      el.disabled = true;
      el.classList.add("disabled");
      el.setAttribute("aria-disabled", "true");

      // Para links, previne cliques adicionais
      if (el.tagName === "A") {
        el.addEventListener("click", (ev) => ev.preventDefault(), { once: true });
      }
    });

    // No botão que disparou, mostra msg “bonita”
    if (clickedBtn) {
      const text =
        clickedBtn.dataset.loadingText ||
        container.dataset.loadingText ||
        "Processando…";
      setBusyVisual(clickedBtn, text);
    }
  }

  // --- Submit de forms com data-loading="true"
  document.addEventListener(
    "submit",
    (e) => {
      const form = e.target.closest("form");
      if (!form || form.dataset.loading !== "true") return;

      const submitter = e.submitter || document.activeElement;
      const text =
        (submitter && submitter.dataset.loadingText) ||
        form.dataset.loadingText ||
        "Processando…";

      disableAllButtons(form, submitter);
      showOverlay(text);
    },
    true
  );

  // --- Clique em links com data-loading-link="true"
  document.addEventListener("click", (e) => {
    const a = e.target.closest("a[data-loading-link='true']");
    if (!a) return;

    const text = a.dataset.loadingText || "Processando…";
    const scope = a.closest("form, .container, body") || document.body;

    disableAllButtons(scope, a);
    showOverlay(text);
  });

  // Evita overlay preso ao voltar do cache
  window.addEventListener("pageshow", () => hideOverlay());
})();
