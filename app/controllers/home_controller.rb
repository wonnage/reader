class HomeController < ApplicationController
  def index
    session[:active_feed] ||= current_user.feeds.first.id
  end
end
