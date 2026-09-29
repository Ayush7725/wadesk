# WaDesk: the operator console's System health page (CR-004). Checks every part of the installation and describes each
# in plain words for a non-technical operator. Every check is short and never raises, so one broken part cannot break
# the page. Never put secrets (tokens, passwords, URLs with credentials) into a check.
class Wadesk::SystemHealth
  # status: :ok, :warn or :bad. details: extra plain lines. numbers: WhatsApp Web counts (engine only).
  Check = Struct.new(:key, :title, :status, :summary, :details, :numbers, keyword_init: true)

  RETRYING_WARN_AT = 25 # jobs waiting to be retried after an error
  DEAD_WARN_AT = 100 # jobs that failed permanently (Sidekiq keeps them for months, so a few are normal)
  WAITING_WARN_AT = 1000 # jobs waiting to run: a backlog means workers cannot keep up

  def checks
    @checks ||= [app, database, redis, whatsapp_engine, email, background_jobs]
  end

  def healthy?
    checks.all? { |check| check.status == :ok }
  end

  def needing_attention
    checks.reject { |check| check.status == :ok }
  end

  private

  def app
    pending = migrations_pending?
    details = ["Version #{Chatwoot.config[:version]}#{" · build #{GIT_HASH.first(7)}" if git_sha?}"]
    if pending.nil?
      check(:app, 'App', :warn, 'The app is running, but it could not check whether its database is up to date.', details: details)
    elsif pending
      check(:app, 'App', :bad, 'The app was updated but its database was not. Ask your developer to run the database update (migrations).',
            details: details)
    else
      check(:app, 'App', :ok, 'The app is running and its database is up to date.', details: details)
    end
  end

  def database
    size = ActiveRecord::Base.connection.select_value('SELECT pg_database_size(current_database())').to_i
    check(:database, 'Database', :ok, 'The database is answering. It stores clients, conversations and settings.',
          details: ["Size: #{ActiveSupport::NumberHelper.number_to_human_size(size)}"])
  rescue StandardError
    check(:database, 'Database', :bad, 'The database is not answering. Nothing can be saved until it is back.')
  end

  def redis
    client = Redis.new(Redis::Config.app)
    check(:redis, 'Redis', :ok, 'Redis is answering. It holds the job queue and live updates.',
          details: ["Memory used: #{client.info['used_memory_human']}"])
  rescue StandardError
    check(:redis, 'Redis', :bad, 'Redis is not answering. Live updates and background work have stopped.')
  ensure
    client&.close
  end

  def whatsapp_engine
    status, summary = if ENV['WADESK_ENGINE_URL'].blank?
                        [:warn, 'The WhatsApp engine is not set up, so WhatsApp Web numbers cannot connect.']
                      else
                        engine_status
                      end
    check(:whatsapp_engine, 'WhatsApp engine', status, summary, numbers: whatsapp_web_numbers)
  end

  def engine_status
    case WhatsappWeb::EngineClient.new.health
    when :ok then [:ok, 'The WhatsApp engine is running. It keeps WhatsApp Web numbers connected.']
    when :database_down then [:bad, 'The WhatsApp engine is running but cannot reach its database, so numbers cannot stay connected.']
    else [:bad, 'The WhatsApp engine answered with an error. WhatsApp Web numbers may not send or receive.']
    end
  rescue StandardError
    [:bad, 'The WhatsApp engine is not answering. WhatsApp Web numbers cannot send or receive messages.']
  end

  def whatsapp_web_numbers
    { connected: Channel::Whatsapp.whatsapp_web_connected.count, needing_attention: Channel::Whatsapp.whatsapp_web_needing_attention.count }
  rescue StandardError
    nil
  end

  def email
    sender = email_sender
    details = if sender
                ["Emails are sent from #{sender}"]
              else
                ['No sender address is set (MAILER_SENDER_EMAIL), so emails come from a placeholder address that mail servers may reject.']
              end
    if ENV['SMTP_ADDRESS'].blank?
      check(:email, 'Email', :warn, 'No email server is set up, so invitations and password resets may never arrive.', details: details)
    elsif sender.nil?
      check(:email, 'Email', :warn, 'Emails are sent, but without your own sender address.', details: details)
    else
      check(:email, 'Email', :ok, 'Outgoing email is set up: invitations, password resets and notifications are sent.', details: details)
    end
  end

  # Only the address part: a display name could be anything, and the server name or password is never shown.
  def email_sender
    configured = ENV.fetch('MAILER_SENDER_EMAIL', nil).presence
    configured && Mail::Address.new(configured).address
  rescue Mail::Field::ParseError
    nil
  end

  def background_jobs
    stats = Sidekiq::Stats.new
    counts = { waiting: stats.enqueued, scheduled: stats.scheduled_size, retrying: stats.retry_size, dead: stats.dead_size }
    status, summary = background_jobs_status(counts, Sidekiq::ProcessSet.new.size)
    check(:background_jobs, 'Background jobs', status, summary, details: background_jobs_details(counts))
  rescue StandardError
    check(:background_jobs, 'Background jobs', :bad, 'Could not read the job queue. Background work is probably stopped.')
  end

  def background_jobs_status(counts, workers)
    if workers.zero?
      [:bad, 'No background worker is running, so messages and emails are not being sent.']
    elsif counts[:retrying] >= RETRYING_WARN_AT || counts[:dead] >= DEAD_WARN_AT
      [:warn, 'Many jobs are failing. Ask your developer to look at the retrying and failed jobs.']
    elsif counts[:waiting] >= WAITING_WARN_AT
      [:warn, 'Jobs are piling up faster than the server can do them.']
    else
      [:ok, 'Background work is running normally.']
    end
  end

  def background_jobs_details(counts)
    ["#{counts[:waiting]} waiting · #{counts[:scheduled]} scheduled for later · #{counts[:retrying]} retrying after an error · " \
     "#{counts[:dead]} failed for good"]
  end

  # nil when the check itself failed.
  def migrations_pending?
    ActiveRecord::Base.connection_pool.migration_context.needs_migration?
  rescue StandardError
    nil
  end

  def git_sha?
    GIT_HASH.present? && GIT_HASH != 'unknown'
  end

  # extra: details: and numbers:
  def check(key, title, status, summary, **extra)
    Check.new(key: key, title: title, status: status, summary: summary, details: [], **extra)
  end
end
