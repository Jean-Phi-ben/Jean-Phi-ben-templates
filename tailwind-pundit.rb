run "if uname | grep -q 'Darwin'; then pgrep spring | xargs kill -9; fi"

# 1. Configuration des Gems
########################################
gem "propshaft"
gem "tailwindcss-rails"

inject_into_file "Gemfile", before: "group :development, :test do" do
  <<~RUBY
    gem "pundit"
    gem "omniauth-google-oauth2"
    gem "omniauth-facebook"
    gem "omniauth-apple"
    gem "dotenv-rails"
  RUBY
end

# 2. Layout & Fluidité
########################################
file "app/views/layouts/_head_scripts.html.erb", "<%= javascript_importmap_tags %>"
gsub_file "app/views/layouts/application.html.erb", '<%= javascript_importmap_tags %>', '<%= render "layouts/head_scripts" %>'
gsub_file "app/views/layouts/application.html.erb", '<%= yield %>', <<~HTML
  <div id="main-content" class="container mx-auto px-4 py-8">
    <%= yield %>
  </div>
HTML

# 3. Installation et Génération (Tout se passe ici)
########################################
after_bundle do
  run "bundle exec rails tailwindcss:install"
  generate "authentication"
  generate "pundit:install"
  
  # --- MODIFICATION DU MODÈLE USER ---
  # Ajout de admin? et de la logique OAuth from_omniauth
  file "app/models/user.rb", <<~RUBY, force: true
    class User < ApplicationRecord
      has_secure_password
      has_many :sessions, dependent: :destroy

      validates :email_address, presence: true, uniqueness: true

      def admin?
        admin == true
      end

      def self.from_omniauth(auth)
        where(email_address: auth.info.email).first_or_initialize do |user|
          user.password = SecureRandom.hex(16) if user.new_record?
          # Optionnel: user.name = auth.info.name
        end
      end
    end
  RUBY

  # --- CONFIGURATION DE LA MIGRATION ---
  # On regroupe admin et les champs OAuth (provider, uid)
  generate :migration, "AddAdminAndOauthToUsers", "admin:boolean", "provider:string", "uid:string"
  migration_file = Dir.glob("db/migrate/*_add_admin_and_oauth_to_users.rb").first
  if migration_file
    gsub_file migration_file, /t.boolean :admin/, "t.boolean :admin, default: false"
    inject_into_file migration_file, after: "t.string :uid" do
      "\n    add_index :users, [:provider, :uid], unique: true"
    end
  end

  # --- CONFIGURATION DE L'APPLICATION CONTROLLER ---
  file "app/controllers/application_controller.rb", <<~RUBY, force: true
    class ApplicationController < ActionController::Base
      include Authentication
      include Pundit::Authorization

      rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

      private

      def user_not_authorized
        flash[:alert] = "Vous n'avez pas l'autorisation d'accéder à cette page."
        redirect_back_or_to root_path
      end
    end
  RUBY

  # --- SESSIONS CONTROLLER (Ajout du Callback OAuth) ---
  inject_into_file "app/controllers/sessions_controller.rb", after: "class SessionsController < ApplicationController" do
    <<~RUBY

      # Gère le retour de Google/Facebook/Apple
      def create_from_oauth
        auth = request.env['omniauth.auth']
        @user = User.from_omniauth(auth)

        if @user.save
          start_new_session_for @user
          redirect_to root_path, notice: "Connexion réussie via \#{auth.provider} !"
        else
          redirect_to new_session_path, alert: "Échec de la connexion sociale."
        end
      end
    RUBY
  end

  # --- LOGIQUE ADMIN & POLICIES ---
  generate :controller, "admin/dashboard", "index", "--no-test-framework"
  
  file "app/policies/admin_policy.rb", <<~RUBY
    class AdminPolicy < ApplicationPolicy
      def index?
        user&.admin?
      end
    end
  RUBY

  file "app/controllers/admin/dashboard_controller.rb", <<~RUBY, force: true
    class Admin::DashboardController < ApplicationController
      def index
        authorize :admin, :index?
      end
    end
  RUBY

  # --- CONFIGURATION OMNIAUTH ---
  file "config/initializers/omniauth.rb", <<~RUBY
    OmniAuth.config.allowed_request_methods = [:post, :get]

    Rails.application.config.middleware.use OmniAuth::Builder do
      provider :google_oauth2, ENV['GOOGLE_CLIENT_ID'], ENV['GOOGLE_CLIENT_SECRET']
      provider :facebook, ENV['FACEBOOK_APP_ID'], ENV['FACEBOOK_APP_SECRET']
      provider :apple, ENV['APPLE_CLIENT_ID'], ENV['APPLE_TEAM_ID'], ENV['APPLE_KEY_ID'], ENV['APPLE_PRIVATE_KEY']
    end
  RUBY

  # --- VUES (Boutons OAuth) ---
  append_file "app/views/sessions/new.html.erb" do
    <<~HTML
      <div class="mt-6 border-t pt-6">
        <p class="text-center text-sm text-gray-500 mb-4 font-sans">Ou se connecter avec</p>
        <div class="flex flex-col gap-3">
          <%= button_to "Continuer avec Google", "/auth/google_oauth2", data: { turbo: false }, class: "w-full py-2 px-4 border border-gray-300 rounded-md shadow-sm bg-white text-sm font-medium text-gray-700 hover:bg-gray-50 flex justify-center items-center cursor-pointer" %>
          <%= button_to "Continuer avec Apple", "/auth/apple", data: { turbo: false }, class: "w-full py-2 px-4 border border-gray-300 rounded-md shadow-sm bg-black text-white text-sm font-medium hover:bg-gray-800 flex justify-center items-center cursor-pointer" %>
        </div>
      </div>
    HTML
  end

  # Routes
  route "get '/auth/:provider/callback', to: 'sessions#create_from_oauth'"
  route "namespace :admin do root to: 'dashboard#index' end"
  route "root to: 'pages#home'"
  generate :controller, "pages", "home", "--skip-routes"

  # Seeds
  file "db/seeds.rb", <<~RUBY, force: true
    User.destroy_all
    User.create!(email_address: "admin@prestige.com", password: "password123", admin: true)
    User.create!(email_address: "client@prestige.com", password: "password123", admin: false)
    puts "Base de données initialisée !"
  RUBY

  # --- FINALISATION .ENV ---
  file ".env", <<~TEXT
    GOOGLE_CLIENT_ID=votre_id
    GOOGLE_CLIENT_SECRET=votre_secret
    FACEBOOK_APP_ID=votre_id
    FACEBOOK_APP_SECRET=votre_secret
  TEXT

  # Finalisation DB
  rails_command "db:prepare"
  rails_command "db:seed"

  git :init
  git add: "."
  git commit: "-m 'Setup Prestige App: Auth, OAuth, Pundit, Admin'"
end
