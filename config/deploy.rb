require 'bundler/capistrano'
require 'capistrano-unicorn'
require 'sidekiq'
require 'sidekiq/capistrano'
require 'dotenv/capistrano'

set :default_environment, {
  'PATH' => '/usr/local/rbenv/shims:/usr/local/rbenv/bin:$PATH',
}

set :application, "discourse"

set :repository,  "git://github.com/tristil/discourse.git"
set :scm, :git

if ENV["DEPLOY_SERVER"]
  set(:host) { ENV["DEPLOY_SERVER"] }
  set(:user) { ENV["DEPLOY_USER"] }
else
  set(:host) { Capistrano::CLI.ui.ask "SSH server: " }
  set(:user) { Capistrano::CLI.ui.ask "SSH username: " }
end

role :web, host # Your HTTP server, Apache/etc
role :app, host, :primary => true # This may be the same as your `Web` server
role :db,  host, :primary => true # This is where Rails migrations will run

ssh_options[:forward_agent] = true
ssh_options[:keys] = %w('~/.ssh/id_rsa.pub')
default_run_options[:pty] = true

set :use_sudo, false
set :deploy_to, "/home/#{user}/production-sites/discourse"
set :deploy_via, :remote_cache
set :rails_env, :production

# Do backup
task :backup do
  run "pg_dump discourse > /tmp/discourse.sql"
end

task :set_credentials do
  upload("#{File.expand_path(File.dirname(__FILE__))}/../.env",
         "#{shared_path}/.env")
end

namespace :unicorn do
  task :make_sockets_dir do
    run "mkdir -p #{shared_path}/sockets"
    run "ln -s #{shared_path}/sockets #{latest_release}/tmp/sockets"
  end
end

namespace :rails do
  desc "Remote console"
  task :console, :roles => :app do
    run_interactively "bundle exec rails console #{rails_env}"
  end

  desc "Remote dbconsole"
  task :dbconsole, :roles => :app do
    run_interactively "bundle exec rails dbconsole #{rails_env}"
  end
end

namespace :remote do
  namespace :rake do
    desc 'Run a specified rake task'
    task :default, roles: :app, only: { primary: true } do
      run(rake_cmd)
      exit
    end

    desc 'Run a specified rake task on all servers'
    task :all, roles: :app do
      run(rake_cmd)
      exit
    end

    def rake_cmd
      "cd #{current_path} && bundle exec rake #{task_names_from_args}"
    end

    def task_names_from_args
      (ARGV - [current_task.fully_qualified_name].map(&:to_s)).join
    end
  end
end

def run_interactively(command, server=nil)
  server ||= find_servers_for_task(current_task).first
  exec %Q(ssh #{server.host} -t 'sudo su - #{application} -c "cd #{current_path} && #{command}"')
end

before "deploy:migrate", "backup"

after "deploy:update", "deploy:cleanup"
after "deploy:update", "deploy:migrate"
before "deploy:finalize_update", "set_credentials"
after 'deploy:finalize_update', 'unicorn:make_sockets_dir'

after 'deploy:start', 'unicorn:start'
after 'deploy:restart', 'unicorn:restart'
after 'deploy:reload', 'unicorn:reload'
after 'deploy:stop', 'unicorn:stop'
