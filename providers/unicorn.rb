#
# Author:: Noah Kantrowitz <noah@opscode.com>
# Cookbook Name:: application_ruby
# Provider:: unicorn
#
# Copyright:: 2011-2012, Opscode, Inc <legal@opscode.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include Chef::Mixin::LanguageIncludeRecipe

action :before_compile do

  if new_resource.bundler.nil?
    rails_resource = new_resource.application.sub_resources.select{|res| res.type == :rails}.first
    new_resource.bundler rails_resource && rails_resource.bundler
  end

  unless new_resource.bundler
    include_recipe "unicorn"
  end

  if !new_resource.restart_command
    case node['platform']
    when "smartos"
      new_resource.restart_command "svcadm restart unicorn-#{new_resource.name}"
    else
      new_resource.restart_command "/etc/init.d/#{new_resource.name} hup"
    end
  end

end

action :before_deploy do
end

action :before_migrate do
end

action :before_symlink do
end

action :before_restart do

  new_resource = @new_resource

  unicorn_config "/etc/unicorn/#{new_resource.name}.rb" do
    listen({ new_resource.port => new_resource.options })
    working_directory ::File.join(new_resource.path, 'current')
    stderr_path new_resource.stderr_path
    worker_timeout new_resource.worker_timeout
    preload_app new_resource.preload_app
    worker_processes new_resource.worker_processes
    before_fork new_resource.before_fork
    after_fork new_resource.after_fork
  end

  case node['platform']
  when "smartos"
    app_path      = ::File.join(new_resource.path, 'current')
    unicorn_path  = new_resource.path_extensions + ["/opt/local/bin:/opt/local/sbin:/usr/bin:/usr/sbin"]

    smf "unicorn-#{new_resource.name}" do
      credentials_user new_resource.owner

      start_command "bundle exec unicorn -c /etc/unicorn/#{new_resource.name}.rb -E %{config/rails_env} -D"
      start_timeout 90
      stop_command ":kill"
      stop_timeout 30
      restart_command ":kill -SIGUSR2"
      restart_timeout 120
      environment(
        "HOME" => "/home/#{new_resource.owner}",
        "PATH" => unicorn_path.join(':')
      )

      # If you get into a case where the unicorn master is frequently reaping
      # workers, SMF may notice and put the service into maintenance mode.
      # Instead, we tell SMF to ignore core dumps and signals to children.
      ignore ["core","signal"]

      property_groups({
        "config" => {
          "rails_env" => new_resource.environment_name
        }
      })

      working_directory app_path
      action :install
    end
  else
    runit_service new_resource.name do
      template_name 'unicorn'
      owner new_resource.owner if new_resource.owner 
      group new_resource.group if new_resource.group

      cookbook 'application_ruby'
      options(
        :app => new_resource,
        :rails_env => new_resource.environment_name,
        :smells_like_rack => ::File.exists?(::File.join(new_resource.path, "current", "config.ru"))
      )
      run_restart false
    end
  end

end

action :after_restart do
end
