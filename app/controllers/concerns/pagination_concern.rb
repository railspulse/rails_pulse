# PaginationConcern
#
# Provides pagination functionality for controllers.
# Manages pagination limits in session with consistent validation (5-50 range).
# All pagination limits are clamped to ensure performance and security.
module PaginationConcern
  extend ActiveSupport::Concern

  # Sets pagination limit in session with validation
  # Used for both index and show pages via PATCH requests
  def set_pagination_limit(limit = nil)
    limit = limit || params[:limit]
    validated_limit = validate_pagination_limit(limit)
    session[:pagination_limit] = validated_limit if limit.present?

    # Render JSON for direct API calls or AJAX requests (but not turbo frame requests)
    if (request.xhr? && !turbo_frame_request?) || (request.patch? && action_name == "set_pagination_limit")
        render json: { status: "ok" }
    end
  end

  private

  # Returns the current pagination limit from session or params
  # Falls back to default of 10 if not set
  def session_pagination_limit
    # Use URL param if present, otherwise session, otherwise default
    limit = params[:limit].presence || session[:pagination_limit] || 10
    # Always validate the limit before returning
    validate_pagination_limit(limit)
  end

  # Paginates a collection using offset/limit
  # Returns a Paginator object and the paginated records
  def paginate(collection, limit:)
    page       = [ params[:page].to_i, 1 ].max
    raw        = collection.count(:all)
    count      = raw.is_a?(Hash) ? raw.size : raw
    paginator  = RailsPulse::Paginator.new(count: count, page: page, limit: limit)
    # Use the clamped page from paginator for offset calculation
    records    = collection.offset((paginator.page - 1) * limit).limit(limit)
    [ paginator, records ]
  end

  # Validates and clamps pagination limit to 5-50 range
  # Minimum 5 to ensure reasonable page sizes
  # Maximum 50 to prevent performance issues
  def validate_pagination_limit(limit)
    limit.to_i.clamp(5, 50)
  end
end
