require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module ResumoLivre
  class Application < Rails::Application
    config.action_controller.raise_on_missing_callback_actions = false if Rails.version >= "7.1.0"
    config.generators do |generate|
      generate.assets false
      generate.helper false
      generate.test_framework :test_unit, fixture: false
    end

    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.1

    # ===== i18n (traduções) =====
    # Idiomas aceitos e padrão
    config.i18n.available_locales = [:'pt-BR', :en]
    config.i18n.default_locale    = :'pt-BR'
    # Carregar traduções também de subpastas em config/locales
    config.i18n.load_path += Dir[Rails.root.join('config/locales/**/*.{rb,yml,yaml}')]
    # Caso falte alguma chave em pt-BR, usa en como fallback
    config.i18n.fallbacks = [:en]

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w(assets tasks))

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    config.time_zone = "America/Sao_Paulo"
    config.active_record.default_timezone = :local
  end
end
