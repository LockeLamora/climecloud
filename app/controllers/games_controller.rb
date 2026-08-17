# frozen_string_literal: true

require 'gamebooks'

class GamesController < ApplicationController
  # No require_saved_location: the books ship with the app, so a reader without a
  # postcode spends nobody's rate limit here.

  def index
    @books = Gamebooks.all
  end

  # The book's own title page: begin a first read, or continue/restart one already
  # under way. The bookmark only counts if it still names a section — a book edit that
  # renames sections must not leave a continue link pointing nowhere.
  def book
    @book = Gamebooks.find(params[:book])
    if @book.nil?
      redirect_to games_path
      return
    end

    saved = bookmarks[@book['id']]
    @bookmark = saved if saved != @book['start'] && @book['sections'].key?(saved)
  end

  def section
    @book = Gamebooks.find(params[:book])
    if @book.nil?
      redirect_to games_path
      return
    end

    @section = @book['sections'][params[:section]]
    if @section.nil?
      redirect_to games_book_path(book: @book['id'])
      return
    end

    remember_place
  end

  private

  # Reading progress lives in the CYOA cookie, one entry per book, client side like
  # every other setting. Written on a read rather than a POST: the bookmark is a note
  # about the page being served, not something the server stores, and a crawler that
  # follows section links only ever moves its own bookmark.
  def bookmarks
    JSON.parse(cookies['CYOA'].presence || '{}')
  rescue JSON::ParserError
    {}
  end

  def remember_place
    cookies.permanent['CYOA'] = bookmarks.merge(@book['id'] => params[:section]).to_json
  end
end
