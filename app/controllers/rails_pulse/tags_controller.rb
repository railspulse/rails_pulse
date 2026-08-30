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
        flash[:alert] = error_message
      elsif @taggable.add_tag(tag)
        flash[:notice] = "Tag added"
      else
        flash[:alert] = "Failed to add tag"
      end

      redirect_back(fallback_location: root_path, allow_other_host: false)
    end

    def destroy
      tag = params[:tag]
      if @taggable.remove_tag(tag)
        flash[:notice] = "Tag removed"
      else
        flash[:alert] = "Failed to remove tag"
      end

      redirect_back(fallback_location: root_path, allow_other_host: false)
    end

    private

    def validate_tag(tag)
      return "Tag cannot be blank" if tag.blank?
      return "Tag must be #{MAX_TAG_LENGTH} characters or less" if tag.length > MAX_TAG_LENGTH
      return "Tag can only contain letters, numbers, hyphens, and underscores" unless tag.match?(TAG_NAME_REGEX)
      nil
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
