# app/controllers/dashboards_controller.rb
class DashboardsController < ApplicationController
  before_action :authenticate_user!
  require "csv"
  def index
    @summary ||= { total_pedidos: 0, valor_faturado: 0, pedidos_pendentes: 0, valor_pendente: 0 }
    @rows    ||= []
  end

  STRICT_UPLOAD_SLOTS = true

  def upload
    files = []
    Array(params[:orders_file]).each   { |f| files << [:orders_file,   f] } if params[:orders_file].present?
    Array(params[:invoices_file]).each { |f| files << [:invoices_file, f] } if params[:invoices_file].present?

    if files.empty?
      redirect_to dashboards_path, alert: "Envie pelo menos um arquivo (Pedidos ou Pagamentos)." and return
    end

    messages = []
    errors   = []

    # Totais agregados
    orders_imported   = 0
    orders_skipped    = 0
    payments_imported = 0
    payments_skipped  = 0

    files.each do |slot, uploaded|
      fname = file_display_name(uploaded)

      # Detecta o tipo do arquivo (sem travar o loop em caso de erro)
      kind = begin
        detect_file_kind(uploaded)
      rescue => e
        Rails.logger.error("detect_file_kind failed (#{fname}): #{e.class} - #{e.message}")
        errors << "Erro ao importar (#{fname}): #{e.message}"
        next
      end

      case kind
      when :orders
        if STRICT_UPLOAD_SLOTS && slot != :orders_file
          errors << "Arquivo de **Pedidos** (#{fname}) foi anexado no campo de **Faturas**. Reanexe no campo correto."
          next
        end

        begin
          r = Import::OrdersImporter.call(user: current_user, uploaded_file: uploaded)
          if r.respond_to?(:errors) && r.errors.present?
            r.errors.each { |msg| errors << "#{msg} (#{fname})" }
          else
            orders_imported += (r.respond_to?(:imported) ? r.imported.to_i : 0)
            orders_skipped  += (r.respond_to?(:skipped_count) ? r.skipped_count.to_i : 0)
          end
        rescue => e
          Rails.logger.error("OrdersImporter failed (#{fname}): #{e.class} - #{e.message}")
          errors << "Erro ao importar (#{fname}): #{e.message}"
          next
        end

      when :payments
        if STRICT_UPLOAD_SLOTS && slot != :invoices_file
          errors << "Arquivo de **Pagamentos** (#{fname}) foi anexado no campo de **Pedidos**. Reanexe no campo correto."
          next
        end

        begin
          r = Import::PaymentsImporter.call(user: current_user, uploaded_file: uploaded)
          if r.respond_to?(:errors) && r.errors.present?
            r.errors.each { |msg| errors << "#{msg} (#{fname})" }
          else
            payments_imported += (r.respond_to?(:imported) ? r.imported.to_i : 0)
            payments_skipped  += (r.respond_to?(:skipped_count) ? r.skipped_count.to_i : 0)
          end
        rescue => e
          Rails.logger.error("PaymentsImporter failed (#{fname}): #{e.class} - #{e.message}")
          errors << "Erro ao importar (#{fname}): #{e.message}"
          next
        end

      when :ambiguous
        errors << "Arquivo em **#{slot_label(slot)}** (#{fname}) é ambíguo (contém colunas de Pedidos e Pagamentos). Não importado."
      else
        errors << "Arquivo em **#{slot_label(slot)}** (#{fname}) não possui os cabeçalhos esperados. Não importado."
      end
    end

    # Mensagens agregadas (mantendo exatamente o texto base)
    if orders_imported.positive? || orders_skipped.positive?
      messages << "Pedidos: importados #{orders_imported}."
      messages << "Pedidos ignorados (duplicados): #{orders_skipped}" if orders_skipped.positive?
    end

    if payments_imported.positive? || payments_skipped.positive?
      messages << "Pagamentos: importados #{payments_imported}."
      messages << "Pagamentos ignorados (duplicados): #{payments_skipped}" if payments_skipped.positive?
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

  def export_xls
    platform = resolved_platform
    group    = params[:group].to_s == "order" ? :order : :item

    result =
      if platform == "shopee"
        ShopeeDashboardQuery.run(user: current_user)
      else
        PendingRowsQuery.run(user: current_user, group_by: group)
      end

    rows = (result.respond_to?(:rows) ? result.rows : []) || []

    headers = ["Número do pedido", "Plataforma", "Valor", "Dias vencidos", "Status"]

    # CSV com ; como separador (bom para pt-BR) e valores com vírgula decimal.
    csv_str = CSV.generate(col_sep: ";", force_quotes: true) do |csv|
      csv << headers
      rows.each do |r|
        valor = (r["valor"] || r["valor_pendente"] || 0).to_f
        csv << [
          r["numero_pedido"],
          r["plataforma"],
          ("%.2f" % valor).tr(".", ","), # vírgula decimal
          r["dias_vencidos"].to_i,
          r["status"]
        ]
      end
    end

    filename = "pendentes-#{(Time.zone || Time).today.strftime('%Y-%m-%d')}.csv"

    send_data csv_str.encode("UTF-8"),
              filename: filename,
              type: "text/csv; charset=UTF-8",
              disposition: "attachment"
  rescue => e
    Rails.logger.error("[export_xls] #{e.class} - #{e.message}\n#{e.backtrace.take(5).join("\n")}")
    redirect_to dashboards_path(platform: platform), alert: "Falha ao gerar CSV: #{e.message}"
  end

  private

  def resolved_platform
    if respond_to?(:current_platform, true)
      current_platform
    else
      params[:platform].presence || session[:platform].presence || "shein"
    end
  end

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

  def file_display_name(uploaded)
    name = uploaded.respond_to?(:original_filename) ? uploaded.original_filename : uploaded.to_s
    File.basename(name.to_s)
  end

  # Mantido como estava (não usado na agregação, mas preservado)
  def collect_result(messages, errors, result, label:)
    if result.errors.present?
      errors.concat(result.errors)
    else
      messages << "#{label}: importados #{result.imported}."
      messages << "#{label} ignorados (duplicados): #{result.skipped_count}" if result.skipped_count.to_i.positive?
    end
  end
end
