# app/services/dashboard_query.rb
class DashboardQuery
  Result = Struct.new(:summary, :rows, keyword_init: true)

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

    # Precisamos do item_id e do value_total para dedup
    pending_rows = pending_scope.select(:order_number, :order_date, :value_total, :status, :platform, :item_id)

    # --------- DEDUP POR ITEM (contagem por ITEM pendente) ---------
    # Regra:
    # - Se item_id presente: 1 por (order_number, item_id)
    # - Se item_id ausente: 1 por (order_number, valor_total) — evita duplicar linhas idênticas sem ID
    grouped_by_order = pending_rows.group_by { |o| o.order_number.to_s.strip }

    today = (Time.zone || Time).now.to_date

    # Coleção deduplicada de "itens pendentes"
    dedup_items = []

    grouped_by_order.each do |num, arr|
      with_id     = arr.reject { |o| o.item_id.to_s.strip.empty? }
      without_id  = arr.select { |o| o.item_id.to_s.strip.empty? }

      dedup_with_id = with_id
                        .group_by { |o| o.item_id.to_s.strip }
                        .values
                        .map { |items| items.first }

      dedup_without_id = without_id
                           .group_by { |o| [num, format('%.2f', o.value_total.to_f)] } # agrupa por valor quando não tem item_id
                           .values
                           .map { |items| items.first }

      dedup_items.concat(dedup_with_id + dedup_without_id)
    end

    # KPIs de pendência (AGORA por ITEM pendente)
    pedidos_pendentes = dedup_items.size
    valor_pendente    = dedup_items.sum { |o| o.value_total.to_f }.round(2)

    # Linhas da tabela continuam agregadas por pedido (para UX): soma valores, menor data
    rows_by_order = dedup_items.group_by { |o| o.order_number.to_s.strip }.map do |num, arr|
      order_date = arr.map(&:order_date).compact.min
      valor      = arr.sum { |o| o.value_total.to_f }.round(2)
      status     = arr.first&.status
      platform   = arr.first&.platform.presence || "SHEIN"
      dias       = order_date ? (today - order_date.to_date).to_i : 0

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

    rows = rows_by_order
             .select { |r| r["dias_vencidos"] > 90 }
             .sort_by { |r| [-r["dias_vencidos"], -r["valor_pendente"]] }
             .first(10)

    swal_warning = nil
    if orders_rel.exists? && paid_nums.empty?
      swal_warning = "Nenhum pedido pago foi encontrado cruzando os relatórios. Verifique se as planilhas são do mesmo período/plataforma e se o 'Número do pedido' coincide."
    end

    summary = {
      total_pedidos:     total_pedidos,
      valor_faturado:    valor_faturado,
      pedidos_pendentes: pedidos_pendentes, # agora “itens pendentes”
      valor_pendente:    valor_pendente,
      swal_warning:      swal_warning
    }

    Result.new(summary:, rows:)
  end
end
