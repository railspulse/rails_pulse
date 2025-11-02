# Clear existing data
Comment.destroy_all
Post.destroy_all
User.destroy_all

# Create sample users
users = [
  { name: "Alice Johnson", email: "alice@example.com" },
  { name: "Bob Smith", email: "bob@example.com" },
  { name: "Carol Williams", email: "carol@example.com" },
  { name: "David Brown", email: "david@example.com" },
  { name: "Emma Davis", email: "emma@example.com" },
  { name: "Frank Miller", email: "frank@example.com" },
  { name: "Grace Wilson", email: "grace@example.com" },
  { name: "Henry Taylor", email: "henry@example.com" }
]

created_users = users.map do |user_data|
  User.create!(user_data)
end

# Create sample posts
post_titles = [
  "Getting Started with Rails 8",
  "Database Optimization Tips",
  "Understanding Active Record",
  "Building REST APIs",
  "Sample Post for Testing",
  "Performance Monitoring Guide",
  "Advanced SQL Queries",
  "Web Development Best Practices",
  "Scaling Rails Applications",
  "Another Sample Article",
  "Database Indexing Strategies",
  "Sample Content for Demo",
  "Rails Security Guidelines",
  "Testing in Rails",
  "Sample Blog Post Example"
]

created_posts = []
post_titles.each_with_index do |title, index|
  user = created_users[index % created_users.length]
  post = Post.create!(
    user: user,
    title: title,
    content: "This is the content for #{title}. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.",
    published: [ true, false ].sample,
    created_at: rand(4.weeks.ago..Time.current)
  )
  created_posts << post
end

# Create sample comments
comment_contents = [
  "Great article! Very helpful.",
  "Thanks for sharing this information.",
  "I have a question about this approach.",
  "This solved my problem perfectly.",
  "Could you elaborate on this point?",
  "Excellent explanation!",
  "I disagree with this approach.",
  "Very well written.",
  "This is exactly what I was looking for.",
  "Any updates on this topic?"
]

# Create comments with some posts having multiple comments
created_posts.each do |post|
  comment_count = rand(0..5) # Some posts have no comments, others have up to 5
  comment_count.times do
    user = created_users.sample
    Comment.create!(
      user: user,
      post: post,
      content: comment_contents.sample,
      created_at: rand(post.created_at..Time.current)
    )
  end
end

puts "Created #{User.count} users"
puts "Created #{Post.count} posts"
puts "Created #{Comment.count} comments"

