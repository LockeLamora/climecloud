# frozen_string_literal: true

require 'languages'

class ApplicationController < ActionController::Base
  before_action :set_locale

  private

  # Kept in a cookie like every other setting, so the choice survives without the
  # server storing anything about who made it.
  def set_locale
    I18n.locale = Languages.supported?(cookies[:locale]) ? cookies[:locale] : I18n.default_locale
  end
end
