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

## License

This project is open source. Feel free to contribute!