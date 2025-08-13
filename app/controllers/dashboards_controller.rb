class DashboardsController < ApplicationController
  before_action :authenticate_user!

  def index
    # apenas renderiza a tela com cards zerados e formulário de upload
    @summary ||= { total_pedidos: 0, valor_faturado: 0, pedidos_pendentes: 0, valor_pendente: 0 }
    @rows    ||= []
  end

  def upload
    unless params[:orders_file].present? && params[:invoices_file].present?
      redirect_to dashboards_path, alert: "Envie as duas planilhas (Pedidos e Faturas)."
      return
    end

    result = SpreadsheetParser.parse(
      orders_file: params[:orders_file],
      invoices_file: params[:invoices_file]
    )

    @summary = result.summary
    @rows    = result.rows
    render :index
  rescue => e
    Rails.logger.error(e.full_message)
    redirect_to dashboards_path, alert: "Erro ao processar planilhas: #{e.message}"
  end
end
