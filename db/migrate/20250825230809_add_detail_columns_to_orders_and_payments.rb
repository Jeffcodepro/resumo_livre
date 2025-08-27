class AddDetailColumnsToOrdersAndPayments < ActiveRecord::Migration[7.1]
  def change
    change_table :orders, bulk: true do |t|
      # já existiam: user_id, order_number, platform, status, order_date, value_total, raw, created_at, updated_at
      # novos campos (tipos escolhidos com base nos nomes):
      t.string  :order_type                                 # Tipo de pedido
      t.string  :exchange_order_number                      # Pedido de troca
      t.string  :shipping_mode                              # Modo de envio
      t.boolean :instado, default: false                    # Instado ou não
      t.boolean :is_lost, default: false                    # Está perdido
      t.boolean :should_stay, default: false                # se deve ficar
      t.boolean :has_issues, default: false                 # Pedido com problemas
      t.text    :product_name                               # Nome do produto (pode ter mais de um -> agrego)
      t.string  :product_number                             # Número do produto
      t.string  :variation                                  # Variação
      t.string  :seller_sku                                 # SKU do vendedor
      t.string  :shein_sku                                  # SHEIN-SKU
      t.string  :skc                                        # SKC
      t.string  :item_id                                    # ID do item
      t.string  :product_status                             # Status do produto
      t.string  :inventory_id                               # ID do inventário
      t.string  :exchange_code                              # Código de troca
      t.text    :exchange_reason                            # Motivo da substituição
      t.string  :exchange_product_id                        # ID do produto a ser trocado
      t.boolean :is_blocked, default: false                 # Bloqueado ou não
      t.datetime :label_print_deadline                      # Prazo para imprimir etiqueta
      t.datetime :collection_required_at                    # Data e hora requeridas para coleta
      t.datetime :collected_at                              # Coletado em
      t.string  :tracking_code                              # Código de rastreio
      t.string  :last_mile_provider                         # Fornecedor de logística de última milha
      t.boolean :merchant_package, default: false           # Pacote do comerciante
      t.boolean :passes_through_warehouse, default: false   # Se o pacote passa pelo armazém
      t.string  :first_mile_provider                        # Fornecedor de logística de primeira mão
      t.string  :first_mile_waybill                         # Número da carta de porte de primeira viagem
      t.string  :seller_currency                            # Moeda do vendedor
      t.decimal :product_price, precision: 12, scale: 2     # Preço do produto
      t.decimal :coupon_value, precision: 12, scale: 2      # Valor do cupom
      t.decimal :store_campaign_discount, precision: 12, scale: 2 # Desconto de campanha da loja
      t.decimal :commission, precision: 12, scale: 2        # Comissão
    end

    change_table :payments, bulk: true do |t|
      # já existiam: user_id, order_number, platform, amount, paid_at, raw, created_at, updated_at
      t.string  :site                                       # site
      t.string  :related_order_number                       # Número de pedido relacionado
      t.string  :invoice_number                             # Número de fatura
      t.date    :seller_delivery_date                       # Data de entrega do vendedor
      t.datetime :delivered_at                              # Data e hora de entrega
      t.string  :invoice_type                               # Tipo de fatura
      t.decimal :product_price_summary, precision: 12, scale: 2  # Resumo de preços de produtos
      t.decimal :campaign_discount, precision: 12, scale: 2       # Desconto da campanha
      t.decimal :store_coupon_value, precision: 12, scale: 2      # Valor do cupom da loja
      t.decimal :payment_commission, precision: 12, scale: 2      # Comissão
      t.decimal :freight_intermediation_fee, precision: 12, scale: 2     # Taxa de intermediação de frete
      t.decimal :storage_operation_fee, precision: 12, scale: 2          # Taxa de operação de estocagem
      t.decimal :return_processing_fee, precision: 12, scale: 2          # Taxa de processamento de devolução
      # t.decimal :amount já existe (Valor a receber)
      # t.datetime :paid_at já existe (Data de pagamento)
    end

    # índices úteis (opcional)
    add_index :orders,   :order_type unless index_exists?(:orders, :order_type)
    add_index :payments, :invoice_number unless index_exists?(:payments, :invoice_number)
  end
end
