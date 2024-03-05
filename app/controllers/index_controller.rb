# frozen_string_literal: true

class IndexController < ApplicationController
  def index
    unless cookies[:lat]
      redirect_to '/settings'
      return
    end

    render :index
  end
end
