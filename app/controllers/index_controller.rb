class IndexController < ApplicationController
    def index
        if !cookies[:lat]
            redirect_to '/settings'
            return
        end

        render :index
    end
end
