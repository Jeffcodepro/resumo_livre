# frozen_string_literal: true

class PendingRowsQuery
  Result = Struct.new(:summary, :rows, keyword_init: true)

  # group_by: :item (default) ou :order
  def self.run(user:, group_by: :item)
    group_by = (group_by || :item).to_sym

    orders_rel   = user.orders
    payments_rel = user.payments

    # Informativos gerais
    total_pedidos  = orders_rel.sum(:line_count).to_i
    valor_faturado = orders_rel.sum(:value_total).to_f.round(2)

    # 1) pagos: só positivos (por pedido)
    paid_nums = payments_rel
                  .where("amount > 0")
                  .distinct
                  .pluck(:order_number)
                  .map { |n| n.to_s.strip }
                  .uniq

    # 2) candidatos: valor > 0 e pedido NÃO pago
    pending_scope = orders_rel
                      .where("value_total > 0")
                      .where.not(order_number: paid_nums)

    # 3) colunas necessárias (inclui campos de dedupe sem item_id)
    pending_rows = pending_scope.select(
      :order_number, :order_date, :collected_at, :collection_required_at,
      :value_total, :status, :platform, :item_id,
      :product_number, :variation, :seller_sku, :shein_sku, :skc, :inventory_id,
      :tracking_code, :first_mile_waybill
    )

    # 4) DEDUPE POR ITEM
    grouped_by_order = pending_rows.group_by { |o| o.order_number.to_s.strip }

    dedup_items = []
    grouped_by_order.each do |num, arr|
      with_id    = arr.reject { |o| o.item_id.to_s.strip.empty? }
      without_id = arr.select { |o| o.item_id.to_s.strip.empty? }

      dedup_with_id = with_id
                        .group_by { |o| o.item_id.to_s.strip }
                        .values.map(&:first)

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
                           .values.map(&:first)

      dedup_items.concat(dedup_with_id + dedup_without_id)
    end

    today = (Time.zone || Time).today

    # Função: apenas collected_at
    base_date_for = ->(o) { o.collected_at } # <<< SOMENTE collected_at

    # 5) Por ITEM
    items_all = dedup_items.map do |o|
      base_date = base_date_for.call(o)
      dias      = base_date ? (today - base_date.to_date).to_i : 0

      {
        "numero_pedido"  => o.order_number.to_s.strip,
        "plataforma"     => o.platform.presence || "SHEIN",
        "status"         => o.status,
        "valor_pendente" => o.value_total.to_f.round(2),
        "dias_vencidos"  => dias,
        "data"           => base_date&.strftime("%d/%m/%Y")
      }
    end

    items_90 = items_all
                 .select { |r| r["dias_vencidos"].to_i >= 90 }
                 .sort_by { |r| [-r["dias_vencidos"].to_i, -r["valor_pendente"].to_f] }

    # 6) Por PEDIDO (agregando itens do pedido) — base = menor collected_at
    orders_all = dedup_items.group_by { |o| o.order_number.to_s.strip }.map do |num, arr|
      base_date = arr.map(&:collected_at).compact.min # <<< SOMENTE collected_at
      valor     = arr.sum { |o| o.value_total.to_f }.round(2)
      status    = arr.first&.status
      platform  = arr.first&.platform.presence || "SHEIN"
      dias      = base_date ? (today - base_date.to_date).to_i : 0

      {
        "numero_pedido"  => num,
        "plataforma"     => platform,
        "valor_pendente" => valor,
        "dias_vencidos"  => dias,
        "status"         => status,
        "data"           => base_date&.strftime("%d/%m/%Y")
      }
    end

    orders_90 = orders_all
                  .select { |r| r["dias_vencidos"].to_i >= 90 }
                  .sort_by { |r| [-r["dias_vencidos"].to_i, -r["valor_pendente"].to_f] }

    # 7) KPIs
    totals_per_item_count = items_all.size
    totals_per_item_value = items_all.sum { |r| r["valor_pendente"].to_f }.round(2)
    totals_per_order_count = orders_all.size
    totals_per_order_value = orders_all.sum { |r| r["valor_pendente"].to_f }.round(2)

    older90_per_item_count = items_90.size
    older90_per_item_value = items_90.sum { |r| r["valor_pendente"].to_f }.round(2)
    older90_per_order_count = orders_90.size
    older90_per_order_value = orders_90.sum { |r| r["valor_pendente"].to_f }.round(2)

    rows =
      if group_by == :item
        items_90
      else
        orders_90
      end

    summary = {
      group_by: group_by,

      pedidos_pendentes: (group_by == :item ? totals_per_item_count : totals_per_order_count),
      valor_pendente:    (group_by == :item ? totals_per_item_value : totals_per_order_value),
      older90_count:     (group_by == :item ? older90_per_item_count : older90_per_order_count),
      older90_value:     (group_by == :item ? older90_per_item_value : older90_per_order_value),

      totals_per_item_count:  totals_per_item_count,
      totals_per_item_value:  totals_per_item_value,
      totals_per_order_count: totals_per_order_count,
      totals_per_order_value: totals_per_order_value,

      total_pedidos:  total_pedidos,
      valor_faturado: valor_faturado
    }

    Result.new(summary: summary, rows: rows)
  end
end
