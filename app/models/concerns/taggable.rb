module Taggable
  extend ActiveSupport::Concern

  included do
    # Callbacks
    before_save :ensure_tags_is_array

    # Scopes with table name qualification to avoid ambiguity
    scope :with_tag, ->(tag) { where("#{table_name}.tags LIKE ?", "%#{tag}%") }
    scope :without_tag, ->(tag) { where.not("#{table_name}.tags LIKE ?", "%#{tag}%") }
    scope :with_tags, -> { where("#{table_name}.tags IS NOT NULL AND #{table_name}.tags != '[]'") }
  end

  # Tag management methods
  def tag_list
    parsed_tags || []
  end

  def tag_list=(value)
    self.tags = value.to_json
  end

  def has_tag?(tag)
    tag_list.include?(tag.to_s)
  end

  def add_tag(tag)
    current_tags = tag_list
    unless current_tags.include?(tag.to_s)
      current_tags << tag.to_s
      self.tag_list = current_tags
      save
    end
  end

  def remove_tag(tag)
    current_tags = tag_list
    if current_tags.include?(tag.to_s)
      current_tags.delete(tag.to_s)
      self.tag_list = current_tags
      save
    end
  end

  private

  def parsed_tags
    return [] if tags.nil? || tags.empty?
    JSON.parse(tags)
  rescue JSON::ParserError
    []
  end

  def ensure_tags_is_array
    if tags.nil?
      self.tags = "[]"
    elsif tags.is_a?(Array)
      self.tags = tags.to_json
    end
  end
end
