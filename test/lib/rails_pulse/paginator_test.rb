require "test_helper"

module RailsPulse
  class PaginatorTest < ActiveSupport::TestCase
    # Structure Tests

    test "paginator exposes count, page, and limit attributes" do
      paginator = Paginator.new(count: 100, page: 2, limit: 10)

      assert_equal 100, paginator.count
      assert_equal 2, paginator.page
      assert_equal 10, paginator.limit
    end

    # last Tests

    test "last returns 1 when count is zero" do
      paginator = Paginator.new(count: 0, page: 1, limit: 10)

      assert_equal 1, paginator.last
    end

    test "last returns 1 when count is less than limit" do
      paginator = Paginator.new(count: 5, page: 1, limit: 10)

      assert_equal 1, paginator.last
    end

    test "last returns 1 when count equals limit" do
      paginator = Paginator.new(count: 10, page: 1, limit: 10)

      assert_equal 1, paginator.last
    end

    test "last rounds up for non-divisible counts" do
      # 11 records / 10 per page = 2 pages
      paginator = Paginator.new(count: 11, page: 1, limit: 10)

      assert_equal 2, paginator.last
    end

    test "last calculates correct page count for large datasets" do
      # 100 records / 7 per page = ceil(14.28) = 15 pages
      paginator = Paginator.new(count: 100, page: 1, limit: 7)

      assert_equal 15, paginator.last
    end

    # previous Tests

    test "previous returns nil on first page" do
      paginator = Paginator.new(count: 50, page: 1, limit: 10)

      assert_nil paginator.previous
    end

    test "previous returns 1 when on page 2" do
      paginator = Paginator.new(count: 50, page: 2, limit: 10)

      assert_equal 1, paginator.previous
    end

    test "previous returns page minus one for middle pages" do
      paginator = Paginator.new(count: 100, page: 4, limit: 10)

      assert_equal 3, paginator.previous
    end

    # next Tests

    test "next returns nil on last page" do
      paginator = Paginator.new(count: 50, page: 5, limit: 10)

      assert_nil paginator.next
    end

    test "next returns 2 when on first page with multiple pages" do
      paginator = Paginator.new(count: 50, page: 1, limit: 10)

      assert_equal 2, paginator.next
    end

    test "next returns page plus one for middle pages" do
      paginator = Paginator.new(count: 100, page: 3, limit: 10)

      assert_equal 4, paginator.next
    end

    # Edge Cases

    test "page is clamped to 1 when given page 0" do
      paginator = Paginator.new(count: 50, page: 0, limit: 10)

      assert_equal 1, paginator.page
    end

    test "page is clamped to last when given page beyond last" do
      # 50 records / 10 per page = 5 pages, page 99 should clamp to 5
      paginator = Paginator.new(count: 50, page: 99, limit: 10)

      assert_equal 5, paginator.page
    end

    test "single page has no previous or next" do
      paginator = Paginator.new(count: 5, page: 1, limit: 10)

      assert_nil paginator.previous
      assert_nil paginator.next
    end
  end
end
