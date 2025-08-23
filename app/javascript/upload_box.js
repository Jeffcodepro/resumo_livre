// app/javascript/upload_box.js

function updateLabel(input) {
  const id = input.id; // "orders_file" ou "invoices_file"
  const nameEl = document.getElementById(`${id}_name`);
  const label  = document.querySelector(`label[for="${id}"]`);
  const file   = input.files && input.files[0];

  if (nameEl) nameEl.textContent = file ? file.name : "Nenhum arquivo selecionado";
  if (label)  label.classList.toggle("has-file", !!file);
}

function bindDnD(label, input) {
  if (!label || !input) return;

  ["dragenter","dragover"].forEach(ev =>
    label.addEventListener(ev, e => {
      e.preventDefault(); e.stopPropagation();
      label.classList.add("dragover");
    })
  );
  ["dragleave","dragend","drop"].forEach(ev =>
    label.addEventListener(ev, e => {
      e.preventDefault(); e.stopPropagation();
      label.classList.remove("dragover");
    })
  );
  label.addEventListener("drop", e => {
    const files = e.dataTransfer?.files;
    if (files && files.length > 0) {
      // Em drop, não dá pra setar FileList arbitrariamente em todos browsers.
      // Truque simples: foca o input e dispara o click pra abrir seleção (UX ok).
      // Se quiser aceitar drop real, use um <input webkitdirectory> ou lib de upload.
      input.click();
    }
  });
}

function initUploadBoxes() {
  // Delegado: funciona mesmo quando Turbo re-renderiza
  document.addEventListener("change", (e) => {
    const t = e.target;
    if (!(t instanceof HTMLInputElement)) return;
    if (t.type !== "file") return;
    if (!["orders_file", "invoices_file"].includes(t.id)) return;
    updateLabel(t);
  });

  // Bind inicial (para estado preservado ao voltar de navegação)
  ["orders_file", "invoices_file"].forEach((id) => {
    const input = document.getElementById(id);
    const label = document.querySelector(`label[for="${id}"]`);
    if (input) updateLabel(input);
    bindDnD(label, input);
  });
}

document.addEventListener("turbo:load", initUploadBoxes);
document.addEventListener("DOMContentLoaded", initUploadBoxes);
