# RansackParamsConcern
#
# Every filterable page reads its Ransack conditions from params[:q]. The
# dashboard's own forms always send a hash, but a hand-edited URL can make it
# a string or an array (`?q=foo`), and each caller would then invoke Hash
# methods on it and 500. Normalise once, here.
module RansackParamsConcern
  extend ActiveSupport::Concern

  included do
    helper_method :ransack_params
  end

  private

  # params[:q] as an ActionController::Parameters hash, or an empty one when
  # the value is absent or not hash-shaped. A sort (`s`) that is not a
  # string or a list of strings is dropped: Ransack raises on a hash such as
  # `q[s][a]=b`, and the dashboard's sort links only ever send strings.
  def ransack_params
    q = params[:q]
    return ActionController::Parameters.new({}) unless q.respond_to?(:permit)

    sort = q[:s]
    return q if sort.nil? || valid_ransack_sort?(sort)

    q.except(:s)
  end

  def valid_ransack_sort?(sort)
    sort.is_a?(String) || (sort.is_a?(Array) && sort.all?(String))
  end
end
