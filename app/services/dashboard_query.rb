# frozen_string_literal: true

class DashboardQuery
  Result = Struct.new(:summary, :rows, keyword_init: true)

  MIN_OVERDUE_DAYS = 90
  TOP_LIMIT        = 10

  def self.run(user:)
    orders_rel   = user.orders
    payments_rel = user.payments

    # KPIs “de pedidos” (iguais ao parser/importer)
    total_pedidos  = orders_rel.sum(:line_count).to_i
    valor_faturado = orders_rel.sum(:value_total).to_f.round(2)

    # Só pagamentos POSITIVOS contam como pago (por pedido)
    paid_nums = payments_rel
                  .where("amount > 0")
                  .distinct
                  .pluck(:order_number)
                  .map { |n| n.to_s.strip }
                  .uniq

    # Candidatos a pendentes: linhas de pedido com valor > 0 e cujo pedido NÃO está pago
    pending_scope = orders_rel
                      .where("value_total > 0")
                      .where.not(order_number: paid_nums)

    # Precisamos de collected_at (apenas ele conta para idade) e demais campos
    pending_rows = pending_scope.select(
      :order_number, :order_date, :collected_at, :value_total, :status, :platform, :item_id,
      :product_number, :variation, :seller_sku, :shein_sku, :skc, :inventory_id,
      :tracking_code, :first_mile_waybill
    )

    # --------- DEDUPE POR ITEM (contagem por ITEM pendente) ---------
    grouped_by_order = pending_rows.group_by { |o| o.order_number.to_s.strip }

    dedup_items = []
    grouped_by_order.each do |num, arr|
      with_id    = arr.reject { |o| o.item_id.to_s.strip.empty? }
      without_id = arr.select { |o| o.item_id.to_s.strip.empty? }

      dedup_with_id = with_id
                        .group_by { |o| o.item_id.to_s.strip }
                        .values
                        .map(&:first)

      # Evitar colapsar itens distintos sem item_id: usa preço + vários identificadores
      dedup_without_id = without_id
                           .group_by do |o|
                             [
                               num,
                               format('%.2f', o.value_total.to_f),
                               o.product_number.to_s.strip,
                               o.variation.to_s.strip,
                               o.seller_sku.to_s.strip,
                               o.shein_sku.to_s.strip,
                               o.skc.to_s.strip,
                               o.inventory_id.to_s.strip,
                               o.tracking_code.to_s.strip,
                               o.first_mile_waybill.to_s.strip
                             ]
                           end
                           .values
                           .map(&:first)

      dedup_items.concat(dedup_with_id + dedup_without_id)
    end

    # KPIs de pendência (por ITEM pendente) — NÃO mexemos aqui
    pedidos_pendentes = dedup_items.size
    valor_pendente    = dedup_items.sum { |o| o.value_total.to_f }.round(2)

    # --------- TABELA (apenas collected_at) ---------
    today = (Time.zone || Time).today

    # Monta linhas por pedido **somente** se existir pelo menos um collected_at
    rows_by_order = dedup_items
      .group_by { |o| o.order_number.to_s.strip }
      .filter_map do |num, arr|
        cols = arr.map(&:collected_at).compact
        next nil if cols.empty?                      # ignora pedidos sem collected_at

        base_date = cols.min                         # só collected_at
        dias      = (today - base_date.to_date).to_i

        valor     = arr.sum { |o| o.value_total.to_f }.round(2)
        status    = arr.first&.status
        platform  = arr.first&.platform.presence || "SHEIN"

        {
          "numero_pedido"  => num,
          "plataforma"     => platform,
          "valor"          => valor,
          "dias_vencidos"  => dias,
          "status"         => status,
          "pendente"       => true,
          "valor_pendente" => valor
        }
      end

    # Top 10 com >= 90 dias
    rows = rows_by_order
             .select { |r| r["dias_vencidos"].to_i >= MIN_OVERDUE_DAYS }
             .sort_by { |r| [-r["dias_vencidos"].to_i, -r["valor_pendente"].to_f] }
             .first(TOP_LIMIT)

    swal_warning = nil
    if orders_rel.exists? && paid_nums.empty?
      swal_warning = "Nenhum pedido pago foi encontrado cruzando os relatórios. Verifique se as planilhas são do mesmo período/plataforma e se o 'Número do pedido' coincide."
    end

    summary = {
      total_pedidos:     total_pedidos,
      valor_faturado:    valor_faturado,
      pedidos_pendentes: pedidos_pendentes, # itens pendentes
      valor_pendente:    valor_pendente,
      swal_warning:      swal_warning
    }

    Result.new(summary:, rows:)
  end
end
