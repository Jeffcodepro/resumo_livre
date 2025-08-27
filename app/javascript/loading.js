// app/javascript/loading.js
document.addEventListener('DOMContentLoaded', () => {
  const showOverlay = () => document.documentElement.classList.add('is-loading');
  const hideOverlay = () => document.documentElement.classList.remove('is-loading');

  // Ativa para qualquer <form data-loading="true">
  document.body.addEventListener('submit', (e) => {
    const form = e.target.closest('form');
    if (!form) return;
    if (form.dataset.loading === 'true') {
      // Desabilita botões/submit do form
      form.querySelectorAll('button, input[type="submit"]').forEach((el) => {
        el.disabled = true;
        el.classList.add('disabled');
        // Spinner no botão (se não estiver explícito para não usar)
        if (el.dataset.spin !== 'off') {
          el.dataset.originalHtml = el.innerHTML;
          el.innerHTML = `
            <span class="spinner-border spinner-border-sm" role="status" aria-hidden="true"></span>
            <span class="ms-2">Aguarde…</span>
          `;
        }
      });

      // Mostra overlay global
      showOverlay();
    }
  });

  // Se o navegador restaurar a página do cache, garante overlay desligado
  window.addEventListener('pageshow', () => hideOverlay());
});
