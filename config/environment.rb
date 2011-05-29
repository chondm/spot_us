RAILS_GEM_VERSION = '2.3.2' unless defined? RAILS_GEM_VERSION

require File.join(File.dirname(__FILE__), 'boot')
require 'yaml' 

config_file_path = File.join(RAILS_ROOT, *%w(config settings.yml))
if File.exist?(config_file_path)
  config = YAML.load_file(config_file_path)
  APP_CONFIG = config.has_key?(RAILS_ENV) ? config[RAILS_ENV] : {}
else
  puts "WARNING: configuration file #{config_file_path} not found." 
  APP_CONFIG = {}
end

DEFAULT_HOST = APP_CONFIG[:default_host] || ".spotus.local"

Rails::Initializer.run do |config|
  
  MEMCACHE_SERVERS = ['localhost']
  config.after_initialize do
    SpotUs::Cache.initialize!
  end
  
  config.load_paths += %W( #{RAILS_ROOT}/app/concerns )
  
  # need to update this list soon :-)
  config.gem "haml", :version => '>=2.0.6'
  config.gem "fastercsv"
  config.gem 'thoughtbot-factory_girl', :lib => 'factory_girl', :source => 'http://gems.github.com'
  config.gem "rubyist-aasm", :lib => "aasm", :version => '>=2.0.5', :source => 'http://gems.github.com'
  config.gem 'mislav-will_paginate', :lib => 'will_paginate', :version => '>=2.3.1', :source => 'http://gems.github.com/'
  config.gem "rspec-rails", :lib => false, :version => "= 1.2.2"
  config.gem "cucumber", :lib => false, :version => "= 0.1.16"
  config.gem "webrat", :lib => false, :version => "= 0.4.4"
  config.gem "money", :version => ">=2.1.3"
  config.gem "oauth2"
  config.gem "json"
  config.gem "twitter_oauth"

  config.time_zone = 'UTC'

  config.load_paths += %W( #{RAILS_ROOT}/app/sweepers )

  DEFAULT_SECRET = "552e024ba5bbf493d1ae37aacb875359804da2f1002fa908f304c7b0746ef9ab67875b69e66361eb9484fc0308cabdced715f7e97f02395874934d401a07d3e0"
  secret = APP_CONFIG[:action_controller][:session][:secret] rescue DEFAULT_SECRET

  config.action_controller.session = { :session_key => '_spotus_session', :secret => secret }
end

# use this domain for cookies so switching networks doesn't drop cookies
ActionController::Base.session_options[:domain] = DEFAULT_HOST

# These are the sizes of the domain (i.e. 0 for localhost, 1 for something.com)  
# for each of your environments  
SubdomainFu.tld_sizes = { :development => 1,
                          :test => 1,
                          :staging => 1,
                          :production => 1 }

# These are the subdomains that will be equivalent to no subdomain
SubdomainFu.mirrors = %w(www spotus spotreporting)

# This is the "preferred mirror" if you would rather show this subdomain
# in the URL than no subdomain at all.
# SubdomainFu.preferred_mirror = "www"

# define constant to see if it is in a production mode...
REAL_PRODUCTION_MODE = (RAILS_ENV=="production")

begin
   PhusionPassenger.on_event(:starting_worker_process) do |forked|
     if forked
       # We're in smart spawning mode, so...
       # Close duplicated memcached connections - they will open themselves
       CACHE.reset
     end
   end
# In case you're not running under Passenger (i.e. devmode with mongrel)
rescue NameError => error
end