# frozen_string_literal: true

# Whether the news proxy failover exists is otherwise invisible until the morning
# Google walls the shared address — and a missing RAILS_MASTER_KEY leaves the
# credentials, and with them the proxy, silently absent. One line at boot says which
# world this process is in. The URL itself carries credentials, so only its presence
# is printed.
Rails.application.config.after_initialize do
  configured = Rails.application.credentials.fixie&.url.present? || ENV['FIXIE_URL'].present?
  Rails.logger.info("News proxy failover #{configured ? 'configured' : 'NOT configured'}")
end
