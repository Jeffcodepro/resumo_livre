Rails.application.routes.draw do
  devise_for :users

  # Healthcheck
  get "up" => "rails/health#show", as: :rails_health_check

  # Dashboards
  get  "dashboards",              to: "dashboards#index",        as: :dashboards
  post "dashboards/upload",       to: "dashboards#upload",       as: :dashboards_upload
  post "dashboards/load_from_db", to: "dashboards#load_from_db", as: :dashboards_load_from_db
  # (opcional futuro)
  get  "dashboards/export_pdf",   to: "dashboards#export_pdf",   as: :dashboards_export_pdf

  # config/routes.rb
  resources :dashboards, only: [:index] do
    collection do
      get :load_from_db
      get :export_pdf
      post :upload
    end
  end

  # Roots
  authenticated :user do
    root "dashboards#index", as: :authenticated_root
  end

  unauthenticated do
    devise_scope :user do
      root "devise/sessions#new", as: :unauthenticated_root
    end
  end
end
