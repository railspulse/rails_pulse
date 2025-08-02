# Contributing to Rails Pulse

Thank you for your interest in contributing to Rails Pulse! This guide will help you get started with contributing to this Rails performance monitoring gem.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Making Changes](#making-changes)
- [Testing](#testing)
- [Submitting Changes](#submitting-changes)
- [Code Style](#code-style)
- [Release Process](#release-process)

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). Please read and follow it in all interactions.

## Getting Started

### Prerequisites

- Ruby 3.0 or higher
- Rails 7.1 or higher
- SQLite3, PostgreSQL, or MySQL
- Node.js (for asset compilation)

### Development Setup

1. **Fork and clone the repository:**
   ```bash
   git clone https://github.com/your-username/rails_pulse.git
   cd rails_pulse
   ```

2. **Install dependencies:**
   ```bash
   bundle install
   npm install
   ```

3. **Set up the test database:**
   ```bash
   cd test/dummy
   rails db:setup
   cd ../..
   ```

4. **Build assets:**
   ```bash
   npm run build
   ```

5. **Run the test suite:**
   ```bash
   bundle exec rake test
   ```

6. **Start the dummy app (for testing):**
   ```bash
   cd test/dummy
   rails server
   ```

   Visit `http://localhost:3000/rails_pulse` to see Rails Pulse in action.

## Making Changes

### Development Workflow

1. **Create a feature branch:**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**
3. **Test your changes** (see Testing section)
4. **Commit with clear messages** (see Commit Messages)
5. **Push and create a pull request**

### Project Structure

```
rails_pulse/
├── app/                    # Rails Engine views, controllers, helpers
├── lib/                    # Core gem logic
│   ├── rails_pulse/
│   │   ├── middleware/     # Request collection middleware
│   │   ├── subscribers/    # Performance monitoring subscribers
│   │   ├── configuration.rb
│   │   └── engine.rb
├── db/migrate/            # Database migrations
├── test/                  # Test suite
│   └── dummy/             # Test Rails application
├── public/                # Pre-compiled assets
└── scripts/               # Build scripts for assets
```

### Areas for Contribution

- **Performance optimizations**
- **New monitoring features**
- **UI/UX improvements**
- **Documentation improvements**
- **Test coverage expansion**
- **Bug fixes**
- **Security enhancements**

## Testing

### Running Tests

```bash
# Run all tests
bundle exec rake test

# Run specific test files
bundle exec ruby test/models/rails_pulse/request_test.rb

# Run tests with coverage
COVERAGE=true bundle exec rake test
```

### Writing Tests

- Use Minitest (Rails default)
- Place model tests in `test/models/`
- Place controller tests in `test/controllers/`
- Place integration tests in `test/integration/`
- Use factories for test data (if available)

### Test Guidelines

- Write tests for all new functionality
- Maintain or improve test coverage
- Test edge cases and error conditions
- Use descriptive test names

## Code Style

### Ruby Style

Rails Pulse follows [Omakase Ruby Styling](https://github.com/rails/rubocop-rails-omakase):

```bash
# Check style
bundle exec rubocop

# Auto-fix style issues
bundle exec rubocop -a
```

### JavaScript/CSS Style

- Use existing build system and conventions
- Follow Rails Pulse's component-based CSS architecture
- Use Stimulus controllers for JavaScript functionality

### Key Style Guidelines

- Use 2 spaces for indentation
- Line length: 120 characters max
- Use descriptive method and variable names
- Add comments for complex logic
- Follow Rails conventions

## Submitting Changes

### Pull Request Process

1. **Ensure tests pass:**
   ```bash
   bundle exec rake test
   bundle exec rubocop
   ```

2. **Update documentation** if needed

3. **Create a clear pull request:**
   - Descriptive title
   - Detailed description of changes
   - Link to related issues
   - Include screenshots for UI changes

4. **Respond to feedback** promptly and constructively

### Commit Messages

Use clear, descriptive commit messages:

```
Add database query performance monitoring

- Implement query normalization for aggregation
- Add configurable slow query thresholds
- Include query source location tracking
```

Format: `<type>: <description>`

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

## Types of Contributions

### Bug Reports

When reporting bugs, include:
- Rails Pulse version
- Rails version
- Ruby version
- Steps to reproduce
- Expected vs actual behavior
- Relevant logs or screenshots

### Feature Requests

For new features, provide:
- Clear use case description
- Expected behavior
- Why this would benefit users
- Potential implementation approach

### Security Issues

**Do not open GitHub issues for security vulnerabilities.**

Email security issues to: hey@railspulse.com

## Development Tips

### Asset Development

```bash
# Watch for changes during development
npm run watch

# Build production assets
npm run build
```

### Database Changes

```bash
# Generate a new migration
cd test/dummy
rails generate migration YourMigrationName

# Run migrations
rails db:migrate
```

### Performance Testing

Test performance impact:
- Use real-world Rails applications
- Monitor memory usage
- Test with high traffic scenarios
- Benchmark before/after changes

## Release Process

(For maintainers)

1. Update `CHANGELOG.md`
2. Bump version in `lib/rails_pulse/version.rb`
3. Update documentation if needed
4. Create release PR
5. Tag release after merge
6. Publish to RubyGems

## Getting Help

- **GitHub Discussions**: For questions and ideas
- **GitHub Issues**: For bugs and feature requests
- **Email**: hey@railspulse.com for private inquiries

## License

By contributing to Rails Pulse, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing to Rails Pulse! 🚀