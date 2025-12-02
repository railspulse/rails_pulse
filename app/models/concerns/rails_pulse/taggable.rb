module RailsPulse
  module Taggable
    extend ActiveSupport::Concern

    # Tag validation constants
    TAG_NAME_REGEX = /\A[a-z0-9_-]+\z/i
    MAX_TAG_LENGTH = 50

    included do
      # Callbacks
      before_save :ensure_tags_is_array

      # Scopes with table name qualification to avoid ambiguity
      # Note: LIKE patterns are sanitized to prevent SQL injection via wildcards
      scope :with_tag, ->(tag) {
        sanitized_tag = sanitize_sql_like(tag.to_s, "\\")
        where("#{table_name}.tags LIKE ?", "%#{sanitized_tag}%")
      }
      scope :without_tag, ->(tag) {
        sanitized_tag = sanitize_sql_like(tag.to_s, "\\")
        where.not("#{table_name}.tags LIKE ?", "%#{sanitized_tag}%")
      }
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
      # Validate tag format and length
      return false unless valid_tag_name?(tag)

      current_tags = tag_list
      unless current_tags.include?(tag.to_s)
        current_tags << tag.to_s
        self.tag_list = current_tags
        save
      else
        true  # Tag already exists, return success
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

    def valid_tag_name?(tag)
      return false if tag.blank?
      return false if tag.to_s.length > MAX_TAG_LENGTH
      return false unless tag.to_s.match?(TAG_NAME_REGEX)
      true
    end

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
end
