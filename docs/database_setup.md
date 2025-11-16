# Rails Pulse Database Setup & Migrations

Rails Pulse uses a **schema file as the single source of truth** for database structure. This provides clean installations for new users while supporting incremental migrations for upgrades.

## Overview

- **Master Schema File**: Defines all tables and columns in one place
- **Clean Installation**: New users get the complete schema at once
- **Incremental Upgrades**: Existing users get migrations for new features
- **Two Setup Options**: Single database (recommended) or separate database

## Installation

### Option 1: Single Database (Recommended)

Use your existing Rails database for Rails Pulse tables.

```bash
rails generate rails_pulse:install
rails db:migrate
```

This creates:
- `config/initializers/rails_pulse.rb` - Configuration
- `db/rails_pulse_schema.rb` - Schema definition (single source of truth)
- `db/migrate/TIMESTAMP_install_rails_pulse_tables.rb` - Installation migration
- `db/rails_pulse_migrate/.keep` - Directory for future migrations

### Option 2: Separate Database

Use a dedicated database for Rails Pulse data.

```bash
rails generate rails_pulse:install --database=separate
```

Then configure `config/database.yml`:

```yaml
development:
  rails_pulse:
    <<: *default
    database: storage/development_rails_pulse.sqlite3
    migrations_paths: db/rails_pulse_migrate

production:
  rails_pulse:
    adapter: postgresql
    database: myapp_rails_pulse
    username: <%= ENV['DB_USERNAME'] %>
    password: <%= ENV['DB_PASSWORD'] %>
    host: <%= ENV['DB_HOST'] %>
    migrations_paths: db/rails_pulse_migrate
```

Finally, create the database:

```bash
rails db:prepare
```

## Upgrading Rails Pulse

When you upgrade to a new version of Rails Pulse that includes new features, run the upgrade generator:

### For Single Database

```bash
rails generate rails_pulse:upgrade
rails db:migrate
```

### For Separate Database

```bash
rails generate rails_pulse:upgrade --database=separate
rails db:migrate
```

### What the Upgrade Generator Does

1. **Copies new migrations** from the gem to your app
2. **Detects missing columns** by comparing your database to the schema file (safety net)
3. **Provides clear instructions** for next steps

The generator automatically handles both upgrade paths:
- If new migrations exist in the gem → copies them to your app
- If no new migrations but missing columns → generates a migration for you

## Troubleshooting

### "Rails Pulse not detected"

Run the install generator first:

```bash
rails generate rails_pulse:install
rails db:migrate
```

### Missing columns after gem update

The upgrade generator detects and fixes this automatically:

```bash
rails generate rails_pulse:upgrade
rails db:migrate
```

### Database already exists error

If you see "database already exists" when running migrations:

**For single database:**
```bash
rails db:migrate:status  # Check if installation migration already ran
```

**For separate database:**
```bash
rails db:migrate:status:rails_pulse
```

### Schema file should not be deleted

The file `db/rails_pulse_schema.rb` is your single source of truth for the database structure. Keep this file even after running migrations - it's used by the upgrade generator to detect missing columns.

### Tables already exist error

If you see "table already exists" when running migrations, this usually happens when switching between branches or after a database restore.

**Cause**: The database has tables from a previous installation, but migrations are trying to create them again.

**Solution for single database:**
```bash
# Option 1: Drop and recreate (development only!)
rails db:drop db:create db:migrate

# Option 2: Skip to latest migration (if tables are correct)
rails db:migrate:status  # Check current state
# If install migration shows as "down" but tables exist, just run:
rails db:migrate  # The install migration is now idempotent and will skip existing tables
```

**Solution for separate database:**
```bash
# Option 1: Drop and recreate
rails db:drop db:create db:prepare

# Option 2: The schema file has built-in safety checks
rails db:prepare  # Will skip tables that already exist
```

**Why this is safe now**: As of v0.3+, both the install migration and schema file check if tables exist before creating them, so running migrations multiple times is safe.

### Branch switching workflow

When switching between git branches with different Rails Pulse versions:

**Single Database Setup:**
```bash
git checkout feature-branch
bundle install
rails db:migrate  # Idempotent - safe to run even if tables exist
```

