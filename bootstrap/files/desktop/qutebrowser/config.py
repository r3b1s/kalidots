config.load_autoconfig(False)

c.url.start_pages = ["about:blank"]
c.url.default_page = "about:blank"

# Search engines
c.url.searchengines = {
    "DEFAULT": "https://search.brave.com/search?q={}",
    "m": "https://leta.mullvad.net/search?q={}&engine=google",
    "mb": "https://leta.mullvad.net/search?q={}&engine=brave",
    "g": "https://www.google.com/search?q={}",
    "gm": "https://www.google.com/maps?q={}",
    "yt": "https://www.youtube.com/results?search_query={}",
    "b": "https://search.brave.com/search?q={}",
    "bing": "https://www.bing.com/search?q={}",
    "d": "https://duckduckgo.com/?q={}",
    "q": "https://www.qwant.com/?q={}",
    "wp": "https://www.wikipedia.org/w/index.php?title=Special:Search&search={}",
    "aw": "https://wiki.archlinux.org/index.php?search={}",
    "arch": "https://archlinux.org/packages/?sort=&q={}&maintainer=&flagged=",
    "aur": "https://aur.archlinux.org/packages?O=0&K={}",
    "pip": "https://pypi.org/search/?q={}",
    "gh": "https://github.com/search?q={}&type=repositories",
    "npm": "https://www.npmjs.com/search?q={}",
    "ud": "https://www.urbandictionary.com/define.php?term={}",
    "fh": "https://flathub.org/en/apps/search?q={}",
    "sk": "https://skills.sh/?q={}",
}

# Dark mode
c.colors.webpage.preferred_color_scheme = "dark"
c.colors.webpage.darkmode.enabled = True

# Ad blocker
c.content.blocking.enabled = True
c.content.blocking.method = "both"
