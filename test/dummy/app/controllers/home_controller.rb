class HomeController < ApplicationController
  def index
    # Execute various queries to generate realistic Rails Pulse data

    # Simulate user lookup with complex joins
    @recent_users = User.includes(:posts, :comments)
                       .where(created_at: 1.week.ago..)
                       .order(created_at: :desc)
                       .limit(10)

    # Simulate post statistics with aggregations
    @post_stats = Post.joins(:user)
                     .group("users.name")
                     .count

    # Simulate search functionality with LIKE queries
    @search_results = Post.where("title LIKE ?", "%sample%")
                         .includes(:user, :comments)
                         .limit(5)

    # Simulate expensive query with subqueries
    @popular_posts = Post.where(
      id: Comment.group(:post_id)
                 .having("COUNT(*) > ?", 2)
                 .select(:post_id)
    ).includes(:user)

    # Simulate pagination query
    @paginated_posts = Post.offset(0).limit(20).order(:created_at)

    # Simulate individual record lookups
    if @recent_users.any?
      @featured_user = User.find(@recent_users.first.id)
      @user_post_count = @featured_user.posts.count
    end

    # Simulate cache-miss scenario with exists? check
    @has_recent_activity = Post.where(created_at: 1.day.ago..).exists?

    # Simulate N+1 query pattern (intentionally inefficient for testing)
    @post_authors = []
    Post.limit(5).each do |post|
      @post_authors << post.user.name if post.user
    end
  end

  # Fast query action - minimal database operations
  def fast
    @total_users = User.count
    @total_posts = Post.count
    @latest_post = Post.order(created_at: :desc).first
  end

  # Slow query action - complex aggregations and joins
  def slow
    # Complex aggregation that takes time
    @user_stats = User.joins(:posts, :comments)
                     .group("users.id", "users.name", "users.email")
                     .select("users.*, COUNT(DISTINCT posts.id) as post_count, COUNT(DISTINCT comments.id) as comment_count")
                     .having("COUNT(DISTINCT posts.id) > 0")
                     .order("post_count DESC, comment_count DESC")

    # Expensive text search
    @search_posts = Post.joins(:user, :comments)
                       .where("posts.content LIKE ? OR posts.title LIKE ?", "%lorem%", "%sample%")
                       .group("posts.id", "users.name")
                       .select("posts.*, users.name as author_name, COUNT(comments.id) as comment_count")
                       .order("comment_count DESC")

    # Multiple subqueries
    @active_users = User.where(
      id: Post.where(created_at: 2.weeks.ago..).select(:user_id)
    ).where(
      id: Comment.where(created_at: 1.week.ago..).select(:user_id)
    )
  end

  # Error prone action - simulates potential failures
  def error_prone
    # Simulate random errors for testing
    if rand < 0.3
      raise StandardError, "Simulated database timeout"
    end

    # Heavy query that might timeout
    @complex_data = Post.joins(:user)
                       .joins("LEFT JOIN comments ON posts.id = comments.post_id")
                       .group("posts.id", "users.name")
                       .having("COUNT(comments.id) >= ?", rand(1..10))
                       .order("COUNT(comments.id) DESC")
                       .limit(50)

    # Simulate potential N+1 issue
    @post_details = []
    Post.limit(10).each do |post|
      @post_details << {
        post: post,
        author: post.user,
        comment_count: post.comments.count,
        recent_comments: post.comments.recent.limit(3)
      }
    end
  end

  # Search action - various search patterns
  def search
    query = params[:q] || "sample"

    # Text search with LIKE (case-insensitive via UPPER)
    @text_results = Post.where("UPPER(title) LIKE UPPER(?) OR UPPER(content) LIKE UPPER(?)", "%#{query}%", "%#{query}%")
                       .includes(:user, :comments)
                       .limit(20)

    # Exact match search
    @exact_results = Post.where(title: query).includes(:user)

    # User search with join
    @user_results = User.joins(:posts)
                       .where("UPPER(users.name) LIKE UPPER(?)", "%#{query}%")
                       .distinct
                       .includes(:posts)

    # Comment search
    @comment_results = Comment.joins(:post, :user)
                             .where("UPPER(comments.content) LIKE UPPER(?)", "%#{query}%")
                             .includes(:post, :user)
                             .limit(10)

    # Combined search stats
    @search_stats = {
      total_posts: @text_results.count,
      total_users: @user_results.count,
      total_comments: @comment_results.count
    }
  end

  # API simulation - JSON responses with different complexity
  def api_simple
    @data = {
      users: User.count,
      posts: Post.count,
      comments: Comment.count,
      timestamp: Time.current
    }

    respond_to do |format|
      format.html
      format.json { render json: @data }
    end
  end

  def api_complex
    # Expensive aggregations for API
    @data = {
      user_statistics: User.joins(:posts, :comments)
                          .group("users.id")
                          .select("users.id, users.name, COUNT(DISTINCT posts.id) as posts_count, COUNT(DISTINCT comments.id) as comments_count")
                          .limit(20)
                          .map { |u| { id: u.id, name: u.name, posts: u.posts_count, comments: u.comments_count } },

      popular_posts: Post.joins(:comments)
                        .group("posts.id")
                        .select("posts.*, COUNT(comments.id) as comment_count")
                        .order("comment_count DESC")
                        .limit(10)
                        .map { |p| { id: p.id, title: p.title, comments: p.comment_count } },

      recent_activity: Comment.joins(:user, :post)
                             .order(created_at: :desc)
                             .limit(20)
                             .map { |c| { user: c.user.name, post: c.post.title, content: c.content.truncate(50) } },

      generated_at: Time.current
    }

    respond_to do |format|
      format.html
      format.json { render json: @data }
    end
  end

  # ChartKick demo action - tests compatibility with Chartkick
  def chartkick_demo
    # Generate data for various ChartKick chart types

    # Posts per user (Bar Chart)
    @posts_per_user = User.joins(:posts)
                         .group("users.name")
                         .count

    # Posts over time (Line Chart)
    @posts_over_time = Post.group_by_day(:created_at, last: 7).count

    # Comments per post (Column Chart)
    @comments_per_post = Post.joins(:comments)
                            .group("posts.title")
                            .count
                            .first(10)

    # User activity (Pie Chart)
    active_users_count = User.joins(:posts).where(posts: { created_at: 1.week.ago.. }).distinct.count
    total_users_count = User.count
    @user_activity = {
      "Active Users" => active_users_count,
      "Inactive Users" => total_users_count - active_users_count
    }

    # Area chart data
    @comments_over_time = Comment.group_by_day(:created_at, last: 7).count
  end
end
