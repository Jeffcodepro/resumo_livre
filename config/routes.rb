Rails.application.routes.draw do
  get 'dashboards/index'
  get 'welcomes/index'
  devise_for :users
  # root to: "pages#home"
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # Dashboards (plural)
  get  "dashboards",        to: "dashboards#index"
  post "dashboards/upload", to: "dashboards#upload"

  # Root:
  authenticated :user do
    root "dashboards#index", as: :authenticated_root
  end

  unauthenticated do
    devise_scope :user do
      root "devise/sessions#new", as: :unauthenticated_root
    end
  end
end
