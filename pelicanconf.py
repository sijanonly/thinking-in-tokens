import os
AUTHOR = 'Sijan Bhandari'
SITENAME = 'Thinking in Tokens'
SITEURL = ""

PATH = "content"

TIMEZONE = 'Europe/Berlin'

DEFAULT_LANG = 'en'

OUTPUT_PATH = "output/"

ARTICLE_PATHS = ["articles"]
PAGE_PATHS = ["pages"]

STATIC_PATHS = [
    "images",
]

THEME = "theme/elegant"

# Feed settings
FEED_ALL_ATOM = "feeds/all.atom.xml"
CATEGORY_FEED_ATOM = "feeds/{slug}.atom.xml"

# URL settings
ARTICLE_URL = "articles/{date:%Y}/{date:%m}/{slug}/"
ARTICLE_SAVE_AS = "articles/{date:%Y}/{date:%m}/{slug}/index.html"

PAGE_URL = "pages/{slug}/"
PAGE_SAVE_AS = "pages/{slug}/index.html"

# Metadata
DEFAULT_CATEGORY = "Miscellaneous"
USE_FOLDER_AS_CATEGORY = False

# Feed generation is usually not desired when developing
TRANSLATION_FEED_ATOM = None
AUTHOR_FEED_ATOM = None
AUTHOR_FEED_RSS = None

# # Blogroll
# LINKS = [
#     ("Pelican", "https://getpelican.com/"),
#     ("Python.org", "https://www.python.org/"),
#     ("Jinja2", "https://palletsprojects.com/p/jinja/"),
#     ("You can modify those links in your config file", "#"),
# ]

# Social widget
# SOCIAL = [
#     ("You can add links in your config file", "#"),
#     ("Another social link", "#"),
# ]

DEFAULT_PAGINATION = 10

# Uncomment following line if you want document-relative URLs when developing
RELATIVE_URLS = True

DIRECT_TEMPLATES = [
    "index",
    "categories",
    "tags",
    "archives",
]

PLUGINS = [
    "render_math",
]
