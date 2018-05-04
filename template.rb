# frozen_string_literal: true
RAILS_REQUIREMENT = "~> 5.1.0"

# Some generators and initialisers will require this to be set
ENV["RAILS_SECRET_KEY_BASE"] ||= SecureRandom.hex(64)

def apply_template!
  assert_minimum_rails_version
  assert_valid_options
  assert_postgresql
  add_template_repository_to_source_path

  template "Gemfile.tt", force: true

  template "PROVISIONING.md.tt"
  template "README.md.tt", force: true
  remove_file "README.rdoc"

  template "example.env.tt"
  create_file ".env.production"
  create_file ".env.test"
  copy_file "gitignore", ".gitignore", force: true
  Dir.mkdir(".circleci")
  copy_file "circleci.yml", ".circleci/config.yml"
  copy_file "overcommit.yml", ".overcommit.yml"
  template "ruby-version.tt", ".ruby-version"
  copy_file "simplecov", ".simplecov"
  copy_file "rspec", ".rspec"

  copy_file "Capfile"
  copy_file "Guardfile"

  apply "config.ru.rb"
  apply "app/template.rb"
  apply "bin/template.rb"
  apply "config/template.rb"
  apply "doc/template.rb"
  apply "lib/template.rb"
  apply "public/template.rb"
  apply "spec/template.rb"

  migration "db/migrate/create_versions.rb"

  apply "variants/crm/template.rb"
  apply "variants/semantic-ui/template.rb" if apply_semantic_ui?
  apply "variants/security/template.rb" if apply_security?
  apply "variants/reports/template.rb" if apply_reports?

  git :init unless preexisting_git_repo?
  empty_directory ".git/safe"

  run_with_clean_bundler_env "bin/setup"
  generate_spring_binstubs

  binstubs = %w(
    annotate brakeman bundler-audit capistrano guard rubocop sidekiq
    terminal-notifier
  )
  run_with_clean_bundler_env "bundle binstubs #{binstubs.join(' ')}"


  template "rubocop.yml.tt", ".rubocop.yml"
  copy_file "rubocop.github.yml", ".rubocop.github.yml"
  copy_file "rubocop.rails.yml", ".rubocop.rails.yml"
  run_rubocop_autocorrections

  if empty_git_repo?
    git add: "-A ."
    git commit: "-n -m 'Set up project'"
    if git_repo_specified?
      git remote: "add origin #{git_repo_url.shellescape}"
    end
  end
end

require "fileutils"
require "shellwords"

# Add this template directory to source_paths so that Thor actions like
# copy_file and template resolve against our source files. If this file was
# invoked remotely via HTTP, that means the files are not present locally.
# In that case, use `git clone` to download them to a local temporary dir.
def add_template_repository_to_source_path
  if __FILE__ =~ %r{\Ahttps?://}
    require "tmpdir"
    source_paths.unshift(tempdir = Dir.mktmpdir("rails-template-"))
    at_exit { FileUtils.remove_entry(tempdir) }
    git clone: [
      "--quiet",
      "https://github.com/WebGents/rails-template.git",
      tempdir
    ].map(&:shellescape).join(" ")
  else
    source_paths.unshift(File.dirname(__FILE__))
  end
end

def assert_minimum_rails_version
  requirement = Gem::Requirement.new(RAILS_REQUIREMENT)
  rails_version = Gem::Version.new(Rails::VERSION::STRING)
  return if requirement.satisfied_by?(rails_version)

  prompt = "This template requires Rails #{RAILS_REQUIREMENT}. "\
           "You are using #{rails_version}. Continue anyway?"
  exit 1 if no?(prompt)
end

# Bail out if user has passed in contradictory generator options.
def assert_valid_options
  valid_options = {
    skip_gemfile: false,
    skip_bundle: false,
    skip_git: false,
    skip_test_unit: true,
    edge: false
  }
  valid_options.each do |key, expected|
    next unless options.key?(key)
    actual = options[key]
    unless actual == expected
      fail Rails::Generators::Error, "Unsupported option: #{key}=#{actual}"
    end
  end
end

def assert_postgresql
  return if IO.read("Gemfile") =~ /^\s*gem ['"]pg['"]/
  fail Rails::Generators::Error,
       "This template requires PostgreSQL, "\
       "but the pg gem isn't present in your Gemfile."
end

# Mimic the convention used by capistrano-mb in order to generate
# accurate deployment documentation.
def capistrano_app_name
  app_name.gsub(/[^a-zA-Z0-9_]/, "_")
end

def git_repo_url
  @git_repo_url ||=
    ask_with_default("What is the git remote URL for this project?", :blue, "skip")
end

def production_hostname
  @production_hostname ||=
    ask_with_default("Production hostname?", :blue, "example.com")
end

def staging_hostname
  @staging_hostname ||=
    ask_with_default("Staging hostname?", :blue, "staging.example.com")
end

def gemfile_requirement(name)
  @original_gemfile ||= IO.read("Gemfile")
  req = @original_gemfile[/gem\s+['"]#{name}['"]\s*(,[><~= \t\d\.\w'"]*)?.*$/, 1]
  req && req.gsub("'", %(")).strip.sub(/^,\s*"/, ', "')
end

def ask_with_default(question, color, default)
  return default unless $stdin.tty?
  return default if ENV["HEADLESS"] == "1"
  question = (question.split("?") << " [#{default}]?").join
  answer = ask(question, color)
  answer.to_s.strip.empty? ? default : answer
end

def yes?(question, default = "yes")
  ask_with_default(question, :blue, default) =~ /^y(es)?/i
end

def git_repo_specified?
  git_repo_url != "skip" && !git_repo_url.strip.empty?
end

def preexisting_git_repo?
  @preexisting_git_repo ||= (File.exist?(".git") || :nope)
  @preexisting_git_repo == true
end

def empty_git_repo?
  return @empty_git_repo if defined?(@empty_git_repo)
  @empty_git_repo = !system("git rev-list -n 1 --all &> /dev/null")
end

def apply_semantic_ui?
  yes?("Use Semantic UI gems, layouts, views, etc.?")
end

def apply_security?
  yes?("Install Devise and Pundit for authentication and authorisation?")
end

def apply_reports?
  yes?("Add reporting engine to generate charts from queries?")
end

def run_with_clean_bundler_env(cmd)
  return run(cmd) unless defined?(Bundler)
  Bundler.with_clean_env { run(cmd) }
end

def run_rubocop_autocorrections
  run_with_clean_bundler_env "bin/rubocop -a --fail-level A > /dev/null"
end

def migration(filename)
  @last_timeref ||= Time.now.utc
  timeref ||= @last_timeref
  timeref += 1 if @last_timeref >= timeref

  fn = File.basename(filename).sub(/^\d+_?/, "")
  stamp = timeref.strftime("%Y%m%d%H%M%S")
  copy_file filename, File.join("db", "migrate", "#{stamp}_#{fn}")
  @last_timeref = timeref
end

# Redefine route to
# 1) Add routes to the bottom of the route file
# 2) More cleanly support multi-line routes
def route(str)
  str = str.chomp
  str = "  #{str}" unless str =~ /\n/
  insert_into_file "config/routes.rb", "#{str}\n", before: /^end\n/
end

apply_template!
