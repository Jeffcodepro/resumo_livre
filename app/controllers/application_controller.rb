class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception

  before_action :configure_permitted_parameters, if: :devise_controller?

  # app/controllers/application_controller.rb
  def after_sign_in_path_for(resource)
    resource.respond_to?(:admin?) && resource.admin? ? admin_users_path : super
  end


  protected

  def configure_permitted_parameters
    # Cadastro (sign up): permite os campos extras
    devise_parameter_sanitizer.permit(
      :sign_up,
      keys: %i[full_name trade_name cnpj whatsapp]
    )

    # Edição de conta (account update): NÃO permite mudar full_name, trade_name, cnpj e email
    # Só deixa editar whatsapp e senha
    devise_parameter_sanitizer.permit(
      :account_update,
      keys: %i[whatsapp password password_confirmation current_password]
    )
  end
end
