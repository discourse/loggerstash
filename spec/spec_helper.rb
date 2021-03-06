# frozen_string_literal: true

require 'bundler'
Bundler.setup(:default, :development)
require 'rspec/core'
require 'rspec/mocks'

require 'simplecov'
SimpleCov.start do
  add_filter('spec')
end

RSpec.configure do |config|
  config.order = :random
  config.fail_fast = true
  #config.full_backtrace = true

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
