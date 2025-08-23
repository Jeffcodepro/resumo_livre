# app/services/spreadsheet_parser.rb
class SpreadsheetParser
  require "roo"
  require "set"

  Result = Struct.new(:summary, :rows, keyword_init: true)

  # ------------------------------------------------------------
  # API principal
  # ------------------------------------------------------------
  def self.parse(orders_file:, invoices_file:)
    orders   = open_spreadsheet(orders_file)
    invoices = open_spreadsheet(invoices_file)

    orders_df   = normalize_orders(orders)
    invoices_df = normalize_invoices(invoices)
    compute(orders_df, invoices_df)
  end

  # ------------------------------------------------------------
  # Abrir arquivos
  # ------------------------------------------------------------
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

  # ------------------------------------------------------------
  # Helpers gerais
  # ------------------------------------------------------------
  def self.norm(str)
    s = str.to_s
    s = ActiveSupport::Inflector.transliterate(s)
    s.downcase.strip
  end

  def self.find_key(headers, *candidates)
    down = headers.map { |h| [norm(h), h] }.to_h
    candidates.each do |cand|
      key = down.keys.find { |k| k.include?(norm(cand)) }
      return down[key] if key
    end
    nil
  end

  # respeita números numéricos; lida com pt-BR e en-US
  def self.to_d(value)
    return 0.to_d if value.nil? || (value.respond_to?(:blank?) && value.blank?)
    return BigDecimal(value.to_s) if value.is_a?(Numeric)

    s = value.to_s.strip
    s = s.gsub(/[^\d,.\-]/, "") # remove R$, espaços, etc

    if s.include?(",") && s.include?(".")
      if s.rindex(",") > s.rindex(".")
        s = s.gsub(".", "").gsub(",", ".")
      else
        s = s.gsub(",", "")
      end
    elsif s.include?(",")
      s = s.gsub(",", ".")
    else
      # só ponto: já ok
    end

    BigDecimal(s)
  rescue
    0.to_d
  end

  def self.parse_time(value)
    return nil if value.nil?
    Time.parse(value.to_s) rescue nil
  end

  def self.refunded?(status)
    norm(status).include?("reembolsado por cliente")
  end

  # ------------------------------------------------------------
  # Normalizações (headers na LINHA 2)
  # ------------------------------------------------------------
  def self.normalize_orders(xlsx)
    sheet   = xlsx.sheet(0)
    header_row_index = 2
    headers = sheet.row(header_row_index).map(&:to_s)

    rows = (header_row_index + 1..sheet.last_row).map { |i| sheet.row(i) }
    data = rows.map { |r| headers.zip(r).to_h }

    # no seu arquivo, o valor total é a ÚLTIMA coluna
    last_header = headers.reverse.find { |h| h.to_s.strip != "" } || headers.last

    {
      rows: data,
      number_key:     find_key(headers, "número do pedido", "numero do pedido", "pedido", "order number"),
      status_key:     find_key(headers, "status do pedido", "status"),
      created_at_key: find_key(headers, "data e hora de criação do pedido", "data do pedido", "data de criação", "criação"),
      value_key:      last_header # SOMAR esta coluna (última)
    }
  end

  def self.normalize_invoices(xlsx)
    sheet   = xlsx.sheet(0)
    header_row_index = 2
    headers = sheet.row(header_row_index).map(&:to_s)

    rows = (header_row_index + 1..sheet.last_row).map { |i| sheet.row(i) }
    data = rows.map { |r| headers.zip(r).to_h }

    {
      rows: data,
      number_key: find_key(headers, "número do pedido", "numero do pedido", "pedido", "order number"),
      site_key:   find_key(headers, "site", "plataforma", "canal", "marketplace")
    }
  end

  # ------------------------------------------------------------
  # Cálculo
  # ------------------------------------------------------------
  def self.compute(orders_df, invoices_df)
    o_num  = orders_df[:number_key] or raise "Coluna 'Número do pedido' não encontrada em Pedidos"
    o_stat = orders_df[:status_key]
    o_date = orders_df[:created_at_key]
    o_val  = orders_df[:value_key]

    # 1) Filtrar pedidos não reembolsados (linha a linha)
    valid_rows = orders_df[:rows].select do |row|
      num = row[o_num].to_s.strip
      next false if num.empty?
      !refunded?(row[o_stat])
    end

    # RESUMO pela contagem de linhas (como você conferiu manualmente)
    total_pedidos_rows  = valid_rows.size
    valor_faturado_rows = valid_rows.sum { |r| to_d(r[o_val]) }.to_f.round(2)

    # 2) Agregar por número de pedido (para cruzamento/tabela)
    orders_by_num = {}
    valid_rows.each do |row|
      num        = row[o_num].to_s.strip
      created_at = parse_time(row[o_date])
      valor      = to_d(row[o_val])

      orders_by_num[num] ||= {
        "plataforma"   => row["Tipo de pedido"] || row["Site"] || row["Canal"],
        "status"       => row[o_stat],
        "data_criacao" => created_at,
        "valor_total"  => 0.to_d
      }
      orders_by_num[num]["valor_total"] += valor
      if created_at && orders_by_num[num]["data_criacao"]
        orders_by_num[num]["data_criacao"] = [orders_by_num[num]["data_criacao"], created_at].min
      elsif created_at
        orders_by_num[num]["data_criacao"] = created_at
      end
    end

    # 3) Faturas deduplicadas (primeira ocorrência conta)
    matched_numbers = Set.new
    if invoices_df[:number_key]
      seen = Set.new
      invoices_df[:rows].each do |row|
        num = row[invoices_df[:number_key]].to_s.strip
        next if num.empty? || seen.include?(num)
        seen << num
        matched_numbers << num
      end
    end

    # 4) Pendências (pedidos que NÃO aparecem nas faturas deduplicadas)
    order_keys   = orders_by_num.keys.to_set
    overlap      = order_keys & matched_numbers
    pending_nums = order_keys.reject { |n| matched_numbers.include?(n) }

    pedidos_pendentes = pending_nums.size
    valor_pendente    = pending_nums.sum { |n| orders_by_num[n]["valor_total"] }.to_f.round(2)

    # 5) Construir linhas (sem corte de 90d ainda)
    today = (Time.zone || Time).now.to_date
    merged = orders_by_num.map do |num, o|
      pendente = pending_nums.include?(num)
      dias_vencidos = o["data_criacao"] ? (today - o["data_criacao"].to_date).to_i : 0

      {
        "numero_pedido"  => num,
        "plataforma"     => o["plataforma"],
        "valor"          => o["valor_total"].to_f.round(2),
        "dias_vencidos"  => dias_vencidos,
        "status"         => o["status"],
        "pendente"       => pendente,
        "valor_pendente" => pendente ? o["valor_total"].to_f.round(2) : 0.0
      }
    end

    # 🔔 Alerta: se NÃO houver nenhum cruzamento, zera pendências e avisa
    swal_warning = nil
    if overlap.empty?
      pedidos_pendentes = 0
      valor_pendente    = 0.0
      merged.each do |r|
        r["pendente"]       = false
        r["valor_pendente"] = 0.0
      end
      swal_warning = "Nenhum pedido pago foi encontrado cruzando os relatórios importados. Verifique se as duas planilhas são do mesmo período/plataforma e se a coluna de número do pedido coincide."
    end

    # 6) Lista final: se não houver pendências (ou alerta), não mostramos tabela
    force_empty_list = (pedidos_pendentes == 0) || swal_warning.present?

    list = if force_empty_list
      []
    else
      # Só pedidos PENDENTES e com > 90 dias, top 10
      merged.select { |r| r["pendente"] && r["dias_vencidos"] > 90 }
            .sort_by { |r| [-r["dias_vencidos"], -r["valor_pendente"]] }
            .first(10)
    end

    summary = {
      total_pedidos:     total_pedidos_rows,
      valor_faturado:    valor_faturado_rows,
      pedidos_pendentes: pedidos_pendentes,
      valor_pendente:    valor_pendente,
      swal_warning:      swal_warning
    }

    Result.new(summary:, rows: list)
  end

  # ------------------------------------------------------------
  # Validação por cabeçalho obrigatório (para uploads)
  # Pedidos:   deve conter "Receita estimada de mercadorias"
  # Faturas:   deve conter "Valor a receber"
  # Cabeçalhos estão na LINHA 2
  # ------------------------------------------------------------
  REQUIRED_ORDERS_HEADER   = "Receita estimada de mercadorias"
  REQUIRED_INVOICES_HEADER = "Valor a receber"

  def self.headers_from(uploaded, header_row_index: 2)
    xlsx    = open_spreadsheet(uploaded)
    sheet   = xlsx.sheet(0)
    headers = sheet.row(header_row_index).map(&:to_s)
    headers
  end

  def self.contains_header?(headers, wanted)
    target = norm(wanted)
    headers.any? { |h| norm(h).include?(target) }
  end

  # Deduz o "tipo" do arquivo a partir dos cabeçalhos obrigatórios
  def self.peek_kind(uploaded)
    headers = headers_from(uploaded)
    has_orders   = contains_header?(headers, REQUIRED_ORDERS_HEADER)
    has_invoices = contains_header?(headers, REQUIRED_INVOICES_HEADER)

    kind =
      if has_orders && !has_invoices
        :orders
      elsif has_invoices && !has_orders
        :invoices
      elsif has_orders && has_invoices
        :ambiguous
      else
        :unknown
      end

    {
      kind: kind,
      headers: headers,
      header_count: headers.reject { |h| h.to_s.strip.empty? }.size,
      has_orders: has_orders,
      has_invoices: has_invoices
    }
  end

  # Valida os dois uploads: orders_file DEVE ter 'Receita estimada de mercadorias'
  # e invoices_file DEVE ter 'Valor a receber'
  def self.validate_uploads(orders_file:, invoices_file:)
    o = peek_kind(orders_file)
    i = peek_kind(invoices_file)

    ok = (o[:kind] == :orders) && (i[:kind] == :invoices)

    errors = []
    errors << "Arquivo de **Pedidos** deve conter a coluna “#{REQUIRED_ORDERS_HEADER}”."   unless o[:has_orders]
    errors << "Arquivo de **Faturas** deve conter a coluna “#{REQUIRED_INVOICES_HEADER}”." unless i[:has_invoices]
    errors << "O arquivo de **Pedidos** parece ambíguo (contém também coluna de faturas)."  if o[:kind] == :ambiguous
    errors << "O arquivo de **Faturas** parece ambíguo (contém também coluna de pedidos)."  if i[:kind] == :ambiguous

    { ok: ok, orders: o, invoices: i, errors: errors }
  end
end
