module Admin
  class UsersController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_admin!

    def index
      @users = User.order(created_at: :desc)
    end

    def approve_all_pending
      count = User.pending_approval.update_all(
        approved: true,
        approved_at: Time.current,
        updated_at: Time.current
      )
      redirect_to admin_users_path, notice: "#{count} usuários aprovados."
    end

    def approve;   user.update!(approved: true,  approved_at: Time.current); redirect_back fallback_location: admin_users_path, notice: "Usuário aprovado."; end
    def block;     user.update!(blocked: true);   redirect_back fallback_location: admin_users_path, notice: "Usuário bloqueado."; end
    def unblock;   user.update!(blocked: false);  redirect_back fallback_location: admin_users_path, notice: "Usuário desbloqueado."; end
    def mark_paid; user.update!(paid: true);      redirect_back fallback_location: admin_users_path, notice: "Pagamento marcado como efetuado."; end
    def mark_unpaid; user.update!(paid: false);   redirect_back fallback_location: admin_users_path, notice: "Pagamento marcado como pendente."; end

    private
    def user; @user ||= User.find(params[:id]); end
    def ensure_admin!; redirect_to(root_path, alert: "Acesso negado") unless current_user&.admin?; end
  end
end
