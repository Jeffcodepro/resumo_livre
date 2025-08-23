# app/controllers/dashboards_controller.rb
class DashboardsController < ApplicationController
  before_action :authenticate_user!

  def index
    # tela inicial SEM dados
    @summary = { total_pedidos: 0, valor_faturado: 0, pedidos_pendentes: 0, valor_pendente: 0 }
    @rows    = []
  end

  def upload
    # 0) Sem arquivos → zera, alerta e NÃO processa
    if params[:orders_file].blank? || params[:invoices_file].blank?
      # usa SweetAlert (Opção A no layout)
      redirect_to dashboards_path, flash: { swal: "Selecione as duas planilhas: Pedidos e Faturas." } and return
    end

    # 1) Validação por cabeçalhos obrigatórios (não processa se errado)
    probe = SpreadsheetParser.validate_uploads(
      orders_file:   params[:orders_file],
      invoices_file: params[:invoices_file]
    )

    unless probe[:ok]
      # ZERA SEMPRE quando inválido
      @summary = { total_pedidos: 0, valor_faturado: 0, pedidos_pendentes: 0, valor_pendente: 0 }
      @rows    = []

      msg_lines = []
      msg_lines += probe[:errors]
      msg_lines << ""
      msg_lines << "Dica: o arquivo de **Pedidos** deve conter “#{SpreadsheetParser::REQUIRED_ORDERS_HEADER}”."
      msg_lines << "      o arquivo de **Faturas** deve conter “#{SpreadsheetParser::REQUIRED_INVOICES_HEADER}”."

      # SweetAlert na renderização atual
      flash.now[:swal] = msg_lines.join("\n")
      render :index and return   # ← interrompe o fluxo; NÃO chama parse
    end

    # 2) Tudo certo → processa normalmente
    result   = SpreadsheetParser.parse(
      orders_file:   params[:orders_file],
      invoices_file: params[:invoices_file]
    )
    @summary = result.summary
    @rows    = result.rows

    # 3) Alerta “sem cruzamento” (se aplicável)
    flash.now[:swal] = @summary[:swal_warning] if @summary[:swal_warning].present?

    render :index
  rescue => e
    Rails.logger.error("UPLOAD ERROR: #{e.class} - #{e.message}")
    redirect_to dashboards_path, alert: "Erro ao processar planilhas: #{e.message}"
  end
end
