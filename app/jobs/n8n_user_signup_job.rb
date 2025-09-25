require "net/http"
require "uri"
require "json"
require "openssl"
class N8nUserSignupJob < ApplicationJob
  queue_as :default

  # Re-tenta com backoff se der erro temporário
  retry_on(StandardError, attempts: 5, wait: :exponentially_longer)

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    webhook_url = ENV["N8N_WEBHOOK_URL"] || Rails.application.credentials.dig(:n8n, :webhook_url)
    raise "N8N_WEBHOOK_URL não configurada" if webhook_url.blank?

    uri  = URI.parse(webhook_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl     = (uri.scheme == "https")
    http.open_timeout = 5   # opcional
    http.read_timeout = 10  # opcional

    payload = {
      full_name:  user.full_name,
      trade_name: user.trade_name,
      whatsapp:   user.whatsapp,
      email:      user.email
    }.compact

    request = Net::HTTP::Post.new(uri.request_uri)
    request["Content-Type"] = "application/json"
    request["X-Source"]     = "resumo_livre" # só para rastrear a origem, se quiser
    request.body = JSON.generate(payload)

    response = http.request(request)
    raise "n8n webhook falhou: #{response.code} #{response.body}" unless response.is_a?(Net::HTTPSuccess)
  end
end
