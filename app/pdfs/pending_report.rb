# frozen_string_literal: true

require "prawn"
require "prawn/table"
require "action_view"
require "action_view/helpers"

class PendingReport
  include ActionView::Helpers::NumberHelper

  # Espera o mesmo contrato já usado no controller:
  #   PendingReport.new(user: current_user, result: result, title: "Relatório de Pendências", by_item: true/false).render
  #
  # Onde `result` é o objeto retornado por PendingRowsQuery.run:
  #   result.summary -> hash com métricas
  #   result.rows    -> array de hashes já filtradas (>= 90d) e deduplicadas
  #
  def initialize(user:, result:, title: "Relatório de Pendências", by_item: nil)
    @user     = user
    @result   = result
    @title    = title
    @rows     = Array(result&.rows)
    @summary  = (result&.summary || {})
    # Se não vier explícito, tenta descobrir pelo summary
    @by_item  = !by_item.nil? ? by_item : (fetch(@summary, :group_by).to_s == "item")
  end

  # Gera o PDF em memória e retorna o binário (String)
  def render
    pdf = Prawn::Document.new(page_size: "A4", margin: 36)
    build_header(pdf)
    pdf.move_down 14
    build_table(pdf)
    pdf.render
  end

  private

  # ----------------- Header -----------------
  def build_header(pdf)
    pdf.text @title.to_s, size: 16, style: :bold

    generated_at = I18n.l(Time.zone ? Time.zone.now : Time.now, format: :short) rescue (Time.now.strftime("%d/%m/%Y %H:%M"))
    pdf.move_down 2
    pdf.text "gerado em #{generated_at}", size: 9, color: "666666"

    # Métricas principais vindas das linhas (garantem consistência com o que está na tabela)
    count = @rows.size
    total_value = @rows.sum { |r| money_value(r) }.to_f

    left  = "Pedidos pendentes: <b>#{count}</b>"
    right = "Valor pendente: <b>#{currency(total_value)}</b>"

    pdf.move_down 10
    pdf.table(
      [[{ content: left, inline_format: true }, { content: right, inline_format: true }]],
      cell_style: { borders: [], padding: [0, 0, 0, 0], inline_format: true },
      column_widths: [pdf.bounds.width * 0.55, pdf.bounds.width * 0.45]
    )

    exporter = display_user(@user)
    pdf.move_down 6
    pdf.text "Exportado por: #{exporter}", size: 10

    pdf.stroke_color "DDDDDD"
    pdf.move_down 8
    pdf.stroke_horizontal_rule
    pdf.move_down 6
  end

  def display_user(user)
    return "" if user.nil?
    name = (user.respond_to?(:first_name) ? user.first_name : nil).presence || user.try(:full_name).presence || ""
    mail = user.try(:email).to_s
    if name.present? && mail.present?
      "#{name} (#{mail})"
    else
      name.presence || mail
    end
  end

  def currency(v)
    number_to_currency(v.to_f, unit: "R$", separator: ",", delimiter: ".", format: "%u %n")
  end

  # ----------------- Tabela -----------------
  def build_table(pdf)
    if @rows.empty?
      pdf.text "Sem pendências com o filtro atual.", size: 11, style: :italic
      return
    end

    # Última coluna renomeada para "Coletado em"
    header =
      if @by_item
        ["Pedido", "Valor pendente (R$)", "Dias vencidos", "Coletado em"]
      else
        ["Pedido", "Valor pendente (R$)", "Dias vencidos", "Coletado em"]
      end

    today = (Time.zone || Time).today
    data = [header]

    @rows.each do |r|
      num   = fetch(r, :numero_pedido).to_s
      valor = money_value(r)
      dias  = fetch(r, :dias_vencidos).to_i

      # O campo vindo do serviço já traz a data formatada em "%d/%m/%Y" a partir do collected_at
      coletado_em = fetch(r, :data).presence
      if coletado_em.blank? && dias.positive?
        base_date = (today - dias).strftime("%d/%m/%Y") rescue nil
        coletado_em = base_date
      end

      data << [
        num,
        format_money_cell(valor),
        dias.to_i,
        coletado_em.to_s
      ]
    end

    # Estilos e largura: evitamos forçar width exata para não dar CannotFit; ainda assim limitamos a 99.5% do bounds
    pdf.table(
      data,
      header: true,
      width: pdf.bounds.width * 0.995,
      row_colors: %w[FFFFFF F7F7F7],
      cell_style: { size: 9, inline_format: false, padding: [6, 6, 6, 6] }
    ) do |t|
      t.row(0).font_style = :bold
      t.row(0).background_color = "EEEEEE"

      # Alinhamentos
      t.columns(1).align = :right # Valor
      t.columns(2).align = :right # Dias

      # Larguras aproximadas (ajuda a prevenir overflow, mas deixa Prawn ajustar se necessário)
      total_width = pdf.bounds.width * 0.995
      t.columns(0).width = total_width * 0.44   # Pedido
      t.columns(1).width = total_width * 0.20   # Valor
      t.columns(2).width = total_width * 0.18   # Dias
      t.columns(3).width = total_width * 0.18   # Coletado em
    end
  end

  # --------------- Helpers -----------------
  def fetch(h, key)
    return nil if h.nil?
    h[key] || h[key.to_s]
  end

  # Detecta e pega o valor do campo certo (alguns lugares usam "valor_pendente", outros só "valor")
  def money_value(row)
    v = fetch(row, :valor_pendente)
    v = fetch(row, :valor) if v.nil?
    v.to_f
  end

  def format_money_cell(v)
    # devolve string como "1.234,56" sem o "R$" (pois já está no cabeçalho da coluna)
    n = number_to_currency(v.to_f, unit: "", separator: ",", delimiter: ".", format: "%n").strip
    n.empty? ? "0,00" : n
  end
end
