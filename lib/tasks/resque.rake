require 'resque/tasks'

namespace :resque do
  task :setup => 'environment' do
    Resque.before_fork = Proc.new { ActiveRecord::Base.establish_connection }
  end
end
