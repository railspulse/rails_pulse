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

  # Define realistic SQL queries
  queries_data = [
    "SELECT * FROM users WHERE id = ?",
    "SELECT users.*, COUNT(posts.id) as post_count FROM users LEFT JOIN posts ON users.id = posts.user_id GROUP BY users.id",
    "SELECT * FROM posts WHERE user_id = ? ORDER BY created_at DESC LIMIT ?",
    "SELECT posts.*, users.name FROM posts JOIN users ON posts.user_id = users.id WHERE posts.published = ?",
    "SELECT COUNT(*) FROM comments WHERE post_id = ?",
    "SELECT * FROM comments WHERE post_id = ? ORDER BY created_at DESC",
    "INSERT INTO posts (user_id, title, content, published, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
    "UPDATE posts SET title = ?, content = ?, updated_at = ? WHERE id = ?",
    "DELETE FROM posts WHERE id = ?",
    "SELECT * FROM users WHERE email = ?",
    "SELECT posts.* FROM posts WHERE title LIKE ? OR content LIKE ?",
    "SELECT users.*, COUNT(DISTINCT posts.id) as post_count, COUNT(DISTINCT comments.id) as comment_count FROM users LEFT JOIN posts ON users.id = posts.user_id LEFT JOIN comments ON users.id = comments.user_id GROUP BY users.id",
    "SELECT * FROM posts WHERE created_at > ? ORDER BY created_at DESC",
    "SELECT COUNT(*) FROM posts WHERE published = ? AND created_at > ?",
    "SELECT comments.*, posts.title, users.name FROM comments JOIN posts ON comments.post_id = posts.id JOIN users ON comments.user_id = users.id WHERE comments.created_at > ?"
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

      # Assign query for SQL operations
      query = operation_type == "sql" ? created_queries.sample : nil

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
        when /SELECT \* FROM users WHERE id = \?/
          "app/models/user.rb:15"
        when /SELECT users\.\*, COUNT\(posts\.id\) as post_count FROM users LEFT JOIN posts/
          "app/controllers/home_controller.rb:28"
        when /SELECT \* FROM posts WHERE user_id = \? ORDER BY created_at DESC LIMIT \?/
          "app/models/user.rb:23"
        when /SELECT posts\.\*, users\.name FROM posts JOIN users/
          "app/controllers/home_controller.rb:45"
        when /SELECT COUNT\(\*\) FROM comments WHERE post_id = \?/
          "app/models/post.rb:18"
        when /SELECT \* FROM comments WHERE post_id = \? ORDER BY created_at DESC/
          "app/controllers/home_controller.rb:67"
        when /INSERT INTO posts/
          "app/models/post.rb:8"
        when /UPDATE posts SET title = \?/
          "app/models/post.rb:35"
        when /DELETE FROM posts WHERE id = \?/
          "app/models/post.rb:42"
        when /SELECT \* FROM users WHERE email = \?/
          "app/models/user.rb:31"
        when /SELECT posts\.\* FROM posts WHERE title LIKE \? OR content LIKE \?/
          "app/controllers/home_controller.rb:89"
        when /SELECT users\.\*, COUNT\(DISTINCT posts\.id\) as post_count, COUNT\(DISTINCT comments\.id\)/
          "app/controllers/home_controller.rb:12"
        when /SELECT \* FROM posts WHERE created_at > \? ORDER BY created_at DESC/
          "app/models/post.rb:26"
        when /SELECT COUNT\(\*\) FROM posts WHERE published = \? AND created_at > \?/
          "app/controllers/home_controller.rb:34"
        when /SELECT comments\.\*, posts\.title, users\.name FROM comments JOIN posts/
          "app/controllers/home_controller.rb:78"
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
end
