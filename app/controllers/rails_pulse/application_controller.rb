module RailsPulse
  class ApplicationController < ActionController::Base
    def set_pagination_limit
      session[:pagination_limit] = params[:limit].to_i if params[:limit].present?
      render json: { status: 'ok' }
    end

    private

    def session_pagination_limit
      session[:pagination_limit] || 10
    end

    def store_pagination_limit(limit)
      session[:pagination_limit] = limit.to_i if limit.present?
    end
  end
end
