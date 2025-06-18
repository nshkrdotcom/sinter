# 🚀 Sinter Development Workflow

This document describes the simple, visual development workflow for Sinter.

## ✨ Quick Development Script

The main development tool is `dev.exs` - a simple script that provides visual feedback on your code quality.

### Usage

```bash
# Run all checks (default)
elixir dev.exs
elixir dev.exs check

# Start file watcher (auto-run tests on changes)  
elixir dev.exs watch

# Show help
elixir dev.exs help
```

### What it checks

✅ **Format** - Code formatting (`mix format --check-formatted`)  
✅ **Compile** - Compilation without warnings (`mix compile`)  
✅ **Credo** - Code quality and style (`mix credo`)  
✅ **Tests** - All tests pass (`mix test`)
⚠️  **Dialyzer** - Type analysis (warnings allowed, non-critical)

### Example Output

```
🔍 Running Development Checks
============================

✅ Format     PASS
✅ Compile    PASS  
✅ Credo      PASS
✅ Tests      PASS
⚠️  Dialyzer   WARN

Summary:
⚠️ Some warnings found
Passed: 4 | Warned: 1 | Failed: 0
```

When there are issues:

```
🔍 Running Development Checks
============================

✅ Format     PASS
⚠️  Compile    WARN
✅ Credo      PASS
❌ Tests      FAIL

Summary:
💥 Some checks failed
Passed: 2 | Warned: 1 | Failed: 1

💡 Quick fixes:
  • Format code: mix format
  • Check details: mix credo
  • Run tests: mix test
```

## 🎯 Mix Aliases

Simple aliases for common tasks:

```bash
# Quick validation pipeline
mix check          # format + compile + credo + test

# Quality assurance (fast, no Dialyzer)
mix qa             # same as check

# Full QA with type checking
mix qa.full        # check + note about Dialyzer warnings being OK

# Test variations  
mix test.watch     # Watch mode with clear screen
mix test.quick     # Exclude slow tests
mix test.all       # Include all tests
```

## 🔄 Recommended Workflow

### 1. **Active Development**
```bash
# Start the watcher for instant feedback
elixir dev.exs watch
```

This runs tests automatically when you save files, providing instant feedback.

### 2. **Before Committing**
```bash
# Quick validation
elixir dev.exs

# Or using mix alias
mix check
```

### 3. **Full Quality Check**
```bash
# Complete validation including type checking
mix qa
```

## 🛠 Setup

The development script is ready to use out of the box. Dependencies:

- `mix_test_watch` - For file watching (already in `mix.exs`)
- Standard Elixir tooling (format, compile, credo, test)

## 🎨 Features

### Visual Feedback
- 🟢 **Green** - Everything passing
- 🟡 **Yellow** - Warnings (code still works)
- 🔴 **Red** - Errors (needs fixing)

### Non-Verbose Output
- Simple pass/fail indicators
- Quick summary with counts
- Helpful suggestions when issues found
- No overwhelming output or details unless needed

### Fast Execution
- Runs checks in sequence for clear feedback
- Caches compilation artifacts
- Only shows what you need to know

## 💡 Philosophy

This workflow prioritizes:

- **Speed** - Get feedback quickly
- **Clarity** - Simple pass/fail indicators  
- **Actionability** - Clear next steps when issues arise
- **Non-intrusive** - No pre-commit hooks or forced automation
- **Visual** - Easy to scan results at a glance

Perfect for rapid development cycles where you want quality feedback without friction!

## ⚡ CI/CD Integration

The development workflow integrates with CI:

- **GitHub Actions CI** - Runs all the same checks
- **Dialyzer in CI** - Configured to allow warnings (won't fail builds)
- **Type Safety** - Dialyzer warnings are non-critical, indicating overly-broad type specs

### Dialyzer Note
Dialyzer currently shows 11 "contract_supertype" warnings. These are **intentionally allowed** because:
- They indicate type specs are more general than Dialyzer's inference
- This is common and acceptable in library code  
- They don't represent actual bugs or issues
- CI is configured to continue despite these warnings

## 🚫 What's NOT included

- Pre-commit hooks (by design - you wanted to avoid these)
- Verbose output (keeps things clean)
- Complex configuration (works out of the box)
- Forced automation (you decide when to run checks)
- Dialyzer failure blocking (warnings are allowed)

The goal is happy, productive development with optional quality gates! 🎉 