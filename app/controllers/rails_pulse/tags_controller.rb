module RailsPulse
  class TagsController < ApplicationController
    before_action :set_taggable

    # Tag validation rules
    TAG_NAME_REGEX = /\A[a-z0-9_-]+\z/i
    MAX_TAG_LENGTH = 50

    def create
      tag = params[:tag]

      # Validate tag name
      error_message = validate_tag(tag)
      if error_message
        render_error(error_message)
        return
      end

      # Add tag to taggable
      unless @taggable.add_tag(tag)
        render_error("Failed to add tag")
        return
      end

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

    def validate_tag(tag)
      return "Tag cannot be blank" if tag.blank?
      return "Tag must be #{MAX_TAG_LENGTH} characters or less" if tag.length > MAX_TAG_LENGTH
      return "Tag can only contain letters, numbers, hyphens, and underscores" unless tag.match?(TAG_NAME_REGEX)
      nil
    end

    def render_error(message)
      render turbo_stream: turbo_stream.replace("tag_manager_#{@taggable.class.name.demodulize.underscore}_#{@taggable.id}",
        partial: "rails_pulse/tags/tag_manager",
        locals: { taggable: @taggable, error: message })
    end

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
