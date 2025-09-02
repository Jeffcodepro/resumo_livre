# app/controllers/dashboards_controller.rb
class DashboardsController < ApplicationController
  before_action :authenticate_user!

  def index
    @summary ||= { total_pedidos: 0, valor_faturado: 0, pedidos_pendentes: 0, valor_pendente: 0 }
    @rows    ||= []
  end

  STRICT_UPLOAD_SLOTS = true

  def upload
    files = []
    files << [:orders_file,   params[:orders_file]]   if params[:orders_file].present?
    files << [:invoices_file, params[:invoices_file]] if params[:invoices_file].present?

    if files.empty?
      redirect_to dashboards_path, alert: "Envie pelo menos um arquivo (Pedidos ou Pagamentos)." and return
    end

    messages = []
    errors   = []

    files.each do |slot, uploaded|
      kind = detect_file_kind(uploaded)

      case kind
      when :orders
        if STRICT_UPLOAD_SLOTS && slot != :orders_file
          errors << "Arquivo de **Pedidos** foi anexado no campo de **Faturas**. Reanexe no campo correto."
          next
        end
        r = Import::OrdersImporter.call(user: current_user, uploaded_file: uploaded)
        collect_result(messages, errors, r, label: "Pedidos")

      when :payments
        if STRICT_UPLOAD_SLOTS && slot != :invoices_file
          errors << "Arquivo de **Pagamentos** foi anexado no campo de **Pedidos**. Reanexe no campo correto."
          next
        end
        r = Import::PaymentsImporter.call(user: current_user, uploaded_file: uploaded)
        collect_result(messages, errors, r, label: "Pagamentos")

      when :ambiguous
        errors << "Arquivo em **#{slot_label(slot)}** é ambíguo (contém colunas de Pedidos e Pagamentos). Não importado."
      else
        errors << "Arquivo em **#{slot_label(slot)}** não possui os cabeçalhos esperados. Não importado."
      end
    end

    flash[:swal] = ([*messages, *errors].join("\n")) if messages.any? || errors.any?
    redirect_to dashboards_path
  rescue => e
    Rails.logger.error("UPLOAD ERROR: #{e.class} - #{e.message}")
    redirect_to dashboards_path, alert: "Erro ao importar: #{e.message}"
  end

  def load_from_db
    result   = DashboardQuery.run(user: current_user)
    @summary = result.summary
    @rows    = result.rows
    render :index
  end

  # === Exporta PENDENTES exatamente como o dashboard: POR ITEM por padrão, com corte ≥90 dias ===
  def export_pdf
    group = params[:group].to_s == "order" ? :order : :item

    result = PendingRowsQuery.run(user: current_user, group_by: group)
    pdf    = PendingReport.new(user: current_user, result: result, title: "Relatório de Pendências", by_item: (group == :item)).render

    suffix   = group == :item ? "por-item" : "por-pedido"
    filename = "pendentes-#{suffix}-#{(Time.zone || Time).today.strftime('%Y-%m-%d')}.pdf"

    send_data pdf,
              filename: filename,
              type: "application/pdf",
              disposition: "attachment"
  rescue => e
    Rails.logger.error("[export_pdf] #{e.class} - #{e.message}\n#{e.backtrace.take(5).join("\n")}")
    redirect_to dashboards_path, alert: "Falha ao gerar PDF: #{e.message}"
  end
  private

  def detect_file_kind(uploaded)
    headers = SpreadsheetParser.headers_from(uploaded, header_row_index: 2) rescue []
    has_orders   = SpreadsheetParser.contains_header?(headers, SpreadsheetParser::REQUIRED_ORDERS_HEADER)
    has_payments = SpreadsheetParser.contains_header?(headers, SpreadsheetParser::REQUIRED_INVOICES_HEADER)

    return :orders    if has_orders && !has_payments
    return :payments  if has_payments && !has_orders
    return :ambiguous if has_orders && has_payments
    :unknown
  end

  def slot_label(slot)
    slot == :orders_file ? "Pedidos" : "Faturas/Pagamentos"
  end

  def collect_result(messages, errors, result, label:)
    if result.errors.present?
      errors.concat(result.errors)
    else
      messages << "#{label}: importados #{result.imported}."
      messages << "#{label} ignorados (duplicados): #{result.skipped_count}" if result.skipped_count.to_i.positive?
    end
  end
end
