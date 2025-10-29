"""
Scrapy Settings for GEOTEE Website Scraper
"""

import os

# Scrapy project name
BOT_NAME = 'geotee_scraper'

# Spiders modules
SPIDER_MODULES = ['scraper.spiders']
NEWSPIDER_MODULE = 'scraper.spiders'

# Crawl responsibly by identifying yourself
USER_AGENT = 'GeoteeChatbot/1.0 (+https://ai-geotee.cloud; contact@geotee.gr)'

# Obey robots.txt rules
ROBOTSTXT_OBEY = True

# Configure maximum concurrent requests
CONCURRENT_REQUESTS = 8
CONCURRENT_REQUESTS_PER_DOMAIN = 4
CONCURRENT_REQUESTS_PER_IP = 4

# Download delay (seconds)
# Ευγενικό crawling - δεν φορτώνει το website
DOWNLOAD_DELAY = 1
RANDOMIZE_DOWNLOAD_DELAY = True

# Disable cookies (enabled by default)
COOKIES_ENABLED = False

# Disable Telnet Console (enabled by default)
TELNETCONSOLE_ENABLED = False

# Override the default request headers
DEFAULT_REQUEST_HEADERS = {
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'el-GR,el;q=0.9,en-US;q=0.8,en;q=0.7',
    'Accept-Encoding': 'gzip, deflate, br',
}

# Enable or disable spider middlewares
SPIDER_MIDDLEWARES = {
    'scrapy.spidermiddlewares.httperror.HttpErrorMiddleware': 50,
    'scrapy.spidermiddlewares.offsite.OffsiteMiddleware': 500,
    'scrapy.spidermiddlewares.referer.RefererMiddleware': 700,
    'scrapy.spidermiddlewares.urllength.UrlLengthMiddleware': 800,
    'scrapy.spidermiddlewares.depth.DepthMiddleware': 900,
}

# Enable or disable downloader middlewares
DOWNLOADER_MIDDLEWARES = {
    'scrapy.downloadermiddlewares.useragent.UserAgentMiddleware': None,
    'scrapy.downloadermiddlewares.retry.RetryMiddleware': 90,
    'scrapy.downloadermiddlewares.httpcompression.HttpCompressionMiddleware': 810,
}

# Configure item pipelines
# Η σειρά των numbers καθορίζει τη σειρά εκτέλεσης (μικρότερο = πρώτο)
ITEM_PIPELINES = {
    'scraper.pipelines.knowledge_pipeline.KnowledgePipeline': 300,
    'scraper.pipelines.knowledge_pipeline.JsonExportPipeline': 400,
}

# Enable and configure the AutoThrottle extension
AUTOTHROTTLE_ENABLED = True
AUTOTHROTTLE_START_DELAY = 1
AUTOTHROTTLE_MAX_DELAY = 10
AUTOTHROTTLE_TARGET_CONCURRENCY = 2.0
AUTOTHROTTLE_DEBUG = False

# Enable and configure HTTP caching
HTTPCACHE_ENABLED = True
HTTPCACHE_EXPIRATION_SECS = 86400  # 24 hours
HTTPCACHE_DIR = 'httpcache'
HTTPCACHE_IGNORE_HTTP_CODES = [500, 502, 503, 504, 400, 403, 404, 408]
HTTPCACHE_STORAGE = 'scrapy.extensions.httpcache.FilesystemCacheStorage'

# Retry settings
RETRY_ENABLED = True
RETRY_TIMES = 3
RETRY_HTTP_CODES = [500, 502, 503, 504, 408, 429]

# Depth limit
DEPTH_LIMIT = 3  # Μέγιστο βάθος crawling (0 = infinite)
DEPTH_PRIORITY = 1

# URL length limit
URLLENGTH_LIMIT = 2048

# Redirect settings
REDIRECT_ENABLED = True
REDIRECT_MAX_TIMES = 5

# Timeout
DOWNLOAD_TIMEOUT = 30

# Logging
LOG_ENABLED = True
LOG_LEVEL = 'INFO'  # DEBUG, INFO, WARNING, ERROR, CRITICAL
LOG_FORMAT = '%(asctime)s [%(name)s] %(levelname)s: %(message)s'
LOG_DATEFORMAT = '%Y-%m-%d %H:%M:%S'

# Log file (αν θέλεις να γράφει σε αρχείο)
# LOG_FILE = '../logs/scraper.log'

# Stats
STATS_DUMP = True

# Memory limit (αν το spider καταναλώνει πολύ memory)
# MEMUSAGE_ENABLED = True
# MEMUSAGE_LIMIT_MB = 1024
# MEMUSAGE_WARNING_MB = 512

# Feed export settings (για export σε διάφορα formats)
FEED_EXPORT_ENCODING = 'utf-8'
FEED_STORAGES = {
    'file': 'scrapy.extensions.feedexport.FileFeedStorage',
}

FEED_EXPORTERS = {
    'json': 'scrapy.exporters.JsonItemExporter',
    'jsonlines': 'scrapy.exporters.JsonLinesItemExporter',
    'csv': 'scrapy.exporters.CsvItemExporter',
}

# Qdrant configuration (διαβάζονται από environment variables)
QDRANT_HOST = os.getenv('QDRANT_HOST', 'localhost')
QDRANT_PORT = int(os.getenv('QDRANT_PORT', 6333))

# Extensions
EXTENSIONS = {
    'scrapy.extensions.telnet.TelnetConsole': None,  # Disabled
    'scrapy.extensions.corestats.CoreStats': 500,
    'scrapy.extensions.logstats.LogStats': 500,
}

# DNS timeout
DNS_TIMEOUT = 60

# Respect meta robots tags
ROBOTSTXT_OBEY = True

# File patterns to ignore
FILES_URLS_FIELD = 'file_urls'
FILES_RESULT_FIELD = 'files'

# Request fingerprinter implementation
REQUEST_FINGERPRINTER_IMPLEMENTATION = '2.7'

# Twisted reactor
TWISTED_REACTOR = 'twisted.internet.asyncioreactor.AsyncioSelectorReactor'

# Feed export
FEED_EXPORT_INDENT = 2

# Scheduler priority queue
SCHEDULER_PRIORITY_QUEUE = 'scrapy.pqueues.ScrapyPriorityQueue'
