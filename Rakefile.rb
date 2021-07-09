# Provide a Rake-based interface for building & provisioning 
# a dev environment based on Ansible & Vagrant.  
# 
# For Rake, cf.:
# - https://github.com/ruby/rake
# - https://martinfowler.com/articles/rake.html
# 
# Make sure to have Rake installed:
# $ gem install rake
# 
# Make sure to have all dependencies installed:
# $ gem install bundler
# $ bundle install
# $ rake ansible:dependencies

#
# Dependencies
# 

# stdlib
require 'yaml'
require 'json'
require 'pp'
require 'erb'
require 'ostruct'

# Gems
# 
# For Rails' active support extensions, cf.:
# - https://guides.rubyonrails.org/active_support_core_extensions.html
require 'rubygems'
require 'bundler/setup'
require 'rake'
require 'awesome_print'
require 'active_support/core_ext/hash/keys'
require 'active_support/configurable'

# Extend Rake for a customized handling of command line arguments
#
# Cf. https://github.com/ruby/rake/blob/master/lib/rake/application.rb
module Rake
  class Application 
    def handle_argv

      if ARGV.include?('--')
        # If options are present in ARGV, remove everything
        # that's not an option (i.e., remove everything up 
        # to a begin-of-options marker).  
        ARGV.slice!(..ARGV.find_index('--'))
        # Remove options from top level tasks 
        @top_level_tasks = @top_level_tasks - ARGV
      else
        # Clear ARGV if no options are present.
        #
        # This does not affect Rake, since Rake operates
        # on a duplicate of ARGV.
        ARGV.slice!(0..)
      end
    end
  end
end

Rake.application.handle_argv

#
# Helper functions
#

# Read basic config. 
def get_config(fn)
  YAML.load_file(fn).symbolize_keys
end

# Write ERB template files with given data to given destination.
# 
# Used here to write Ansible inventory & config files.
# 
# Cf.:
# - https://docs.ansible.com/ansible/latest/user_guide/intro_inventory.html
# - https://www.stuartellis.name/articles/erb/
# - https://www.rubyguides.com/2018/11/ruby-erb-haml-slim/
# - https://blog.appsignal.com/2019/01/08/ruby-magic-bindings-and-lexical-scope.html
def write_template(template, target, config)

  File.write(

    target,
    ERB.new(File.read(template)).result(binding)
  )
end

# Whether or not to generate, or update, Ansible inventory & confg files.
def generate_ansible_files
  
  # Helper to decide whether or not to generate/update a given file
  update = Proc.new do |fn, mtime|
    !(File.exists?(fn) && File.stat(fn).mtime >= mtime)
    true
  end

  Dir.glob('./templates/ansible.*').each do |template|

    # Get a template's last modified date
    source_mtime = File.stat(template).mtime 

    # Get a destination's potential file name & path 
    target_file  = File.basename(template).split('.').slice(1...-1).join('.') 
    target_paths = target_file.start_with?('inventory') ? ['inventory/'] : ['', 'plays/*/']

    # Walk destination path(s)
    target_paths.each do |target_path|
      
      Dir.glob("./ansible/#{target_path}").each do |path|

        # Build a potential real path
        fn = File.join(File.expand_path(path), target_file)    

        # Yield source (template file) & target if the target needs to be generated/updated
        yield template, fn if update.call(fn, source_mtime) && block_given?
      end
    end
  end
end

# Generate Ansible runtime config, meant to be passed on to Ansible via shell:
# 
def write_ansible_runtime_vars(config, fn_config, fn_ansible_runtime_config)

  exists  = File.exists?(fn_ansible_runtime_config)
  current = exists && File.stat(fn_config).mtime <= File.stat(fn_ansible_runtime_config).mtime

  # return if exists && current
  
  config.core[:base_dir].merge!({
    
    "root" =>  File.expand_path(config.core[:base_dir]['root'])
  })
  
  File.write(fn_ansible_runtime_config, JSON.pretty_generate({custom: config.core}))
end

# Get Ansible limits (hosts, sites).
#
# Limits can be set in core.config.yml, or passed via commandline, e.g.:
# $ rake some:task -- hostnames  
# $ rake some:task -- hostname sitename  
# $ rake some:task -- hostname sitenames  
def set_limits(config)
  
  limits = {hosts: nil, sites: nil}
  
  if config.core.has_key?(:limit)
    limits[:hosts] = config.core[:limit]['hosts']
  end
  
  options = config.ARGV
  
  if options && options.count > 0
    limits[:hosts] = options.first.split(',') 
    limits[:sites] = options.last.split(',') if limits[:hosts].count == 1 && options.count == 2
  end
  
  limits
end

# Get commandline-ready limits
def get_limits(config)
  
  limits = {
    
    hosts: ('--limit ' + config[:limits][:hosts].join(':') if config[:limits][:hosts]), 
    sites: nil
  }
      
  if config[:limits][:sites]
    limits[:sites] = "--extra-vars '#{JSON.generate({limit_projects: config[:limits][:sites]})}'" 
  end

  limits
end

# 
# Settings
# 

# Get some base config structure.
# 
# For more options on how to do this, cf.:
# - https://www.cloudbees.com/blog/creating-configuration-objects-in-ruby/

config = OpenStruct.new

config.core         = get_config('./config/core.config.yml')
config.file         = File.expand_path('./config/core.config.yml')
config.runtime_file = File.expand_path('./config/generated.ansible-runtime.json')
config.ssh          = File.join(__dir__, '~/.ssh/config')
config.inventory    = File.join(__dir__, 'ansible/inventory/inventory.yml')
config.roles        = File.join(__dir__, 'ansible/roles')
config.collections  = File.join(__dir__, 'ansible/collections')
config.devops_dir   = __dir__

