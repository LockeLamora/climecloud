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

  # A pure read: the bookmark moves in #turn, never here, so a browser that fetches
  # links ahead of the cursor cannot turn pages the reader never chose.
  def section
    @book = Gamebooks.find(params[:book])
    if @book.nil?
      redirect_to games_path
      return
    end

    @section = @book['sections'][params[:section]]
    redirect_to games_book_path(book: @book['id']) if @section.nil?
  end

  # The section's picture alone, at a size worth panning around: the pictures hide
  # objects the footnotes ask the reader to find, and 219 pixels is too small to look
  # for a sheep in. A pure read, like the section itself.
  def picture
    @book = Gamebooks.find(params[:book])
    if @book.nil?
      redirect_to games_path
      return
    end

    @section = @book['sections'][params[:section]]
    @image = @section&.dig('image', 'full')
    redirect_to games_book_path(book: @book['id']) if @image.nil?
  end

  # Every choice in a section posts here. The bookmark is written and the reader is sent
  # on to the section's own GET, so the page being read keeps a plain URL that the back
  # button, a reload and the continue link can all fetch harmlessly.
  def turn
    book = Gamebooks.find(params[:book])
    if book.nil?
      redirect_to games_path
      return
    end

    unless book['sections'].key?(params[:section])
      redirect_to games_book_path(book: book['id'])
      return
    end

    cookies.permanent['CYOA'] = bookmarks.merge(book['id'] => params[:section]).to_json
    redirect_to games_section_path(book: book['id'], section: params[:section])
  end

  private

  # Reading progress lives in the CYOA cookie, one entry per book, client side like
  # every other setting.
  def bookmarks
    JSON.parse(cookies['CYOA'].presence || '{}')
  rescue JSON::ParserError
    {}
  end
end
