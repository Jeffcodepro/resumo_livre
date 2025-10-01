require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module ResumoLivre
  class Application < Rails::Application
    # Para Rails 7.1+: evita erro com callbacks ausentes em controllers
    if Gem::Version.new(Rails.version) >= Gem::Version.new("7.1.0")
      config.action_controller.raise_on_missing_callback_actions = false
    end

    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.1

    # Generators
    config.generators do |g|
      g.assets false
      g.helper false
      g.test_framework :test_unit, fixture: false
    end

    # ===== i18n (traduções) =====
    config.i18n.available_locales = [:'pt-BR', :en]
    config.i18n.default_locale    = :'pt-BR'
    config.i18n.enforce_available_locales = true
    # Carregar traduções também de subpastas em config/locales
    config.i18n.load_path += Dir[Rails.root.join('config/locales/**/*.{rb,yml,yaml}')]
    # Fallbacks: tenta pt-BR e só então en
    config.i18n.fallbacks = [:'pt-BR', :en]

    # Timezone
    config.time_zone = "America/Sao_Paulo"
    config.active_record.default_timezone = :local

    # Autoload de libs (Zeitwerk)
    # Adicione outros diretórios aqui conforme necessidade
    config.autoload_lib(ignore: %w[assets tasks])
  end
end
