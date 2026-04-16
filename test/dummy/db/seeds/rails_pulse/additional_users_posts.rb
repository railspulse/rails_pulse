module RailsPulse
  module Seeds
    module AdditionalUsersAndPosts
      def self.seed!
        print "Generating additional users and posts"

        additional_users = create_additional_users
        additional_posts = create_additional_posts(additional_users)
        create_additional_comments(additional_users, additional_posts)

        puts "\nCreated #{additional_users.count} additional users, #{additional_posts.count} posts"
      end

      private

      def self.create_additional_users
        first_names = %w[Isabella Jack Kate Liam Maya Noah Olivia Parker Quinn Ruby Sam Tara Ulysses Victoria William Xavier Yara Zoe Alexander Benjamin Charlotte Daniel Elizabeth Felix Gabriel Hannah Isaac Julia Kevin Luna Marcus Natalie Oscar Penelope]
        last_names = %w[Anderson Thomas Jackson White Harris Martin Thompson Garcia Martinez Robinson Clark Rodriguez Lewis Lee Walker Hall Allen Young Hernandez King Wright Lopez Hill Green Adams Baker Gonzalez Nelson Carter Mitchell]
        domains = %w[example.com gmail.com yahoo.com outlook.com company.org tech.io startup.com]

        users = []
        150.times do |i|
          first = first_names.sample
          last = last_names.sample
          email = "#{first.downcase}.#{last.downcase}#{i + 100}@#{domains.sample}"

          users << User.create!(
            name: "#{first} #{last}",
            email: email,
            created_at: rand(5.weeks.ago..Time.current)
          )

          print "." if i % 30 == 0
        end

        users
      end

      def self.create_additional_posts(additional_users)
        all_users = User.all.to_a

        topics = [
          "Advanced Rails Patterns", "Database Performance Tuning", "Microservices Architecture", "GraphQL Implementation",
          "Redis Caching Strategies", "Background Job Processing", "API Rate Limiting", "OAuth Integration",
          "Docker Containerization", "Kubernetes Deployment", "CI/CD Pipelines", "Monitoring and Alerting",
          "Code Quality Metrics", "Refactoring Techniques", "Design Patterns", "Test-Driven Development",
          "Frontend Frameworks", "State Management", "Progressive Web Apps", "Mobile Development",
          "Machine Learning Integration", "Data Visualization", "Analytics Implementation", "A/B Testing",
          "User Authentication", "Authorization Patterns", "Session Management", "CORS Configuration",
          "Error Tracking", "Performance Optimization", "Memory Management", "Debugging Techniques"
        ]

        templates = [
          "This comprehensive guide covers %s. We'll explore the fundamentals and advanced techniques that every developer should know.",
          "In this detailed article about %s, we dive deep into practical examples and real-world applications that you can implement today.",
          "Understanding %s is crucial for modern web development. Here's everything you need to know to get started with confidence.",
          "%s has become increasingly important in today's development landscape. Let's explore the best practices and common pitfalls to avoid.",
          "A practical approach to %s with step-by-step instructions and code examples for better implementation and maintainability.",
          "Deep dive into %s: from basic concepts to advanced implementation strategies that scale with your application.",
          "%s explained with real-world examples and actionable insights from production environments."
        ]

        posts = []
        800.times do |i|
          topic = topics.sample
          user = all_users.sample
          created_at = rand(5.weeks.ago..1.week.ago)

          posts << Post.create!(
            user: user,
            title: "#{topic}: #{%w[Complete Ultimate Practical Advanced Comprehensive Essential Modern].sample} #{%w[Guide Tutorial Overview Walkthrough Reference].sample}",
            content: (templates.sample % topic.downcase) + " Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.",
            published: rand < 0.85,
            created_at: created_at
          )

          print "." if i % 100 == 0
        end

        posts
      end

      def self.create_additional_comments(additional_users, additional_posts)
        all_users = User.all.to_a
        all_posts = Post.all.to_a

        templates = [
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
              content: templates.sample,
              created_at: rand(post.created_at..Time.current)
            )
          end
        end
      end
    end
  end
end
