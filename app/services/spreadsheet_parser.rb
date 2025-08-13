# app/services/spreadsheet_parser.rb
class SpreadsheetParser
  require "roo"
  Result = Struct.new(:summary, :rows, keyword_init: true)

  def self.parse(orders_file:, invoices_file:)
    orders   = open_spreadsheet(orders_file)
    invoices = open_spreadsheet(invoices_file)

    orders_df   = normalize_orders(orders)
    invoices_df = normalize_invoices(invoices)
    compute(orders_df, invoices_df)
  end

  def self.open_spreadsheet(uploaded)
    path = uploaded.tempfile.path
    ext  = File.extname(uploaded.original_filename).downcase
    case ext
    when ".xlsx", ".xls" then Roo::Spreadsheet.open(path)
    when ".csv"          then Roo::CSV.new(path, csv_options: { encoding: "utf-8" })
    else
      raise "Formato não suportado: #{ext}"
    end
  end

  def self.normalize_orders(xlsx)
    sheet = xlsx.sheet(0)
    headers = sheet.row(1).map(&:to_s)
    rows = (2..sheet.last_row).map { |i| sheet.row(i) }.map { |r| headers.zip(r).to_h }

    {
      rows: rows,
      number_key: find_key(headers, "número do pedido", "numero do pedido", "pedido"),
      status_key: find_key(headers, "status do pedido", "status"),
      price_key:  find_key(headers, "preço do produto", "preco do produto", "valor", "preço", "preco"),
      coupon_key: find_key(headers, "valor do cupom", "cupom"),
      created_at_key: find_key(headers, "data e hora de criação do pedido", "data", "criação")
    }
  end

  def self.normalize_invoices(xlsx)
    sheet = xlsx.sheet(0)
    headers = sheet.row(2).map(&:to_s)            # cabeçalho na linha 2
    rows    = (3..sheet.last_row).map { |i| sheet.row(i) }.map { |r| headers.zip(r).to_h }

    {
      rows: rows,
      number_key: find_key(headers, "número do pedido", "numero do pedido", "pedido"),
      site_key:   find_key(headers, "site", "plataforma"),
      paid_at_key: find_key(headers, "data de pagamento"),
      received_key: find_key(headers, "valor a receber", "valor", "total", "preço", "preco")
    }
  end

  def self.find_key(headers, *candidates)
    downcased = headers.map { |h| [h.downcase, h] }.to_h
    candidates.each do |cand|
      k = downcased.keys.find { |h| h.include?(cand) }
      return downcased[k] if k
    end
    nil
  end

  def self.compute(orders_df, invoices_df)
    o_num = orders_df[:number_key] or raise "Coluna 'Número do pedido' não encontrada em Pedidos"

    orders_group = {}
    orders_df[:rows].each do |row|
      num = row[o_num].to_s.strip
      next if num.empty?

      price  = to_d(row[orders_df[:price_key]])
      coupon = to_d(row[orders_df[:coupon_key]])
      value  = price - coupon

      orders_group[num] ||= {
        "plataforma"   => row["Tipo de pedido"] || row["Site"] || row["Canal"],
        "status"       => row[orders_df[:status_key]],
        "data_criacao" => parse_time(row[orders_df[:created_at_key]]),
        "valor_total"  => 0.to_d
      }
      orders_group[num]["valor_total"] += value
    end

    invoices_group = {}
    if invoices_df[:number_key]
      invoices_df[:rows].each do |row|
        num = row[invoices_df[:number_key]].to_s.strip
        next if num.empty?

        invoices_group[num] ||= {
          "site"          => row[invoices_df[:site_key]],
          "valor_recebido"=> 0.to_d,
          "data_pagamento"=> parse_time(row[invoices_df[:paid_at_key]])
        }
        invoices_group[num]["valor_recebido"] += to_d(row[invoices_df[:received_key]])
      end
    end

    today = Date.today
    merged = orders_group.map do |num, o|
      inv = invoices_group[num]
      valor_recebido = inv ? inv["valor_recebido"] : 0.to_d
      valor_pendente = o["valor_total"] - valor_recebido
      pendente       = valor_pendente > 0.01

      dias_vencidos = if pendente && o["data_criacao"]
        (today - o["data_criacao"].to_date).to_i
      else
        0
      end

      {
        "numero_pedido"  => num,
        "plataforma"     => inv&.dig("site") || o["plataforma"],
        "valor"          => o["valor_total"].to_f.round(2),
        "dias_vencidos"  => dias_vencidos,
        "status"         => o["status"],
        "valor_recebido" => valor_recebido.to_f.round(2),
        "valor_pendente" => valor_pendente.to_f.round(2),
        "pendente"       => pendente
      }
    end

    summary = {
      total_pedidos:   merged.size,
      valor_faturado:  merged.select { |r| r["valor_recebido"] > 0 }.sum { |r| r["valor_recebido"] }.round(2),
      pedidos_pendentes: merged.count { |r| r["pendente"] },
      valor_pendente:  merged.select { |r| r["pendente"] }.sum { |r| r["valor_pendente"] }.round(2)
    }

    rows = merged.sort_by { |r| [r["pendente"] ? 0 : 1, -r["dias_vencidos"], -r["valor_pendente"]] }
    Result.new(summary:, rows:)
  end

  def self.to_d(value)
    return 0.to_d if value.nil?
    s = value.to_s.tr(".", "").tr(",", ".")
    BigDecimal(s) rescue 0.to_d
  end

  def self.parse_time(value)
    return nil if value.nil?
    Time.parse(value.to_s) rescue nil
  end
end
