apply "config/application.rb"
copy_file "config/brakeman.yml"
template "config/database.yml.tt", force: true
remove_file "config/secrets.yml"
copy_file "config/sidekiq.yml"

template "config/deploy.rb.tt"
template "config/deploy/production.rb.tt"
template "config/deploy/staging.rb.tt"

route 'root "home#show"'

copy_file "config/initializers/active_job.rb"
copy_file "config/initializers/draper.rb"
copy_file "config/initializers/generators.rb"
copy_file "config/initializers/inflections.rb", force: true
copy_file "config/initializers/paper_trail.rb"
copy_file "config/initializers/rollbar.rb"
copy_file "config/initializers/rotate_log.rb"
copy_file "config/initializers/secret_token.rb"
copy_file "config/initializers/secure_headers.rb"
copy_file "config/initializers/simple_form.rb"
copy_file "config/initializers/slim.rb"
copy_file "config/initializers/version.rb"
template "config/initializers/sidekiq.rb.tt"

gsub_file "config/initializers/filter_parameter_logging.rb", /\[:password\]/ do
  "%w(password secret session cookie csrf)"
end

template "config/locales/en.yml", force: true

apply "config/environments/development.rb"
apply "config/environments/production.rb"
apply "config/environments/test.rb"
template "config/environments/staging.rb.tt"

route %Q(mount Sidekiq::Web => "/sidekiq" # monitoring console)

route <<-RUBY
  namespace :audit do
    get 'versions', to: 'versions#index'
    get 'versions/:item_type/:item_id', to: 'versions#index', as: :record_versions
  end
RUBY
