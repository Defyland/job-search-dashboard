Rails.application.routes.draw do
  resource :session, only: %i[new create destroy]
  resources :jobs, only: %i[index show] do
    patch :mark, on: :member
  end
  resources :search_profiles, except: :show do
    collection do
      post :compile
    end

    member do
      patch :compile
    end
  end
  resources :search_runs, only: %i[index show create]
  resources :sources, only: %i[index edit update]

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  namespace :api do
    namespace :v1 do
      resources :job_ingestions, only: :create
      resources :codex_fallback_sources, only: :index
    end
  end

  root "jobs#index"
end
