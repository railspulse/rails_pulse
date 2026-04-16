module BaseData
  def self.seed!
    clear_existing_data
    users = create_users
    posts = create_posts(users)
    create_comments(users, posts)

    puts "Created #{User.count} users"
    puts "Created #{Post.count} posts"
    puts "Created #{Comment.count} comments"

    [ users, posts ]
  end

  private

  def self.clear_existing_data
    Comment.destroy_all
    Post.destroy_all
    User.destroy_all
  end

  def self.create_users
    users_data = [
      { name: "Alice Johnson", email: "alice@example.com" },
      { name: "Bob Smith", email: "bob@example.com" },
      { name: "Carol Williams", email: "carol@example.com" },
      { name: "David Brown", email: "david@example.com" },
      { name: "Emma Davis", email: "emma@example.com" },
      { name: "Frank Miller", email: "frank@example.com" },
      { name: "Grace Wilson", email: "grace@example.com" },
      { name: "Henry Taylor", email: "henry@example.com" }
    ]

    users_data.map { |user_data| User.create!(user_data) }
  end

  def self.create_posts(users)
    titles = [
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

    titles.map.with_index do |title, index|
      user = users[index % users.length]
      Post.create!(
        user: user,
        title: title,
        content: "This is the content for #{title}. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.",
        published: [ true, false ].sample,
        created_at: rand(4.weeks.ago..Time.current)
      )
    end
  end

  def self.create_comments(users, posts)
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

    posts.each do |post|
      comment_count = rand(0..5)
      comment_count.times do
        user = users.sample
        Comment.create!(
          user: user,
          post: post,
          content: comment_contents.sample,
          created_at: rand(post.created_at..Time.current)
        )
      end
    end
  end
end
