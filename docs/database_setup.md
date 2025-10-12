# Rails Pulse Database Setup & Migrations

Rails Pulse uses a **single source of truth approach** for database management, following the solid_queue pattern. This combines the simplicity of schema-based installation with the flexibility of migrations for upgrades.

## Overview

- **Single Source of Truth**: One master schema file in the gem
- **Initial Installation**: Schema file copied and loaded via migration
- **Future Changes**: Individual migrations in dedicated directory
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
2. Copy `db/rails_pulse_schema.rb` (single source of truth)
3. Create an installation migration in `db/migrate/` that loads the schema
4. Create `db/rails_pulse_migrate/` directory for future migrations

**Next steps:**
```bash
rails db:migrate    # Create Rails Pulse tables via schema loading
```

The schema file `db/rails_pulse_schema.rb` remains as your single source of truth and should not be deleted.

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
rails db:prepare  # Creates database and loads schema automatically
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
```

The schema file remains as your single source of truth and should not be deleted.

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

The schema file `db/rails_pulse_schema.rb` should always be kept as your single source of truth:
- **Single database**: Keep schema file, migrations load from it
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


## Architecture: Single Source of Truth

### How It Works

Rails Pulse follows the **solid_queue pattern** for database management:

1. **Master Schema**: One canonical schema file in the gem at `lib/generators/rails_pulse/templates/db/rails_pulse_schema.rb`
2. **Installation**: Generator copies the schema to your app's `db/rails_pulse_schema.rb`
3. **Migration Loading**: Installation migration loads and executes the schema file at runtime
4. **Future Updates**: Individual migrations in `db/rails_pulse_migrate/` for incremental changes

### Migration Class Names

The installation migration follows Rails conventions:
- Class name: `InstallRailsPulseTables` (without timestamp)
- Filename includes timestamp: `YYYYMMDDHHMMSS_install_rails_pulse_tables.rb`
- Rails uses the filename timestamp to track migration status
- The generator creates a new timestamped file each time it runs

### Migration Approach

The installation migration doesn't duplicate table definitions. Instead, it:
- **Loads the schema file at runtime**: `load schema_file`
- **Executes the schema dynamically**: `RailsPulse::Schema.call(connection)`
- **Ensures automatic synchronization**: Always reflects the current schema

### Benefits

1. **Single Source of Truth**: Schema definition exists in one place
2. **No Sync Issues**: Migration always loads the current schema
3. **Maintainer Friendly**: Gem developers only update one file
4. **Clean Installation**: New users get all tables at once, not 20+ migrations
5. **Future-Proof**: Can add incremental migrations for schema evolution