**Separate Database Setup:**
```bash
git checkout feature-branch
bundle install
rails db:prepare  # Schema file will skip existing tables
```

**If you want a clean state:**
```bash
git checkout feature-branch
bundle install
rails db:drop db:create
rails db:migrate  # (single DB) or rails db:prepare (separate DB)
rails db:seed
```

### Running migrations twice

As of v0.3+, you can safely run migrations multiple times:

```bash
rails db:migrate
rails db:migrate  # Safe! Will skip tables that already exist
```

The install migration checks if Rails Pulse tables exist before creating them, and the schema file has similar safety checks.

## Architecture

### How Installation Works

1. **Schema File**: The gem ships with a complete schema definition
2. **Installation**: Copies schema to your app as `db/rails_pulse_schema.rb`
3. **Migration**: Creates a migration that loads and executes the schema
4. **Result**: All tables and columns created in one go

### How Upgrades Work

1. **New Feature Released**: Gem ships with new migration in `db/rails_pulse_migrate/`
2. **Bundle Update**: You update the gem version
3. **Upgrade Generator**: Copies new migration(s) to your app
4. **Rails Migrate**: You run the migration to apply changes

### Schema File Behavior

The schema file (`db/rails_pulse_schema.rb`) is designed for **fresh installations only**. It has important safety characteristics:

**What it does:**
- ✅ Creates missing tables
- ✅ Skips tables that already exist
- ✅ Safe to run multiple times
- ✅ Provides logging of what it's creating

**What it does NOT do:**
- ❌ Add columns to existing tables
- ❌ Modify existing columns
- ❌ Remove columns from tables
- ❌ Change indexes on existing tables

**Why this matters:**
The schema file represents the "ideal final state" for new installations. For existing installations, **you must use incremental migrations** to modify table structure.

**Example - Adding a new column:**

When adding a new feature that requires a database column:

1. Create an incremental migration in `db/rails_pulse_migrate/`:
   ```ruby
   # db/rails_pulse_migrate/20250120000000_add_priority_to_jobs.rb
   class AddPriorityToJobs < ActiveRecord::Migration[7.0]
     def change
       unless column_exists?(:rails_pulse_jobs, :priority)
         add_column :rails_pulse_jobs, :priority, :integer, default: 0
       end
     end
   end
   ```

2. Update the schema file to include the column (for new installations):
   ```ruby
   # db/rails_pulse_schema.rb
   unless connection.table_exists?(:rails_pulse_jobs)
     connection.create_table :rails_pulse_jobs do |t|
       # ... existing columns ...
       t.integer :priority, default: 0  # New column for fresh installs
     end
   end
   ```

3. Users run the upgrade generator to get the migration:
   ```bash
   rails generate rails_pulse:upgrade
   rails db:migrate
   ```

This approach ensures:
- **Fresh installations** get the complete schema with all columns
- **Existing installations** get the incremental migration to add the column
- **Safety** - the schema file never modifies existing tables

### Benefits

- **Clean for new users**: One migration installs everything
- **Safe for existing users**: Incremental migrations with safety checks
- **Automatic detection**: Upgrade generator catches skipped migrations
- **Standard Rails**: Familiar migration workflow
- **Reviewable changes**: See exactly what's changing before running migrations
- **Idempotent**: Schema file and migrations can run multiple times safely

## Examples

### Fresh Installation

```bash
# Install Rails Pulse
rails generate rails_pulse:install

# Create tables
rails db:migrate

# Start using Rails Pulse!
```

### Upgrading After Gem Update

```bash
# Update gem
bundle update rails_pulse

# Check for and copy new migrations
rails generate rails_pulse:upgrade

# Apply changes
rails db:migrate

# Restart server
rails restart
```

### Converting from Separate to Single Database

```bash
# 1. Export data from separate database
rails db:dump:rails_pulse > rails_pulse_backup.sql

# 2. Update database.yml (remove rails_pulse configuration)

# 3. Re-install in main database
rails generate rails_pulse:install --database=single
rails db:migrate

# 4. Import data
rails db:restore < rails_pulse_backup.sql
```
