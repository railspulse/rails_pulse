class Comment < ApplicationRecord
  belongs_to :user
  belongs_to :post

  validates :content, presence: true

  scope :recent, -> { where(created_at: 1.day.ago..) }
end
