# app/queries/dashboard_query.rb (ou onde estiver)

class DashboardQuery
  Result = Struct.new(:summary, :rows, keyword_init: true)

  MIN_OVERDUE_DAYS = 30     # <- era 90, agora 30
  TOP_LIMIT        = 10

  def self.run(user:)
    orders_rel   = user.orders
    payments_rel = user.payments

    total_pedidos  = orders_rel.sum(:line_count).to_i
    valor_faturado = orders_rel.sum(:value_total).to_f.round(2)

    paid_nums = payments_rel
                  .where("amount > 0")
                  .distinct
                  .pluck(:order_number)
                  .map { |n| n.to_s.strip }
                  .uniq

    pending_scope = orders_rel
                      .where("value_total > 0")
                      .where.not(order_number: paid_nums)

    pending_rows = pending_scope.select(
      :order_number, :order_date, :collected_at, :value_total, :status, :platform, :item_id,
      :product_number, :variation, :seller_sku, :shein_sku, :skc, :inventory_id,
      :tracking_code, :first_mile_waybill
    )

    grouped_by_order = pending_rows.group_by { |o| o.order_number.to_s.strip }

    dedup_items = []
    grouped_by_order.each do |num, arr|
      with_id    = arr.reject { |o| o.item_id.to_s.strip.empty? }
      without_id = arr.select { |o| o.item_id.to_s.strip.empty? }

      dedup_with_id = with_id.group_by { |o| o.item_id.to_s.strip }.values.map(&:first)

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
        end.values.map(&:first)

      dedup_items.concat(dedup_with_id + dedup_without_id)
    end

    # ===== KPIs (agora só ≥ 30 dias e com collected_at presente) =====
    today = (Time.zone || Time).today
    cutoff_items = dedup_items.select do |o|
      base = o.collected_at
      base && ((today - base.to_date).to_i >= MIN_OVERDUE_DAYS)
    end

    pedidos_pendentes = cutoff_items.size
    valor_pendente    = cutoff_items.sum { |o| o.value_total.to_f }.round(2)

    # ===== TABELA por pedido (usa somente collected_at) =====
    rows_by_order = dedup_items
      .group_by { |o| o.order_number.to_s.strip }
      .filter_map do |num, arr|
        cols = arr.map(&:collected_at).compact
        next nil if cols.empty?

        base_date = cols.min
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

    # Top 10 agora também com ≥ 30 dias
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
      pedidos_pendentes: pedidos_pendentes, # agora só ≥ 30d
      valor_pendente:    valor_pendente,    # agora só ≥ 30d
      swal_warning:      swal_warning
    }

    Result.new(summary:, rows:)
  end
end
