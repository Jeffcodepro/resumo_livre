# frozen_string_literal: true

module Import
  class OrdersImporter
    require "roo"
    require "set"

    REQUIRED_HEADER   = "Receita estimada de mercadorias"
    HEADER_ROW_INDEX  = 2

    Result = Struct.new(:imported, :skipped_count, :skipped_numbers, :errors, keyword_init: true)

    def self.call(user:, uploaded_file:)
      xlsx     = open_spreadsheet(uploaded_file)
      sheet    = xlsx.sheet(0)
      headers  = sheet.row(HEADER_ROW_INDEX).map(&:to_s)

      unless headers.any? { |h| norm(h).include?(norm(REQUIRED_HEADER)) }
        return Result.new(
          imported: 0, skipped_count: 0, skipped_numbers: [],
          errors: ["O arquivo enviado não parece ser o de Pedidos. Esperado cabeçalho contendo “#{REQUIRED_HEADER}”."]
        )
      end

      # Chaves principais
      number_key  = find_key(headers, "número do pedido", "numero do pedido", "pedido", "order number")
      status_key  = find_key(headers, "status do pedido", "status")
      date_key    = find_key(headers, "coletado em", "coletado") # (usado pra order_date)

      # ==== Coluna de VALOR (robusta contra mudanças nas últimas colunas)
      rows = (HEADER_ROW_INDEX + 1..sheet.last_row).map { |i| headers.zip(sheet.row(i)).to_h }
      value_key = detect_value_header(headers, rows)
      raise "Não foi possível identificar a coluna de valor em Pedidos" if value_key.nil?

      item_id_key = find_key(headers, "id do item")
      raise "Coluna 'Número do pedido' não encontrada." if number_key.nil?

      # Extras
      order_type_key              = find_key(headers, "tipo de pedido")
      exchange_order_number_key   = find_key(headers, "pedido de troca")
      shipping_mode_key           = find_key(headers, "modo de envio")
      instado_key                 = find_key(headers, "instado ou não", "instado")
      is_lost_key                 = find_key(headers, "está perdido", "esta perdido")
      should_stay_key             = find_key(headers, "se deve ficar")
      has_issues_key              = find_key(headers, "pedido com problemas")
      product_name_key            = find_key(headers, "nome do produto")
      product_number_key          = find_key(headers, "número do produto", "numero do produto")
      variation_key               = find_key(headers, "variação", "variacao")
      seller_sku_key              = find_key(headers, "sku do vendedor")
      shein_sku_key               = find_key(headers, "shein-sku")
      skc_key                     = find_key(headers, "skc")
      product_status_key          = find_key(headers, "status do produto")
      inventory_id_key            = find_key(headers, "id do inventário", "id do inventario")
      exchange_code_key           = find_key(headers, "código de troca", "codigo de troca")
      exchange_reason_key         = find_key(headers, "motivo da substituição", "motivo da substituicao")
      exchange_product_id_key     = find_key(headers, "id do produto a ser trocado")
      is_blocked_key              = find_key(headers, "bloqueado ou não", "bloqueado")
      label_print_deadline_key    = find_key(headers, "prazo para imprimir etiqueta")
      collection_required_at_key  = find_key(headers, "data e hora requeridas para coleta")
      collected_at_key            = find_key(headers, "coletado em")
      tracking_code_key           = find_key(headers, "código de rastreio", "codigo de rastreio")
      last_mile_provider_key      = find_key(headers, "fornecedor de logística de última milha", "fornecedor de logistica de ultima milha")
      merchant_package_key        = find_key(headers, "pacote do comerciante")
      passes_warehouse_key        = find_key(headers, "se o pacote passa pelo armazém", "se o pacote passa pelo armazem")
      first_mile_provider_key     = find_key(headers, "fornecedor de logística de primeira mão", "fornecedor de logistica de primeira mao")
      first_mile_waybill_key      = find_key(headers, "número da carta de porte de primeira viagem", "numero da carta de porte de primeira viagem")
      seller_currency_key         = find_key(headers, "moeda do vendedor")
      product_price_key           = find_key(headers, "preço do produto", "preco do produto")
      coupon_value_key            = find_key(headers, "valor do cupom")
      store_campaign_discount_key = find_key(headers, "desconto de campanha da loja")
      commission_key              = find_key(headers, "comissão", "comissao")

      # Filtra válidas
      valid = rows.select do |row|
        num = row[number_key].to_s.strip
        next false if num.blank?
        !refunded?(row[status_key])
      end

      # --- DEDUP INSERÇÃO POR ITEM ---
      seen_items_by_order = Hash.new { |h, k| h[k] = Set.new } # order_number => Set[item_id]
      seen_no_id_orders   = Set.new

      existing_pairs = Order.where(user_id: user.id)
                            .pluck(:order_number, :item_id)
                            .map { |num, iid| [num.to_s.strip, iid.to_s.strip.presence] }
                            .to_set

      to_insert = []
      skipped   = []

      valid.each do |row|
        num    = row[number_key].to_s.strip
        iid    = row[item_id_key].to_s.strip
        has_id = !iid.empty?

        if has_id
          pair = [num, iid]
          if seen_items_by_order[num].include?(iid) || existing_pairs.include?(pair)
            skipped << num
            next
          end
          seen_items_by_order[num] << iid
        else
          if seen_no_id_orders.include?(num) || existing_pairs.include?([num, nil])
            skipped << num
            next
          end
          seen_no_id_orders << num
        end

        order_date = parse_time(row[date_key])
        value      = to_d(row[value_key])

        to_insert << {
          user_id:                   user.id,
          order_number:              num,
          platform:                  "SHEIN",
          status:                    row[status_key].to_s,
          order_date:                order_date,
          value_total:               value,
          line_count:                1,
          order_type:                presence(row[order_type_key]),
          exchange_order_number:     presence(row[exchange_order_number_key]),
          shipping_mode:             presence(row[shipping_mode_key]),
          instado:                   to_bool(row[instado_key]),
          is_lost:                   to_bool(row[is_lost_key]),
          should_stay:               to_bool(row[should_stay_key]),
          has_issues:                to_bool(row[has_issues_key]),
          product_name:              presence(row[product_name_key]),
          product_number:            presence(row[product_number_key]),
          variation:                 presence(row[variation_key]),
          seller_sku:                presence(row[seller_sku_key]),
          shein_sku:                 presence(row[shein_sku_key]),
          skc:                       presence(row[skc_key]),
          item_id:                   has_id ? iid : nil,
          product_status:            presence(row[product_status_key]),
          inventory_id:              presence(row[inventory_id_key]),
          exchange_code:             presence(row[exchange_code_key]),
          exchange_reason:           presence(row[exchange_reason_key]),
          exchange_product_id:       presence(row[exchange_product_id_key]),
          is_blocked:                to_bool(row[is_blocked_key]),
          label_print_deadline:      parse_time(row[label_print_deadline_key]),
          collection_required_at:    parse_time(row[collection_required_at_key]),
          collected_at:              parse_time(row[collected_at_key]),
          tracking_code:             presence(row[tracking_code_key]),
          last_mile_provider:        presence(row[last_mile_provider_key]),
          merchant_package:          to_bool(row[merchant_package_key]),
          passes_through_warehouse:  to_bool(row[passes_warehouse_key]),
          first_mile_provider:       presence(row[first_mile_provider_key]),
          first_mile_waybill:        presence(row[first_mile_waybill_key]),
          seller_currency:           presence(row[seller_currency_key]),
          product_price:             decimal_or_nil(row[product_price_key]),
          coupon_value:              decimal_or_nil(row[coupon_value_key]),
          store_campaign_discount:   decimal_or_nil(row[store_campaign_discount_key]),
          commission:                decimal_or_nil(row[commission_key]),
          raw:                       row,
          created_at:                Time.current,
          updated_at:                Time.current
        }
      end

      Order.insert_all(to_insert) if to_insert.any?

      Result.new(
        imported: to_insert.size,
        skipped_count: skipped.size,
        skipped_numbers: skipped.first(50),
        errors: []
      )
    rescue => e
      Result.new(imported: 0, skipped_count: 0, skipped_numbers: [], errors: ["Erro ao importar Pedidos: #{e.message}"])
    end

    # ---------- helpers ----------
    def self.open_spreadsheet(uploaded)
      path = uploaded.tempfile.path
      ext  = File.extname(uploaded.original_filename).downcase
      case ext
      when ".xlsx", ".xlsm" then Roo::Excelx.new(path)
      when ".csv"           then Roo::CSV.new(path, csv_options: { encoding: "utf-8" })
      else
        raise "Formato não suportado: #{ext} (use .xlsx ou .csv)"
      end
    end

    def self.find_key(headers, *candidates)
      down = headers.map { |h| [norm(h), h] }.to_h
      candidates.each do |cand|
        key = down.keys.find { |k| k.include?(norm(cand)) }
        return down[key] if key
      end
      nil
    end

    def self.norm(str)
      s = str.to_s
      s = ActiveSupport::Inflector.transliterate(s)
      s.downcase.strip
    end

    def self.presence(v)
      v = v.to_s.strip
      v.empty? ? nil : v
    end

    def self.to_bool(v)
      s = v.to_s.strip.downcase
      return true  if %w[sim yes true 1 y].include?(s)
      return false if %w[não nao no false 0 n].include?(s)
      nil
    end

    def self.decimal_or_nil(v)
      s = v.to_s
      return nil if s.strip.empty?
      to_d(s)
    end

    def self.to_d(value)
      return 0.to_d if value.nil? || (value.respond_to?(:blank?) && value.blank?)
      return BigDecimal(value.to_s) if value.is_a?(Numeric)
      s = value.to_s.strip.gsub(/[^\d,.\-]/, "")
      if s.include?(",") && s.include?(".")
        s = s.rindex(",") > s.rindex(".") ? s.gsub(".", "").gsub(",", ".") : s.gsub(",", "")
      elsif s.include?(",")
        s = s.gsub(",", ".")
      end
      BigDecimal(s)
    rescue
      0.to_d
    end

    # ---------- PARSERS DE DATA/HORA (PT-BR ROBUSTO) ----------
    def self.parse_time(value)
      parse_time_br(value)
    end

    def self.parse_date(value)
      d = parse_date_br(value)
      d&.to_date
    end

    def self.parse_time_br(value)
      return nil if value.nil? || (value.respond_to?(:blank?) && value.blank?)

      zone = Time.zone || ActiveSupport::TimeZone['America/Sao_Paulo']

      case value
      when Time
        return zone.at(value)
      when DateTime
        return zone.local(value.year, value.month, value.day, value.hour, value.min, value.sec)
      when Date
        return zone.local(value.year, value.month, value.day, 0, 0, 0)
      when Numeric
        # Excel serial date/time (a partir de 1899-12-30)
        base = Date.new(1899, 12, 30)
        days = value.floor
        frac = value - days
        date = base + days
        secs = (frac * 86_400).round
        h = secs / 3600
        m = (secs % 3600) / 60
        s = secs % 60
        return zone.local(date.year, date.month, date.day, h, m, s)
      else
        s = value.to_s.strip
        return nil if s.empty?
        if (dt = parse_time_from_pt_string(s, zone))
          return dt
        end
        Time.parse(s) rescue nil
      end
    end

    def self.parse_date_br(value)
      t = parse_time_br(value)
      t&.to_date
    end

    def self.parse_time_from_pt_string(str, zone)
      s = ActiveSupport::Inflector.transliterate(str).downcase.strip

      months = {
        "janeiro"=>1, "fevereiro"=>2, "marco"=>3, "abril"=>4, "maio"=>5, "junho"=>6, "julho"=>7, "agosto"=>8,
        "setembro"=>9, "outubro"=>10, "novembro"=>11, "dezembro"=>12,
        "jan"=>1, "fev"=>2, "mar"=>3, "abr"=>4, "mai"=>5, "jun"=>6, "jul"=>7, "ago"=>8,
        "set"=>9, "out"=>10, "nov"=>11, "dez"=>12
      }

      # 1) "dd [de] <mes> [de] yyyy [hh:mm[:ss]]"
      if s =~ /\A\s*(\d{1,2})\s*(?:de\s*)?([a-z]{3,9})\s*(?:de\s*)?(\d{4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?\s*\z/
        d  = $1.to_i
        mn = $2
        y  = $3.to_i
        hh = ($4 || "0").to_i
        mm = ($5 || "0").to_i
        ss = ($6 || "0").to_i
        m  = months[mn]
        return zone.local(y, m, d, hh, mm, ss) if m
      end

      # 2) "dd/mm/yyyy [hh:mm[:ss]]" ou "dd-mm-yyyy ..."
      if s =~ /\A\s*(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?\s*\z/
        d  = $1.to_i
        m  = $2.to_i
        y  = $3.to_i
        y += 2000 if y < 100
        hh = ($4 || "0").to_i
        mm = ($5 || "0").to_i
        ss = ($6 || "0").to_i
        return zone.local(y, m, d, hh, mm, ss)
      end

      # 3) "yyyy-mm-dd[ hh:mm[:ss]]"
      if s =~ /\A\s*(\d{4})-(\d{1,2})-(\d{1,2})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?\s*\z/
        y  = $1.to_i
        m  = $2.to_i
        d  = $3.to_i
        hh = ($4 || "0").to_i
        mm = ($5 || "0").to_i
        ss = ($6 || "0").to_i
        return zone.local(y, m, d, hh, mm, ss)
      end

      nil
    end

    def self.refunded?(status)
      norm(status).include?("reembolsado por cliente")
    end

    # =========================
    # NOVO: detecção robusta do header de valor
    # =========================
    def self.detect_value_header(headers, data_rows)
      # 1) por nome (sinônimos prováveis)
      by_name = find_key(
        headers,
        "Receita estimada de mercadorias",
        "Receita estimada de mercadorias (R$)",
        "Receita de mercadorias",
        "Valor total",
        "Total do pedido",
        "Valor do pedido",
        "Estimated merchandise revenue",
        "Merchandise revenue",
        "Order total"
      )
      return by_name if by_name

      # 2) ignora SEMPRE as duas últimas não vazias
      non_empty = headers.select { |h| h.to_s.strip != "" }
      # casos pequenos (degenerados)
      return non_empty.last if non_empty.size <= 1
      return non_empty[-3]  if non_empty.size == 3

      # remove as duas últimas
      candidates = non_empty.size >= 4 ? non_empty[0..-3] : non_empty

      # 3) heurística: olhar até 6 últimas candidatas (sem as duas finais)
      slice  = candidates.last([candidates.size, 6].min)
      sample = data_rows.first(250)

      best_hdr  = nil
      best_numc = -1
      best_sum  = BigDecimal("0")

      slice.each do |hdr|
        values = sample.map { |r| r[hdr] }
        numc   = values.count { |v| numeric_like?(v) }
        sum    = values.reduce(0.to_d) { |acc, v| acc + to_d(v) }

        if (numc > best_numc) || (numc == best_numc && sum > best_sum)
          best_hdr  = hdr
          best_numc = numc
          best_sum  = sum
        end
      end

      return best_hdr if best_hdr.present? && best_sum > 0

      # 4) fallback final: antepenúltima não vazia
      non_empty.size >= 3 ? non_empty[-3] : non_empty.last
    end

    def self.numeric_like?(v)
      return true if v.is_a?(Numeric)
      s = v.to_s.strip
      s.match?(/\A-?\d+(?:[.,]\d+)?\z/)
    end
  end
end
