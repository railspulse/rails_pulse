module RailsPulse
  class Paginator
    attr_reader :count, :page, :limit

    def initialize(count:, page:, limit:)
      @count = count
      @limit = limit
      @page  = page.clamp(1, last)
    end

    def last
      [ (count.to_f / limit).ceil, 1 ].max
    end

    def previous
      page > 1 ? page - 1 : nil
    end

    def next
      page < last ? page + 1 : nil
    end
  end
end
