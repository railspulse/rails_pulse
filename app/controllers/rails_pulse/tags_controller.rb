module RailsPulse
  class TagsController < ApplicationController
    before_action :set_taggable

    def create
      tag = params[:tag]

      if tag.blank?
        render turbo_stream: turbo_stream.replace("tag_manager_#{@taggable.class.name.demodulize.underscore}_#{@taggable.id}",
          partial: "rails_pulse/tags/tag_manager",
          locals: { taggable: @taggable, error: "Tag cannot be blank" })
        return
      end

      @taggable.add_tag(tag)
      @taggable.reload

      render turbo_stream: turbo_stream.replace("tag_manager_#{@taggable.class.name.demodulize.underscore}_#{@taggable.id}",
        partial: "rails_pulse/tags/tag_manager",
        locals: { taggable: @taggable })
    end

    def destroy
      tag = params[:tag]
      @taggable.remove_tag(tag)
      @taggable.reload

      render turbo_stream: turbo_stream.replace("tag_manager_#{@taggable.class.name.demodulize.underscore}_#{@taggable.id}",
        partial: "rails_pulse/tags/tag_manager",
        locals: { taggable: @taggable })
    end

    private

    def set_taggable
      @taggable_type = params[:taggable_type]
      @taggable_id = params[:taggable_id]

      @taggable = case @taggable_type
      when "route"
        Route.find(@taggable_id)
      when "request"
        Request.find(@taggable_id)
      when "query"
        Query.find(@taggable_id)
      when "job"
        Job.find(@taggable_id)
      when "job_run"
        JobRun.find(@taggable_id)
      else
        head :not_found
      end
    end
  end
end