# CLI arguments
config.ARGV = ARGV

# Set limits (host(s), site(s))
config.limits = set_limits(config)

# Generate Ansible runtime config
write_ansible_runtime_vars config, config.file, config.runtime_file

#
# Bootstrap
# 

generate_ansible_files do |template, target|
  write_template(template, target, config)
end

# We do our own default help screen when no task was given.
# To get at the task descriptions as well as the task locations & other metadata, however, we need 
# to tell Rake to record them before we load the task definitions in.
Rake::TaskManager.record_task_metadata = true

#
# Tasks
# 
namespace :ansible do

  desc 'Update roles.'
  task :dependencies do
    cd('ansible') do
      begin
        sh 'ansible-galaxy install --roles-path=./roles/contrib -r requirements.yml'
        sh 'ansible-galaxy collection install -p=./collections -r requirements.yml'
      rescue RuntimeError; end  
    end
  end
end

namespace :conn do
  
  desc 'Try to ping a machine with Ansible, so we know we are able to connect.'
  task :ping do
    limits = get_limits(config)
    begin
      if limits[:hosts]
        sh "ansible #{limits[:hosts].gsub!('--limit ', '')} -i #{config.inventory} -m ping"
      end
    rescue RuntimeError; end  
  end
end

namespace :projects do
  
  desc 'Setup local project folders'
  task :init do
    cd('ansible/plays/main') do
      limits = get_limits config
      begin
        sh "ansible-playbook -i #{config.inventory} --extra-vars '@#{config.runtime_file}' #{limits[:sites]} --tags 'init'  #{limits[:hosts]} playbook.yml"
      rescue RuntimeError; end  
    end
  end
  
  # @todo Run projects:init first
  desc 'Fetch project(s) from remote'
  task :fetch do
    cd('ansible/plays/main') do
      limits = get_limits config
      begin
        sh "ansible-playbook -i #{config.inventory} --extra-vars '@#{config.runtime_file}' #{limits[:sites]} --tags 'fetch'  #{limits[:hosts]} playbook.yml"
      rescue RuntimeError; end  
    end
  end
end

#
# Help screen
# 
# Shows all tasks grouped by their respective namespace & ordered
# by their given position inside the files they're defined in (= they're
# showed in the same order as they were defined).
# 
task :default do

  # Helper to inspect Task objects.
  # 
  # Cf.:
  # https://ruby-doc.org/core-2.6/Proc.html
  # https://scoutapm.com/blog/how-to-use-lambdas-in-ruby
  # https://www.rubyguides.com/2018/12/ruby-inspect-method/
  # https://stackoverflow.com/questions/8595184/how-to-list-all-methods-for-an-object-in-ruby

  inspect = lambda do |t|
    ap t.inspect
    ap t.methods - Object.methods
  end

  # Acquire task infos, and group & sort tasks.

  tasks = Rake.application.tasks
  stack = []

  tasks.each do |t|
    
    # Evaluate a single task.
    # 
    # Cf. https://github.com/ruby/rake/blob/master/lib/rake/task.rb
    # 
    if t.scope && t.comment && t.full_comment
    
      # We want to keep all tasks in the context of their respective scope (i.e., their namespace),
      # so grab the (first) one the current task is attached to, if any.
      
      ns = t.scope.entries[-1] || 'Misc'

      # Fetch the physical location of a task.
      # 
      # For how & when Rake manages the location of a task cf.:
      # - https://github.com/ruby/rake/blob/master/lib/rake/task_manager.rb
      # - https://github.com/ruby/rake/blob/master/lib/rake/task.rb
      #
      location = t.locations && t.locations.length ? t.locations.first : nil
      
      if location 
        # Rake keeps the whole path & other info about a task in a single string, so just try to 
        # fetch the line no. of a task starts (i.e. its definition).
        location = location.match(/(?<=[:])\d+(?=[:])/).to_s.to_i        
      end

      stack.push({ns: ns, name: t.name, desc: t.full_comment, position: location || -1})
    end
  end

  stack = stack.sort     { |a, b| a[:position] <=> b[:position] }
  stack = stack.group_by { |task| task[:ns] } # cf. https://jelera.github.io/howto-work-with-ruby-group-by

  # Display banner.
  # 
  # For the Unicode chars, cf. the geometrical shapes at:
  # https://unicode.org/charts/#symbols

  puts
  puts "\u{250C}" << "\u{2500}" * 38 << "\u{2510}"
  puts "\u{2502}" << ' ' * 38 << "\u{2502}"
  puts "\u{2502}" << ' ' * 16 << 'DevOps' << ' ' * 16 << "\u{2502}"
  puts "\u{2502}" << ' ' * 38 << "\u{2502}"
  puts "\u{2514}" << "\u{2500}" * 38 << "\u{2518}"
  puts
  puts 'Usage:'
  puts 'rake TASK, e.g. rake some:task' 
  puts 'rake TASK, e.g. rake some:task -- HOSTNAME(S)'
  puts 'rake TASK, e.g. rake some:task -- HOSTNAME SITENAME'
  puts 
  puts 'Ping:'
  puts 'rake test:ping -- HOSTNAME(S)'
  puts 

  stack.each do |ns, tasks|

    title = "* #{ns.upcase} *"
    
    puts "-" * title.length
    puts title
    puts "-" * title.length
    puts

    task = tasks.shift
      
    puts sprintf("rake %s", task[:name]) 
    puts sprintf("%s".rjust(9, ' '), task[:desc]) 
    puts
  
    tasks.each do |t|
      
      puts sprintf("%s".rjust(7, ' '), t[:name]) 
      puts sprintf("%s".rjust(9, ' '), t[:desc]) 
      puts
    end
  end
end