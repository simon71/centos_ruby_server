# -*- mode: ruby -*-
# vi: set ft=ruby :

# All Vagrant configuration is done below. The "2" in Vagrant.configure
# configures the configuration version (we support older styles for
# backwards compatibility). Please don't change it unless you know what
# you're doing.
Vagrant.configure("2") do |config|

  config.vm.box = "centos/7"

  if ENV['init_env']
    $init_env = ENV['init_env']
  else
    puts "Environment variable: 'init_env' is not set, defaulting to 'dev'"
    $init_env = 'dev'
  end

  if ENV['init_role']
    $init_amp = ENV['init_role']
  else
    puts "Environment variable: init_role is not set, defaulting to 'ruby_server'"
    $init_role = 'ruby_server'
  end

  args = "--role #{$init_role} --environment #{$init_env}"

  config.vm.provision :shell, :path => 'init.sh', :args => args
end
