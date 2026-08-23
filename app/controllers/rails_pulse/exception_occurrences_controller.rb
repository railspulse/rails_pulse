module RailsPulse
  class ExceptionOccurrencesController < ApplicationController
    before_action :set_exception_group
    before_action :set_occurrence

    def show
    end

    private

    def set_exception_group
      @exception_group = ExceptionGroup.find(params[:exception_id])
    end

    def set_occurrence
      @occurrence = @exception_group.occurrences.find(params[:id])
    end
  end
end
