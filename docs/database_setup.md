# Rails Pulse Database Setup & Migrations

Rails Pulse uses a **hybrid approach** for database management, combining the simplicity of schema-based installation with the flexibility of migrations for upgrades.

## Overview

- **Initial Installation**: Uses schema file for quick setup
- **Future Changes**: Uses regular Rails migrations
- **Two Setup Options**: Single database (recommended) or separate database

## Installation Options

### Option 1: Single Database Setup (Recommended)

Use your existing Rails database for Rails Pulse tables.

```bash
# Install with single database setup (default)
rails generate rails_pulse:install

# Or explicitly specify single database
rails generate rails_pulse:install --database=single
```

This will:
1. Copy `config/initializers/rails_pulse.rb` (configuration)
2. Create an installation migration in `db/migrate/`
3. The migration contains all Rails Pulse tables and indexes

**Next steps:**
```bash
rails db:migrate           # Create Rails Pulse tables
rm db/rails_pulse_schema.rb # Clean up (no longer needed)
```

### Option 2: Separate Database Setup

Use a dedicated database for Rails Pulse data.

```bash
# Install with separate database setup
rails generate rails_pulse:install --database=separate
```

This will:
1. Copy configuration files
2. Copy `db/rails_pulse_schema.rb` (schema file)
3. Create `db/rails_pulse_migrate/` directory for future migrations

**Next steps:**
1. Configure `config/database.yml`:
```yaml
development:
  rails_pulse:
    <<: *default
    database: storage/development_rails_pulse.sqlite3
    migrations_paths: db/rails_pulse_migrate
```

2. Create the database:
```bash
rails db:prepare  # Creates database and loads schema
```

## Upgrading Rails Pulse

### For Single Database Users

```bash
# Check for and apply updates
rails generate rails_pulse:upgrade

# Apply the migration
rails db:migrate
```

The upgrade generator:
- Detects your current setup automatically
- Creates migrations only for missing features
- Provides clear upgrade instructions

### For Separate Database Users

```bash
# Check for schema updates
rails generate rails_pulse:upgrade --database=separate

# Apply updates (when available)
rails db:migrate:rails_pulse
```

## Converting Between Setups

### From Schema-Only to Single Database

If you have `db/rails_pulse_schema.rb` but no tables:

```bash
# Convert schema to migration
rails generate rails_pulse:convert_to_migrations

# Apply the migration
rails db:migrate

# Clean up
rm db/rails_pulse_schema.rb
```

### From Separate to Single Database

1. Export your data from the separate database
2. Run the single database install
3. Import your data
4. Remove separate database configuration

## Troubleshooting

### "Rails Pulse not detected"

Run the upgrade generator to check your installation:
```bash
rails generate rails_pulse:upgrade
```

### Missing columns after upgrade

The upgrade generator automatically detects and adds missing columns:
```bash
rails generate rails_pulse:upgrade
rails db:migrate
```

### Schema file conflicts

If you have both migrations and schema file:
- **Single database**: Delete `db/rails_pulse_schema.rb`
- **Separate database**: Keep schema file, use `db/rails_pulse_migrate/` for migrations

## Advanced Configuration

### Custom Database Names

For separate database setup, customize the database name:

```yaml
production:
  rails_pulse:
    adapter: postgresql
    database: myapp_rails_pulse
    username: postgres
    password: <%= ENV['POSTGRES_PASSWORD'] %>
    host: localhost
    migrations_paths: db/rails_pulse_migrate
```

### Multiple Environments

Each environment can use different setups:
- Development: Single database for simplicity
- Production: Separate database for isolation

```yaml
development:
  # Main database config...

production:
  # Main database config...
  rails_pulse:
    # Separate Rails Pulse database for production
```


## DRY Architecture

### Single Source of Truth

The installation migration doesn't duplicate table definitions. Instead, it:
- **Loads the schema file at runtime**: `load schema_file`
- **Executes the schema dynamically**: `RailsPulse::Schema.call(connection)`
- **Ensures automatic synchronization**: No need to manually keep two files in sync

This eliminates the maintenance burden of keeping migration templates and schema files synchronized.

### Benefits

1. **No Duplication**: Schema definition exists only in `db/rails_pulse_schema.rb`
2. **Always Current**: Migration automatically gets latest schema changes
3. **Maintainer Friendly**: Gem developers only update one file
4. **Error Prevention**: Impossible for migration and schema to be out of sync

