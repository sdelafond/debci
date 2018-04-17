require 'yaml'
ENV['DATABASE_URL'] = 'sqlite3::memory:'
require 'debci/db'

Debci.config.quiet = true
Debci::DB.migrate

RSpec.configure do |config|
  config.before(:each) do
    ActiveRecord::Base.connection.tables.reject { |t| t == "schema_migrations" }.each do |table|
      ActiveRecord::Base.connection.execute("DELETE FROM #{table}")
    end
    allow_any_instance_of(Debci::Job).to receive(:enqueue)
  end
end