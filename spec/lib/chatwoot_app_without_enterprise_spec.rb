require 'rails_helper'

# WaDesk runs without Chatwoot's enterprise/ code: the production image does not contain it and development sets
# DISABLE_ENTERPRISE (licence: docs/wadesk/05-enterprise-feature-audit.md). CI deletes enterprise/ before the specs.
RSpec.describe ChatwootApp do
  it 'keeps enterprise/ out of the production image' do
    ignored = Rails.root.join('.dockerignore').read.lines.map(&:strip)

    expect(ignored).to include('enterprise', 'spec/enterprise')
  end

  it 'does not load enterprise code, views or extensions' do
    expect(described_class).not_to be_enterprise
    expect(described_class.extensions).to be_empty
    expect(ActionController::Base.view_paths.map(&:to_s)).to all(satisfy { |path| path.exclude?('/enterprise/') })
    expect(ActiveSupport::Dependencies.autoload_paths.map(&:to_s)).to all(satisfy { |path| path.exclude?('/enterprise/') })
  end

  it 'does not draw routes whose controllers exist only in enterprise/' do
    %w[
      /api/v1/accounts/1/custom_roles /api/v1/accounts/1/audit_logs /api/v1/accounts/1/sla_policies
      /api/v1/accounts/1/applied_slas /api/v1/accounts/1/agent_capacity_policies /api/v1/accounts/1/saml_settings
      /api/v1/accounts/1/captain/assistants /api/v1/accounts/1/captain/documents
    ].each do |path|
      expect { Rails.application.routes.recognize_path(path, method: :get) }.to raise_error(ActionController::RoutingError), path
    end
  end

  it 'keeps the MIT Captain task and preference routes' do
    expect(Rails.application.routes.recognize_path('/api/v1/accounts/1/captain/tasks/rewrite', method: :post))
      .to include(controller: 'api/v1/accounts/captain/tasks', action: 'rewrite')
    expect(Rails.application.routes.recognize_path('/api/v1/accounts/1/captain/preferences', method: :get))
      .to include(controller: 'api/v1/accounts/captain/preferences')
  end
end
