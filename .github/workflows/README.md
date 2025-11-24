# CI/CD Pipeline

This repository uses GitHub Actions for continuous integration and code quality checks.

## Workflows

### CI Pipeline (`.github/workflows/ci.yml`)

The CI pipeline runs on every push to `main` or `develop` branches and on all pull requests.

#### Jobs

1. **Test**
   - Runs on: Ubuntu Latest
   - Elixir: 1.15.7
   - OTP: 26.1
   - Database: PostgreSQL 15
   - Steps:
     - Checkout code
     - Set up Elixir/OTP
     - Cache dependencies
     - Install dependencies
     - Compile with warnings as errors
     - Check code formatting
     - Run tests

2. **Assets**
   - Runs on: Ubuntu Latest
   - Elixir: 1.15.7 / OTP: 26.1
   - Builds frontend assets using Phoenix built-in tools (esbuild, tailwind)
   - Runs `mix assets.build` to compile CSS and JS
   - Ensures assets compile successfully

3. **Security**
   - Checks for vulnerable dependencies (`mix deps.audit`)
   - Runs security audit with Sobelow
   - Continues on error to not block merges

4. **Dialyzer** (Type Checking)
   - Performs static type analysis
   - Caches PLTs for faster execution
   - Continues on error to not block merges

## Running Checks Locally

### All checks
```bash
mix deps.get
mix compile --warnings-as-errors
mix format --check-formatted
mix test
mix credo --strict
mix dialyzer
mix sobelow --config
mix deps.audit
```

### Quick pre-commit check
```bash
mix precommit
```

## Configuration Files

- `.credo.exs` - Credo static analysis configuration
- `.sobelow-conf` - Sobelow security audit configuration
- `mix.exs` - Project dependencies including dev/test tools

## Dev Dependencies

The following tools are included for code quality:

- **Credo**: Static code analysis
- **Dialyxir**: Type checking with Dialyzer
- **Sobelow**: Security-focused static analysis
- **mix_audit**: Dependency vulnerability checker

## Continuous on Error

Some jobs (`credo`, `sobelow`, `dialyzer`, `mix_audit`) are set to `continue-on-error: true` to prevent blocking merges while the codebase is being improved. You can remove this once issues are resolved.
