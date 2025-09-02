# frozen_string_literal: true

module Import
  class PaymentsImporter
    require "roo"
    require "set"

    REQUIRED_HEADER  = "Valor a receber"
    HEADER_ROW_INDEX = 2

    Result = Struct.new(:imported, :skipped_count, :skipped_numbers, :errors, keyword_init: true)

    def self.call(user:, uploaded_file:)
      xlsx     = open_spreadsheet(uploaded_file)
      sheet    = xlsx.sheet(0)
      headers  = sheet.row(HEADER_ROW_INDEX).map(&:to_s)

      unless headers.any? { |h| norm(h).include?(norm(REQUIRED_HEADER)) }
        return Result.new(
          imported: 0, skipped_count: 0, skipped_numbers: [],
          errors: ["O arquivo enviado não parece ser o de Faturas/Pagamentos. Esperado cabeçalho contendo “#{REQUIRED_HEADER}”."]
        )
      end

      data_rows  = (HEADER_ROW_INDEX + 1..sheet.last_row).map { |i| sheet.row(i) }
      header_map = headers.map(&:to_s)
      rows       = data_rows.map { |r| header_map.zip(r).to_h }

      number_key    = find_key(headers, "número do pedido", "numero do pedido", "pedido", "order number")
      paid_at_key   = find_key(headers, "data de pagamento", "data", "pago em")
      value_key     = find_key(headers, "valor a receber", "valor recebido", "valor pago")

      # Campos extras
      site_key                 = find_key(headers, "site")
      related_order_key        = find_key(headers, "número de pedido relacionado", "numero de pedido relacionado")
      invoice_number_key       = find_key(headers, "número de fatura", "numero de fatura")
      seller_delivery_date_key = find_key(headers, "data de entrega do vendedor")
      delivered_at_key         = find_key(headers, "data e hora de entrega")
      invoice_type_key         = find_key(headers, "tipo de fatura")
      product_price_sum_key    = find_key(headers, "resumo de preços de produtos")
      campaign_discount_key    = find_key(headers, "desconto da campanha")
      store_coupon_value_key   = find_key(headers, "valor do cupom da loja")
      payment_commission_key   = find_key(headers, "comissão", "comissao")
      freight_fee_key          = find_key(headers, "taxa de intermediação de frete")
      storage_fee_key          = find_key(headers, "taxa de operação de estocagem")
      return_fee_key           = find_key(headers, "taxa de processamento de devolução")

      raise "Coluna 'Número do pedido' não encontrada." if number_key.nil?

      # --- Apenas POSITIVOS. Se houver vários positivos por pedido, usa o MAIOR. ---
      by_order = {}
      rows.each do |row|
        num = row[number_key].to_s.strip
        next if num.blank?
        amt = to_d(row[value_key])
        next unless amt > 0

        prev = by_order[num]
        if prev.nil? || amt > prev["__amount__"]
          by_order[num] = row.merge("__amount__" => amt)
        end
      end
      filtered = by_order.values

      nums     = filtered.map { |r| r[number_key].to_s.strip }
      existing = Payment.where(user_id: user.id, order_number: nums).pluck(:order_number).to_set

      to_insert = []
      skipped   = []

      filtered.each do |row|
        num = row[number_key].to_s.strip
        if existing.include?(num)
          skipped << num
          next
        end

        to_insert << {
          user_id:                    user.id,
          order_number:               num,
          platform:                   "SHEIN",
          amount:                     row["__amount__"],                      # positivo
          paid_at:                    parse_time(row[paid_at_key]),
          site:                       row[site_key],
          related_order_number:       row[related_order_key],
          invoice_number:             row[invoice_number_key],
          seller_delivery_date:       parse_date(row[seller_delivery_date_key]),
          delivered_at:               parse_time(row[delivered_at_key]),
          invoice_type:               row[invoice_type_key],
          product_price_summary:      to_d(row[product_price_sum_key]),
          campaign_discount:          to_d(row[campaign_discount_key]),
          store_coupon_value:         to_d(row[store_coupon_value_key]),
          payment_commission:         to_d(row[payment_commission_key]),
          freight_intermediation_fee: to_d(row[freight_fee_key]),
          storage_operation_fee:      to_d(row[storage_fee_key]),
          return_processing_fee:      to_d(row[return_fee_key]),
          raw:                        row.except("__amount__"),
          created_at:                 Time.current,
          updated_at:                 Time.current
        }
      end

      ActiveRecord::Base.transaction do
        Payment.insert_all(to_insert) if to_insert.any?
        cleanup_negatives_when_positive_exists(user)
      end

      Result.new(
        imported: to_insert.size,
        skipped_count: skipped.size,
        skipped_numbers: skipped.first(50),
        errors: []
      )
    rescue => e
      Result.new(imported: 0, skipped_count: 0, skipped_numbers: [], errors: ["Erro ao importar Pagamentos: #{e.message}"])
    end

    # ---------- helpers ----------
    def self.cleanup_negatives_when_positive_exists(user)
      pos_nums = Payment.where(user_id: user.id).where("amount > 0").distinct.pluck(:order_number)
      return if pos_nums.empty?
      Payment.where(user_id: user.id, order_number: pos_nums).where("amount <= 0").delete_all
    end

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
  end
end