# Generate historical data if environment flag is set
if ENV["GENERATE_HISTORICAL_DATA"] == "true"
  puts "\nGenerating historical Rails Pulse performance data..."

  # Clear existing Rails Pulse data
  RailsPulse::Operation.destroy_all
  RailsPulse::Query.destroy_all
  RailsPulse::Request.destroy_all
  RailsPulse::Route.destroy_all
  RailsPulse::Summary.destroy_all

  # Define realistic routes based on the home controller
  routes_data = [
    { method: "GET", path: "/" },
    { method: "GET", path: "/fast" },
    { method: "GET", path: "/slow" },
    { method: "GET", path: "/error_prone" },
    { method: "GET", path: "/search" },
    { method: "GET", path: "/api_simple" },
    { method: "GET", path: "/api_complex" },
    { method: "POST", path: "/users" },
    { method: "GET", path: "/users/:id" },
    { method: "PUT", path: "/users/:id" },
    { method: "DELETE", path: "/users/:id" },
    { method: "POST", path: "/posts" },
    { method: "GET", path: "/posts/:id" },
    { method: "PUT", path: "/posts/:id" },
    { method: "DELETE", path: "/posts/:id" },
    { method: "POST", path: "/comments" },
    { method: "GET", path: "/admin/dashboard" },
    { method: "GET", path: "/admin/users" },
    { method: "GET", path: "/api/v1/posts" },
    { method: "GET", path: "/api/v1/users" }
  ]

  created_routes = routes_data.map do |route_data|
    RailsPulse::Route.create!(route_data)
  end

  # Define realistic SQL queries - mix of good and problematic queries for analysis
  queries_data = [
    # Good queries
    "SELECT id, name, email FROM users WHERE id = ?",
    "SELECT * FROM posts WHERE user_id = ? ORDER BY created_at DESC LIMIT ?",
    "SELECT posts.title, posts.content, users.name FROM posts JOIN users ON posts.user_id = users.id WHERE posts.published = ?",
    "SELECT COUNT(*) FROM comments WHERE post_id = ?",
    "SELECT * FROM comments WHERE post_id = ? ORDER BY created_at DESC LIMIT ?",
    "INSERT INTO posts (user_id, title, content, published, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
    "UPDATE posts SET title = ?, content = ?, updated_at = ? WHERE id = ?",
    "DELETE FROM posts WHERE id = ?",
    "SELECT id, name FROM users WHERE email = ?",

    # Problematic queries for analysis (will trigger issues and suggestions)
    "SELECT * FROM users WHERE id = ?",  # SELECT * issue
    "SELECT name FROM users",  # Missing WHERE clause
    "SELECT posts.* FROM posts WHERE title LIKE ? OR content LIKE ?",  # Missing LIMIT on search
    "SELECT * FROM posts WHERE created_at > ?",  # SELECT * + Missing LIMIT
    "SELECT users.* FROM users LEFT JOIN posts ON users.id = posts.user_id LEFT JOIN comments ON posts.id = comments.post_id WHERE users.active = ? AND posts.published = ? AND comments.approved = ? OR users.created_at > ? AND posts.created_at > ? AND comments.created_at > ?",  # Complex WHERE clause

    # Very complex queries that will trigger multiple issues
    "SELECT * FROM users LEFT JOIN posts ON users.id = posts.user_id LEFT JOIN comments ON posts.id = comments.post_id LEFT JOIN tags ON posts.id = tags.post_id LEFT JOIN categories ON posts.category_id = categories.id WHERE users.active = ? AND posts.published = ? AND comments.approved = ? AND tags.name LIKE ? AND categories.visible = ? AND users.email LIKE ? AND posts.title LIKE ? OR comments.content LIKE ? AND users.created_at BETWEEN ? AND ? AND posts.updated_at > ? ORDER BY users.created_at, posts.created_at, comments.created_at",  # SELECT *, many JOINs, complex WHERE, no LIMIT

    "SELECT users.*, posts.*, comments.*, COUNT(DISTINCT posts.id) as post_count, COUNT(DISTINCT comments.id) as comment_count, AVG(posts.view_count) as avg_views, MAX(comments.created_at) as latest_comment FROM users LEFT JOIN posts ON users.id = posts.user_id LEFT JOIN comments ON users.id = comments.user_id LEFT JOIN user_preferences ON users.id = user_preferences.user_id LEFT JOIN subscriptions ON users.id = subscriptions.user_id WHERE (users.active = ? OR users.premium = ?) AND (posts.published = ? OR posts.featured = ?) AND (comments.approved = ? OR comments.flagged = ?) AND users.created_at BETWEEN ? AND ? GROUP BY users.id HAVING COUNT(posts.id) > ? AND AVG(posts.view_count) > ?",  # Very complex with subqueries, aggregations, HAVING

    "SELECT * FROM (SELECT users.id, users.name, users.email, COUNT(posts.id) as post_count FROM users LEFT JOIN posts ON users.id = posts.user_id WHERE users.active = ? GROUP BY users.id) as user_posts JOIN (SELECT user_id, COUNT(*) as comment_count FROM comments WHERE approved = ? GROUP BY user_id) as user_comments ON user_posts.id = user_comments.user_id WHERE user_posts.post_count > ? AND user_comments.comment_count > ?",  # Subqueries, SELECT *

    "SELECT DISTINCT users.*, posts.*, comments.* FROM users, posts, comments WHERE users.id = posts.user_id AND posts.id = comments.post_id AND users.created_at > ? AND posts.created_at > ? AND comments.created_at > ?",  # Old-style JOINs, SELECT *, DISTINCT without LIMIT

    # Aggregation heavy queries
    "SELECT users.*, COUNT(DISTINCT posts.id) as post_count, COUNT(DISTINCT comments.id) as comment_count, SUM(posts.view_count) as total_views, AVG(posts.view_count) as avg_views, MIN(posts.created_at) as first_post, MAX(posts.created_at) as latest_post FROM users LEFT JOIN posts ON users.id = posts.user_id LEFT JOIN comments ON users.id = comments.user_id GROUP BY users.id",  # Missing WHERE, many aggregations

    # Search queries without proper indexing considerations
    "SELECT * FROM posts WHERE title LIKE ? AND content LIKE ? AND LOWER(title) LIKE ? AND UPPER(content) LIKE ?",  # Function calls in WHERE, SELECT *, no LIMIT

    # Update/Delete without proper constraints
    "UPDATE posts SET view_count = view_count + 1 WHERE published = ?",  # Potentially updates many rows
    "DELETE FROM comments WHERE created_at < ?"  # Potentially deletes many rows
  ]

  created_queries = queries_data.map do |sql|
    RailsPulse::Query.create!(normalized_sql: sql)
  end

  # Generate historical requests and operations
  request_count = ENV["HISTORICAL_REQUEST_COUNT"]&.to_i || 5000
  puts "Generating #{request_count} historical requests..."

  # Define a 6-hour performance issue period (simulate slowdown 2 weeks ago)
  slowdown_start = 2.weeks.ago + 14.hours # 2PM two weeks ago
  slowdown_end = slowdown_start + 6.hours  # Until 8PM same day
  puts "Simulating performance issue from #{slowdown_start.strftime('%B %d, %Y at %I:%M %p')} to #{slowdown_end.strftime('%I:%M %p')}"

  request_count.times do |i|
    route = created_routes.sample
    occurred_at = rand(5.weeks.ago..Time.current)

    # Determine performance characteristics based on route (web app durations)
    base_duration = case route.path
    when "/"
      rand(80..250)   # Homepage with multiple queries
    when "/fast"
      rand(15..45)    # Fast endpoint
    when "/slow"
      rand(450..1800) # Slow endpoint with complex queries
    when "/error_prone"
      rand(35..800)   # Variable performance
    when "/search"
      rand(85..350)   # Search varies by complexity
    when "/api_simple"
      rand(25..75)    # Simple API
    when "/api_complex"
      rand(250..900)  # Complex API with aggregations
    else
      rand(35..250)   # Standard CRUD operations
    end

    # Add some realistic variance
    duration = base_duration + rand(-base_duration * 0.3..base_duration * 0.5)
    duration = [ duration, 10 ].max # Minimum 10ms

    # Apply 50% slowdown during the performance issue period
    if occurred_at >= slowdown_start && occurred_at <= slowdown_end
      duration *= 1.5
    end

    # Determine if this is an error (higher chance for error_prone route)
    is_error = case route.path
    when "/error_prone"
      rand < 0.15 # 15% error rate
    else
      rand < 0.02 # 2% error rate for other routes
    end

    status = if is_error
      [ 400, 404, 422, 500, 503 ].sample
    else
      [ 200, 201, 204 ].sample
    end

    request = RailsPulse::Request.create!(
      route: route,
      duration: duration, # Duration in milliseconds
      status: status,
      is_error: is_error,
      request_uuid: SecureRandom.uuid,
      controller_action: "#{route.path.split('/')[1] || 'home'}##{route.method.downcase}",
      occurred_at: occurred_at
    )

    # Generate operations for this request
    operation_count = case route.path
    when "/"
      rand(8..15)    # Homepage has many operations
    when "/fast"
      rand(1..3)     # Fast endpoint has few operations
    when "/slow"
      rand(15..30)   # Slow endpoint has many operations
    when "/error_prone"
      rand(5..20)    # Variable operations
    when "/search"
      rand(6..12)    # Search has moderate operations
    when "/api_complex"
      rand(10..25)   # Complex API has many operations
    else
      rand(3..8)     # Standard operations
    end

    current_time = 0.0
    operation_count.times do |op_index|
      operation_type = [ "sql", "template", "controller" ].sample

      operation_duration = case operation_type
      when "sql"
        rand(5..200) # 5ms to 200ms for SQL
      when "template"
        rand(10..100) # 10ms to 100ms for rendering
      when "controller"
        duration # Controller time is total time
      end

      # Assign query for SQL operations - bias towards complex queries for more interesting analysis
      query = if operation_type == "sql"
        # 70% chance to use a complex/problematic query, 30% chance for any query
        if rand < 0.7
          complex_queries = created_queries.select do |q|
            sql = q.normalized_sql
            sql.include?("SELECT *") ||
            (sql.match?(/^SELECT.*FROM/i) && !sql.include?("WHERE")) ||
            sql.scan(/\bJOIN\b/i).length > 2 ||
            sql.include?("(SELECT") ||
            sql.scan(/\bAND\b|\bOR\b/i).length > 3
          end
          complex_queries.any? ? complex_queries.sample : created_queries.sample
        else
          created_queries.sample
        end
      else
        nil
      end

      operation_label = case operation_type
      when "sql"
        query&.normalized_sql&.split(" ")&.first(3)&.join(" ") || "SQL Query"
      when "template"
        [ "layouts/application", "home/index", "posts/show", "users/index" ].sample
      when "controller"
        request.controller_action
      end

      # Generate realistic codebase locations based on operation type and content
      codebase_location = case operation_type
      when "sql"
        # Map specific queries to specific file locations
        case query&.normalized_sql
        # Good queries
        when /SELECT id, name, email FROM users WHERE id = \?/
          "app/models/user.rb:15"
        when /SELECT \* FROM posts WHERE user_id = \? ORDER BY created_at DESC LIMIT \?/
          "app/models/user.rb:23"
        when /SELECT posts\.title, posts\.content, users\.name FROM posts JOIN users/
          "app/controllers/home_controller.rb:28"
        when /SELECT COUNT\(\*\) FROM comments WHERE post_id = \?/
          "app/models/post.rb:18"
        when /SELECT \* FROM comments WHERE post_id = \? ORDER BY created_at DESC LIMIT \?/
          "app/controllers/home_controller.rb:45"
        when /INSERT INTO posts/
          "app/models/post.rb:8"
        when /UPDATE posts SET title = \?/
          "app/models/post.rb:35"
        when /DELETE FROM posts WHERE id = \?/
          "app/models/post.rb:42"
        when /SELECT id, name FROM users WHERE email = \?/
          "app/models/user.rb:31"

        # Problematic queries
        when /SELECT \* FROM users WHERE id = \?/
          "app/models/user.rb:18"
        when /SELECT name FROM users$/
          "app/controllers/admin_controller.rb:67"
        when /SELECT posts\.\* FROM posts WHERE title LIKE \? OR content LIKE \?/
          "app/controllers/search_controller.rb:12"
        when /SELECT \* FROM posts WHERE created_at > \?$/
          "app/controllers/home_controller.rb:89"

        # Very complex queries
        when /SELECT users\.\* FROM users LEFT JOIN posts.*LEFT JOIN comments.*WHERE.*AND.*OR/
          "app/controllers/analytics_controller.rb:45"
        when /SELECT \* FROM users LEFT JOIN posts.*LEFT JOIN comments.*LEFT JOIN tags.*LEFT JOIN categories/
          "app/controllers/reports_controller.rb:23"
        when /SELECT users\.\*, posts\.\*, comments\.\*, COUNT\(DISTINCT posts\.id\)/
          "app/controllers/dashboard_controller.rb:78"
        when /SELECT \* FROM \(SELECT users\.id.*COUNT\(posts\.id\) as post_count/
          "app/controllers/analytics_controller.rb:156"
        when /SELECT DISTINCT users\.\*, posts\.\*, comments\.\* FROM users, posts, comments/
          "app/controllers/legacy_controller.rb:34"

        # Aggregation heavy queries
        when /SELECT users\.\*, COUNT\(DISTINCT posts\.id\) as post_count.*SUM\(posts\.view_count\)/
          "app/controllers/metrics_controller.rb:89"

        # Search queries with issues
        when /SELECT \* FROM posts WHERE title LIKE \? AND content LIKE \? AND LOWER\(title\)/
          "app/controllers/advanced_search_controller.rb:45"

        # Problematic update/delete queries
        when /UPDATE posts SET view_count = view_count \+ 1 WHERE published = \?/
          "app/models/post.rb:67"
        when /DELETE FROM comments WHERE created_at < \?/
          "app/jobs/cleanup_job.rb:23"

        else
          "app/models/application_record.rb:12"
        end
      when "template"
        case operation_label
        when "layouts/application"
          "app/views/layouts/application.html.erb:1"
        when "home/index"
          "app/views/home/index.html.erb:3"
        when "posts/show"
          "app/views/home/search.html.erb:8"
        when "users/index"
          "app/views/home/index.html.erb:15"
        else
          "app/controllers/application_controller.rb:25"
        end
      when "controller"
        case route.path
        when "/"
          "app/controllers/home_controller.rb:5"
        when "/fast"
          "app/controllers/home_controller.rb:15"
        when "/slow"
          "app/controllers/home_controller.rb:25"
        when "/error_prone"
          "app/controllers/home_controller.rb:35"
        when "/search"
          "app/controllers/home_controller.rb:45"
        when "/api_simple"
          "app/controllers/home_controller.rb:55"
        when "/api_complex"
          "app/controllers/home_controller.rb:65"
        else
          "app/controllers/home_controller.rb:75"
        end
      else
        "app/controllers/application_controller.rb:10"
      end

      RailsPulse::Operation.create!(
        request: request,
        query: query,
        operation_type: operation_type,
        label: operation_label,
        duration: operation_duration,
        codebase_location: codebase_location,
        start_time: current_time,
        occurred_at: occurred_at
      )

      current_time += operation_duration
    end

    print "." if i % (request_count / 50).ceil == 0
  end

  puts "\n\nGenerated historical Rails Pulse data:"
  puts "- #{RailsPulse::Route.count} routes"
  puts "- #{RailsPulse::Query.count} unique queries"
  puts "- #{RailsPulse::Request.count} requests"
  puts "- #{RailsPulse::Operation.count} operations"

  # Add some additional user/post data for more realistic scenarios
  first_names = %w[Isabella Jack Kate Liam Maya Noah Olivia Parker Quinn Ruby Sam Tara Ulysses Victoria William Xavier Yara Zoe Alexander Benjamin Charlotte Daniel Elizabeth Felix Gabriel Hannah Isaac Julia Kevin Luna Marcus Natalie Oscar Penelope]
  last_names = %w[Anderson Thomas Jackson White Harris Martin Thompson Garcia Martinez Robinson Clark Rodriguez Lewis Lee Walker Hall Allen Young Hernandez King Wright Lopez Hill Green Adams Baker Gonzalez Nelson Carter Mitchell]
  domains = %w[example.com gmail.com yahoo.com outlook.com company.org tech.io startup.com]

  additional_users = []
  150.times do |i|
    first_name = first_names.sample
    last_name = last_names.sample
    email = "#{first_name.downcase}.#{last_name.downcase}#{i + 100}@#{domains.sample}"
    user = User.create!(
      name: "#{first_name} #{last_name}",
      email: email,
      created_at: rand(5.weeks.ago..Time.current)
    )
    additional_users << user
  end

  all_users = created_users + additional_users

  # Historical post topics and content variations
  post_topics = [
    "Advanced Rails Patterns", "Database Performance Tuning", "Microservices Architecture", "GraphQL Implementation",
    "Redis Caching Strategies", "Background Job Processing", "API Rate Limiting", "OAuth Integration",
    "Docker Containerization", "Kubernetes Deployment", "CI/CD Pipelines", "Monitoring and Alerting",
    "Code Quality Metrics", "Refactoring Techniques", "Design Patterns", "Test-Driven Development",
    "Frontend Frameworks", "State Management", "Progressive Web Apps", "Mobile Development",
    "Machine Learning Integration", "Data Visualization", "Analytics Implementation", "A/B Testing",
    "User Authentication", "Authorization Patterns", "Session Management", "CORS Configuration",
    "Error Tracking", "Performance Optimization", "Memory Management", "Debugging Techniques"
  ]

  content_templates = [
    "This comprehensive guide covers %s. We'll explore the fundamentals and advanced techniques that every developer should know.",
    "In this detailed article about %s, we dive deep into practical examples and real-world applications that you can implement today.",
    "Understanding %s is crucial for modern web development. Here's everything you need to know to get started with confidence.",
    "%s has become increasingly important in today's development landscape. Let's explore the best practices and common pitfalls to avoid.",
    "A practical approach to %s with step-by-step instructions and code examples for better implementation and maintainability.",
    "Deep dive into %s: from basic concepts to advanced implementation strategies that scale with your application.",
    "%s explained with real-world examples and actionable insights from production environments."
  ]

  additional_posts = []
  800.times do
    topic = post_topics.sample
    user = all_users.sample
    created_at = rand(5.weeks.ago..1.week.ago)

    post = Post.create!(
      user: user,
      title: "#{topic}: #{%w[Complete Ultimate Practical Advanced Comprehensive Essential Modern].sample} #{%w[Guide Tutorial Overview Walkthrough Reference].sample}",
      content: (content_templates.sample % topic.downcase) + " Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.",
      published: rand < 0.85,
      created_at: created_at
    )
    additional_posts << post
  end

  all_posts = created_posts + additional_posts

  # Historical comment variations
  comment_templates = [
    "Excellent article! This really helped me understand the concept better.",
    "Thanks for sharing this detailed explanation. Very useful information.",
    "I have a question about the implementation you mentioned in section 3.",
    "This approach worked perfectly for my use case. Much appreciated!",
    "Could you provide more details about the performance implications?",
    "Outstanding write-up! I'll definitely be bookmarking this for reference.",
    "I encountered a similar issue and this solution was exactly what I needed.",
    "Well written and easy to follow. Thanks for taking the time to share this.",
    "This is a game-changer for my current project. Amazing insights!",
    "Any recommendations for handling edge cases with this approach?",
    "I implemented this yesterday and saw immediate improvements in performance.",
    "The examples you provided make this much clearer. Thank you!",
    "Have you considered the security implications of this method?",
    "This tutorial saved me hours of debugging. Really appreciate the effort!",
    "Interesting perspective on this topic. I learned something new today.",
    "Great explanation! Could you also cover the testing aspects?",
    "This solved a problem I've been struggling with for weeks.",
    "Clear and concise. Exactly what I was looking for.",
    "Would love to see a follow-up article on advanced techniques.",
    "Thanks for the code examples. They were very helpful."
  ]

  # Generate historical comments
  all_posts.each do |post|
    comment_count = case rand(100)
    when 0..20 then 0
    when 21..50 then rand(1..3)
    when 51..80 then rand(2..8)
    when 81..95 then rand(5..15)
    else rand(10..25)
    end

    comment_count.times do
      user = all_users.sample
      Comment.create!(
        user: user,
        post: post,
        content: comment_templates.sample,
        created_at: rand(post.created_at..Time.current)
      )
    end
  end

  puts "\nGenerated additional historical data:"
  puts "- #{additional_users.count} additional users"
  puts "- #{additional_posts.count} additional posts"
end

# Display some statistics
puts "\nFinal Statistics:"
puts "Total users: #{User.count}"
puts "Total posts: #{Post.count}"
puts "Total comments: #{Comment.count}"
puts "Published posts: #{Post.where(published: true).count}"
puts "Recent posts (last week): #{Post.where(created_at: 1.week.ago..).count}"
puts "Popular posts (2+ comments): #{Post.joins(:comments).group('posts.id').having('COUNT(comments.id) >= 2').count.keys.length}"

if ENV["GENERATE_HISTORICAL_DATA"] == "true"
  puts "\nRails Pulse Statistics:"
  puts "Routes: #{RailsPulse::Route.count}"
  puts "Queries: #{RailsPulse::Query.count}"
  puts "Requests: #{RailsPulse::Request.count}"
  puts "Operations: #{RailsPulse::Operation.count}"
  puts "Average request duration: #{RailsPulse::Request.average(:duration).to_f.round(2)} ms"
  puts "Error rate: #{(RailsPulse::Request.where(is_error: true).count.to_f / RailsPulse::Request.count * 100).round(2)}%"

  # Generate day summaries for all historical data
  puts "\nGenerating day summaries for all historical data..."

  # Find the earliest Rails Pulse data to determine start time
  earliest_request = RailsPulse::Request.minimum(:occurred_at)
  earliest_operation = RailsPulse::Operation.minimum(:occurred_at)

  historical_start_time = if earliest_request && earliest_operation
    [ earliest_request, earliest_operation ].min.beginning_of_day
  elsif earliest_request
    earliest_request.beginning_of_day
  elsif earliest_operation
    earliest_operation.beginning_of_day
  else
    puts "No Rails Pulse data found - skipping summary generation"
    return
  end

  historical_end_time = Time.current

  puts "Creating day summaries from #{historical_start_time.strftime('%B %d, %Y at %I:%M %p')} to #{historical_end_time.strftime('%B %d, %Y at %I:%M %p')}"
  RailsPulse::BackfillSummariesJob.perform_now(historical_start_time, historical_end_time, [ "day" ])

  # Generate hour summaries for the past 16 hours only
  puts "\nGenerating hour summaries for the past 26 hours..."
  hourly_start_time = 26.hours.ago
  hourly_end_time = Time.current

  puts "Creating hourly summaries from #{hourly_start_time.strftime('%B %d, %Y at %I:%M %p')} to #{hourly_end_time.strftime('%B %d, %Y at %I:%M %p')}"
  RailsPulse::BackfillSummariesJob.perform_now(hourly_start_time, hourly_end_time, [ "hour" ])

  puts "Summary generation completed!"
  puts "Generated summaries: #{RailsPulse::Summary.count}"

  # Generate realistic query analysis for some complex queries
  puts "\nGenerating query analysis data for complex queries..."

  # First, ensure complex queries have operations for analysis
  puts "Ensuring complex queries have operations..."

  complex_queries_without_ops = created_queries.select do |query|
    sql = query.normalized_sql
    # Identify complex queries that should have operations
    is_complex = sql.include?("SELECT *") ||
                 (sql.match?(/^SELECT.*FROM/i) && !sql.include?("WHERE")) ||
                 sql.scan(/\bJOIN\b/i).length > 2 ||
                 sql.include?("(SELECT") ||
                 sql.scan(/\bAND\b|\bOR\b/i).length > 3 ||
                 sql.include?("GROUP BY") ||
                 sql.include?("HAVING")

    is_complex && !query.operations.exists?
  end

  puts "  Found #{complex_queries_without_ops.count} complex queries without operations"

  # Create operations for these complex queries
  analytics_route = created_routes.find { |r| r.path.include?("complex") } || created_routes.first

  complex_queries_without_ops.each do |query|
    # Create 2-4 operations for each complex query
    operation_count = rand(2..4)

    operation_count.times do
      request = RailsPulse::Request.create!(
        route: analytics_route,
        duration: rand(300.0..1200.0), # Complex queries are slower
        status: [ 200, 200, 200, 500 ].sample, # Occasional errors
        is_error: rand < 0.1, # 10% error rate
        request_uuid: SecureRandom.uuid,
        occurred_at: rand(historical_start_time..historical_end_time)
      )

      RailsPulse::Operation.create!(
        request: request,
        query: query,
        operation_type: "sql",
        label: query.normalized_sql,
        duration: rand(100.0..400.0),
        codebase_location: [
          "app/controllers/analytics_controller.rb:#{rand(20..80)}",
          "app/controllers/reports_controller.rb:#{rand(15..60)}",
          "app/controllers/dashboard_controller.rb:#{rand(25..90)}"
        ].sample,
        start_time: rand(0..50),
        occurred_at: request.occurred_at
      )
    end
    print "."
  end

  puts "\n  Created operations for #{complex_queries_without_ops.count} complex queries"

  # Select queries that now have operations for analysis
  complex_queries_for_analysis = RailsPulse::Query.joins(:operations).distinct.limit(20)

  puts "Analyzing #{complex_queries_for_analysis.count} complex queries..."

  analyzed_successfully = 0

  complex_queries_for_analysis.each do |query|
    begin
      # Only analyze queries that have operations (remove time restriction for seed data)
      if query.operations.exists?
        puts "  Analyzing query #{query.id}: #{query.normalized_sql[0..80]}..."
        RailsPulse::QueryAnalysisService.analyze_query(query.id)
        analyzed_successfully += 1
        print "."
      else
        puts "  Skipping query #{query.id}: no operations"
      end
    rescue => e
      puts "  Failed to analyze query #{query.id}: #{e.message}"
      puts "  Error backtrace: #{e.backtrace.first(3).join('; ')}"
    end
  end

  puts "\n  Successfully analyzed: #{analyzed_successfully}"

  analyzed_count = RailsPulse::Query.where.not(analyzed_at: nil).count
  puts "\n\nQuery analysis completed!"
  puts "Analyzed queries: #{analyzed_count}"
  puts "Total issues detected: #{RailsPulse::Query.where.not(issues: [ nil, "[]" ]).count}"
  puts "Queries with suggestions: #{RailsPulse::Query.where.not(suggestions: [ nil, "[]" ]).count}"

  # Display some example analysis results
  if analyzed_count > 0
    puts "\nExample analysis results:"
    RailsPulse::Query.where.not(analyzed_at: nil).limit(3).each do |analyzed_query|
      puts "\nQuery: #{analyzed_query.normalized_sql[0..100]}..."
      if analyzed_query.issues.any?
        puts "  Issues (#{analyzed_query.issues.count}):"
        analyzed_query.issues.first(2).each do |issue|
          puts "    - #{issue['severity'].upcase}: #{issue['description']}"
        end
      end
      if analyzed_query.suggestions.any?
        puts "  Suggestions (#{analyzed_query.suggestions.count}):"
        analyzed_query.suggestions.first(2).each do |suggestion|
          puts "    - #{suggestion['type'].upcase}: #{suggestion['action']}"
        end
      end
    end
  end

  # Generate summaries for the complex queries we just created operations for
  puts "\nGenerating summaries for newly created complex query operations..."
  puts "This ensures complex queries appear on the index page."

  RailsPulse::BackfillSummariesJob.perform_now(historical_start_time, historical_end_time, [ "day" ])
  RailsPulse::BackfillSummariesJob.perform_now(hourly_start_time, hourly_end_time, [ "hour" ])

  puts "Final summary count: #{RailsPulse::Summary.count}"
  puts "Queries with summaries: #{RailsPulse::Query.joins(:summaries).distinct.count}"
end

# Generate large dataset for testing cleanup FK violations
if ENV["GENERATE_LARGE_DATA"] == "true"
  puts "\n" + ("=" * 80)
  puts "GENERATING LARGE DATASET FOR CLEANUP TESTING"
  puts "=" * 80
  puts "\nThis will create a scenario that reproduces the FK violation issue:"
  puts "- 12,000+ requests (exceeding the 10,000 limit)"
  puts "- Oldest requests will have operations that shouldn't be deleted"
  puts "- This tests count-based cleanup with FK constraints\n\n"

  # Clear existing Rails Pulse data
  puts "Clearing existing Rails Pulse data..."
  RailsPulse::Operation.destroy_all
  RailsPulse::Query.destroy_all
  RailsPulse::Request.destroy_all
  RailsPulse::Route.destroy_all
  RailsPulse::Summary.destroy_all

  # Create routes
  puts "Creating routes..."
  routes_data = [
    { method: "GET", path: "/" },
    { method: "GET", path: "/users" },
    { method: "GET", path: "/posts" },
    { method: "POST", path: "/posts" },
    { method: "GET", path: "/api/data" }
  ]

  created_routes = routes_data.map { |route_data| RailsPulse::Route.create!(route_data) }

  # Create a few queries
  puts "Creating queries..."
  queries_data = [
    "SELECT * FROM users WHERE id = ?",
    "SELECT * FROM posts WHERE user_id = ?",
    "INSERT INTO posts (title, content) VALUES (?, ?)",
    "UPDATE posts SET title = ? WHERE id = ?",
    "SELECT COUNT(*) FROM comments WHERE post_id = ?"
  ]

  created_queries = queries_data.map { |sql| RailsPulse::Query.create!(normalized_sql: sql) }

  # Generate 12,500 requests to exceed the 10,000 limit
  request_count = 12_500
  puts "Generating #{request_count} requests over 5 weeks..."

  requests_created = []
  request_count.times do |i|
    route = created_routes.sample
    # Distribute evenly over 5 weeks (35 days)
    occurred_at = 5.weeks.ago + (i.to_f / request_count * 35.days)

    request = RailsPulse::Request.create!(
      route: route,
      duration: rand(50..500),
      status: [ 200, 201, 200, 200 ].sample,
      is_error: false,
      request_uuid: SecureRandom.uuid,
      controller_action: "#{route.path.split('/')[1] || 'home'}#index",
      occurred_at: occurred_at
    )

    requests_created << request
    print "." if i % 500 == 0
  end

  puts "\n\nCreated #{requests_created.count} requests"
  puts "Oldest request: #{requests_created.first.occurred_at}"
  puts "Newest request: #{requests_created.last.occurred_at}"

  # Now create operations ONLY for the oldest 3,000 requests
  # BUT set their occurred_at to be RECENT (within retention period)
  # This creates the problematic scenario:
  # - Requests are old and exceed the count limit
  # - Time-based cleanup won't delete the recent operations
  # - Count-based cleanup will try to delete old requests
  # - But those requests still have recent operations attached
  # - FK violation!
  puts "\nCreating RECENT operations for the oldest 3,000 requests..."
  puts "Operations will be timestamped within the retention period."
  puts "This creates the FK violation scenario when cleanup runs.\n"

  operations_to_create = requests_created.first(3_000)
  operation_count = 0

  operations_to_create.each_with_index do |request, i|
    # Create 2-4 operations per request
    ops_per_request = rand(2..4)

    ops_per_request.times do
      query = created_queries.sample
      # KEY: Set operation occurred_at to be RECENT (within last 7 days)
      # This ensures time-based cleanup won't delete these operations
      recent_occurred_at = rand(7.days.ago..Time.current)

      RailsPulse::Operation.create!(
        request: request,
        query: query,
        operation_type: "sql",
        label: query.normalized_sql,
        duration: rand(10..100),
        codebase_location: "app/models/post.rb:#{rand(10..50)}",
        start_time: rand(0..20),
        occurred_at: recent_occurred_at  # RECENT timestamp!
      )
      operation_count += 1
    end

    print "." if i % 300 == 0
  end

  puts "\n\nCreated #{operation_count} operations"
  puts "Operations are associated with the oldest #{operations_to_create.count} requests"

  puts "\n" + ("=" * 80)
  puts "LARGE DATASET GENERATION COMPLETE"
  puts "=" * 80
  puts "\nFinal Statistics:"
  puts "  Routes: #{RailsPulse::Route.count}"
  puts "  Queries: #{RailsPulse::Query.count}"
  puts "  Requests: #{RailsPulse::Request.count}"
  puts "  Operations: #{RailsPulse::Operation.count}"
  puts "\nRequests exceeding limit of 10,000: #{RailsPulse::Request.count - 10_000}"
  puts "Oldest requests with operations: #{RailsPulse::Request.joins(:operations).where('rails_pulse_requests.occurred_at < ?', 3.weeks.ago).count}"
  puts "\nTo test the FK violation, run: rake rails_pulse:cleanup"
  puts "Expected: FK violation when trying to delete old requests that still have operations"
end
