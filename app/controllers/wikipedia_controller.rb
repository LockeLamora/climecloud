# frozen_string_literal: true

require 'wikipedia'

class WikipediaController < ApplicationController
  def search
    @query = params[:query]
    if @query.blank?
      render :search
      return
    end

    service = Wikipedia.new({ query: @query })
    @results = service.search
    @error = service.error

    render :search
  end

  def article
    @title = params[:title]
    @full = params[:full] == '1'

    service = Wikipedia.new({ title: @title, full: @full })
    @article = service.article
    @error = service.error || (@article.nil? ? I18n.t('wikipedia.not_found') : nil)

    render :article
  end
end
