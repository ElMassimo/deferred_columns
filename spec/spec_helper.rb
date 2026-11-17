# frozen_string_literal: true

require 'simplecov'
SimpleCov.start { skip '/spec/' }

require 'bundler/setup'
require 'deferred_columns'
require_relative 'support/models'

module QueryHelpers
  IGNORED_SQL = /\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE|PRAGMA)/i

  # The SQL statements run inside the block.
  def queries(&)
    statements = []
    callback = ->(*, payload) {
      statements << payload[:sql] unless payload[:name] == 'SCHEMA' || payload[:sql].match?(IGNORED_SQL)
    }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &)
    statements
  end

  # The only SQL statement run inside the block.
  def query(&)
    statements = queries(&)
    expect(statements.size).to eq(1), "Expected 1 query, got #{statements.size}:\n#{statements.join("\n")}"
    statements.first
  end

  def column(table, name)
    %("#{table}"."#{name}")
  end
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.include QueryHelpers

  config.before(:suite) { Catalog.seed }

  config.around do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end
end
