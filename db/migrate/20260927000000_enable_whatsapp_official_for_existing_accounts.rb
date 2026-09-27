# WaDesk: Official WhatsApp became a plan (whatsapp_official). Accounts that existed before keep it; new accounts
# get it from `enabled: true` in features.yml, which ConfigLoader applies on deploy.
class EnableWhatsappOfficialForExistingAccounts < ActiveRecord::Migration[7.1]
  def up
    Account.find_in_batches(batch_size: 100) do |accounts|
      accounts.each { |account| account.enable_features!('whatsapp_official') }
    end
  end
end
