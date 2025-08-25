"""A simple Hacker News headline reader using Textual."""

from textual.app import App, ComposeResult
from textual.containers import Container, VerticalScroll
from textual.widgets import Header, Footer, Static, Button
from textual.reactive import reactive


class HeadlineWidget(Static):
    """A widget to display a news headline."""
    
    def __init__(self, title: str, url: str, score: int, **kwargs):
        super().__init__(**kwargs)
        self.title = title
        self.url = url
        self.score = score
    
    def compose(self) -> ComposeResult:
        yield Static(f"▲ {self.score} | {self.title}", classes="headline")
        yield Static(f"🔗 {self.url}", classes="url")


class HackerNewsApp(App):
    """A Textual app for browsing Hacker News headlines."""
    
    CSS_PATH = "styles.css"
    TITLE = "Hacker News Headlines"
    SUB_TITLE = "Built with Textual"
    
    # Sample data - in a real app, this would come from the HN API
    headlines = [
        {"title": "Show HN: My awesome new project", "url": "https://example.com/project", "score": 142},
        {"title": "Ask HN: What's your favorite Python library?", "url": "https://news.ycombinator.com/item?id=12345", "score": 89},
        {"title": "Python 3.13 is now available", "url": "https://python.org/news", "score": 234},
        {"title": "The future of web development", "url": "https://example.com/web-dev", "score": 156},
        {"title": "Show HN: Built a TUI app with Textual", "url": "https://github.com/example/textual-app", "score": 98},
    ]
    
    def compose(self) -> ComposeResult:
        """Compose the UI."""
        yield Header()
        with Container(id="main"):
            with VerticalScroll(id="headlines"):
                for headline in self.headlines:
                    yield HeadlineWidget(
                        title=headline["title"],
                        url=headline["url"],
                        score=headline["score"]
                    )
            yield Button("Refresh", id="refresh")
        yield Footer()
    
    def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle button press events."""
        if event.button.id == "refresh":
            self.notify("Headlines refreshed!")


def main():
    """Run the Hacker News headline reader."""
    app = HackerNewsApp()
    app.run()


if __name__ == "__main__":
    main()
