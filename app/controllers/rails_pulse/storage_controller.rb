module RailsPulse
  class StorageController < ApplicationController
    def show
      @status = RailsPulse::Dashboard::StorageStatus.new
    end
  end
end
