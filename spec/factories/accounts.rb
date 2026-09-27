# frozen_string_literal: true

FactoryBot.define do
  factory :account do
    sequence(:name) { |n| "Account #{n}" }
    status { 'active' }
    domain { 'test.com' }
    support_email { 'support@test.com' }
    # WaDesk: new accounts get whatsapp_official from ACCOUNT_LEVEL_FEATURE_DEFAULTS, which the test database does not load.
    after(:build) { |account| account.enable_features('whatsapp_official') }
  end
end
