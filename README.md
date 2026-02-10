# Hacker News Headlines

A simple Terminal User Interface (TUI) application for browsing Hacker News headlines, built with Python and [Textual](https://github.com/Textualize/textual).

## Features

- Clean, modern terminal interface
- Browse sample Hacker News headlines
- Interactive refresh button
- Built with modern Python tooling (uv + textual)

## Requirements

- Python 3.12+
- [uv](https://github.com/astral-sh/uv) package manager

## Installation

1. Clone this repository:
```bash
git clone https://github.com/Green-Sight/hacker-news-headline.git
cd hacker-news-headline
```

2. Install dependencies using uv:
```bash
uv sync
```

## Usage

Run the application using uv:
```bash
uv run hacker-news-headline
```

Or run directly with Python:
```bash
uv run python -m hacker_news_headline.main
```

### Controls

- Use arrow keys or scroll to navigate through headlines
- Click the "Refresh" button to refresh the headlines
- Press `Ctrl+C` or `q` to quit

## Development

This project uses [uv](https://github.com/astral-sh/uv) for dependency management and virtual environment handling.

### Project Structure

- `hacker_news_headline/` - Main package directory
  - `main.py` - Main application file with the Textual app
  - `styles.css` - CSS styling for the TUI interface
  - `__init__.py` - Package initialization
- `pyproject.toml` - Project configuration and dependencies
- `.python-version` - Python version specification

### Adding Dependencies

```bash
uv add <package-name>
```

### Running in Development Mode

```bash
uv run hacker-news-headline
```

Or directly:
```bash
uv run python -m hacker_news_headline.main
```

## Dependencies

- [textual](https://github.com/Textualize/textual) - Modern Python TUI framework

## Additional Resources

### PostgreSQL Partitioning Guide

This repository includes comprehensive resources for PostgreSQL table partitioning.

**👉 Start here: [POSTGRES_PARTITIONING_README.md](POSTGRES_PARTITIONING_README.md)** - Complete overview with navigation guide

#### 📚 Documentation
- **[POSTGRES_PARTITIONING_GUIDE.md](POSTGRES_PARTITIONING_GUIDE.md)** - Complete guide (601 lines)
  - Detailed migration strategy with trigger-based dual-write approach
  - Safety mechanisms and rollback procedures
  - Performance considerations and optimization tips
  - Comprehensive troubleshooting guide

- **[POSTGRES_PARTITIONING_QUICK_REF.md](POSTGRES_PARTITIONING_QUICK_REF.md)** - Quick reference (387 lines)
  - Command cheat sheet for 10 common operations
  - Partition strategies (Range, List, Hash) with examples
  - Performance tips and anti-patterns
  - Maintenance schedules and monitoring queries

#### 💻 Code
- **[postgres_partitioning_example.sql](postgres_partitioning_example.sql)** - Production-ready script (637 lines)
  - Complete working example with IoT device measurements
  - Safe migration: existing table → partitioned table
  - Zero-downtime backfilling with batched approach
  - Trigger-based routing for incoming data during migration
  - Data integrity verification and rollback procedures
  - Automatic partition creation and maintenance functions

#### 🎯 Perfect For
- Time-series data from IoT devices
- High-volume measurement storage (millions of rows)
- Tables requiring data archival/retention policies
- Systems needing 10-100x query performance improvements
- Zero-downtime migrations on production systems

## License

This project is open source. Feel free to contribute!