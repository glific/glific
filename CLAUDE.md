# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Glific is an open-source two-way communication platform built with Elixir/Phoenix for the social sector. It enables organizations to communicate with users over WhatsApp via the Gupshup and Maytapi messaging platform. It has various features such as contact management, message handling, flow builder, and more. It also integrates with various third-party services such as Google Slides, Google Sheets, Google Drive, and more. Glific uses GraphQL for its API.

## Development Commands

### Build and Setup
```bash
# Initial setup (installs deps, compiles, resets DB, deploys assets)
mix setup

# Install dependencies
mix deps.get

# Reset database (drop, create, migrate, seed)
mix ecto.reset

# Run development server with interactive shell
iex -S mix phx.server
```

### Testing
```bash
# Run full test suite with fresh database
mix test_full

# Run tests (uses existing database)
mix test

# Run tests with Test Driven Development (TDD)
mix test.watch

# Run specific test file
mix test path/to/test_file.exs

# Run tests with coverage
mix coveralls
mix coveralls.html
mix coveralls.json
```

### Code Quality
```bash
# Format code
mix format

# Run Credo for code analysis
mix credo

# Run Dialyzer for type checking
mix dialyzer

# Run Sobelow for security analysis
mix sobelow

# Check code consistency
mix check
```

### Database Operations
```bash
# Create and migrate database
mix ecto.create
mix ecto.migrate

# Drop database
mix ecto.drop

# Reset database with scale data for testing
mix ecto.scale
```

## Architecture Overview

### Core Structure
- **lib/glific/** - Core business logic and domain models
  - `accounts/` - User authentication and account management
  - `contacts/` - Contact management system
  - `messages/` - Message handling and processing
  - `flows/` - Flow builder and conversation flows
  - `templates/` - HSM (WhatsApp Business) templates
  - `partners/` - Multi-tenant organization management
  - `communications/` - WhatsApp/Gupshup integration layer
  - `tags/` - Contact and message tagging system
  - `groups/` - Contact grouping functionality
  - `searches/` - Search and filtering capabilities

- **lib/glific_web/** - Phoenix web layer
  - `controllers/api/v1/` - REST API endpoints
  - `schema/` - GraphQL schema definitions
  - `resolvers/` - GraphQL resolvers
  - `router.ex` - API routing configuration

### Key Patterns

1. **Multi-tenancy**: The system is multi-tenant with organization-based data isolation. Most queries use `organization_id` for scoping.

2. **Context Pattern**: Business logic is organized into contexts (e.g., `Glific.Contacts`, `Glific.Messages`) following Phoenix conventions.

3. **GraphQL API**: Primary API is GraphQL-based using Absinthe, with REST endpoints for webhooks and external integrations.

4. **Background Jobs**: Uses Oban Pro for background job processing (message sending, webhook processing, scheduled flows).

5. **Authentication**: Token-based authentication with JWT, managed through `Glific.Accounts`.

## External Dependencies

### Critical Services
- **Gupshup**: WhatsApp Business API provider (configured in dev.secret.exs)
- **Oban Pro**: Background job processing (requires license key)
- **PostgreSQL**: Primary database (v13+ recommended)

### Environment Configuration
- Development secrets: `config/dev.secret.exs`
- Environment variables: `config/.env.dev`
- SSL certificates: `priv/cert/` (for local HTTPS)

## Testing Approach

- Tests are in `test/` mirroring the `lib/` structure
- Uses ExUnit with factories for test data generation
- Database sandboxing for isolated test transactions
- Full test suite resets database before running (`mix test_full`)

## Important Notes

- Always check `organization_id` scoping for multi-tenant queries
- HSM templates must be synced from Gupshup: `Glific.Templates.sync_hsms_from_bsp(1)`
- Background jobs are processed by Oban workers in `lib/glific/jobs/`
- WebSocket connections for real-time updates use Phoenix Channels
- API authentication required for all GraphQL endpoints except registration
