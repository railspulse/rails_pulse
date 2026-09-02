# RansackParamsConcern
#
# Every filterable page reads its Ransack conditions from params[:q]. The
# dashboard's own forms always send a hash, but a hand-edited URL can make it
# a string or an array (`?q=foo`), and each caller would then invoke Hash
# methods on it and 500. Normalise once, here.
module RansackParamsConcern
  extend ActiveSupport::Concern

  private

  # params[:q] as an ActionController::Parameters hash, or an empty one when
  # the value is absent or not hash-shaped.
  def ransack_params
    q = params[:q]
    q.respond_to?(:permit) ? q : ActionController::Parameters.new({})
  end
end
