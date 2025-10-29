"""
GEOTEE Website Spider
Scrapy spider για scraping του geotee.gr website
"""

import scrapy
from urllib.parse import urljoin, urlparse
import hashlib
import re
from datetime import datetime


class GeoteeSpider(scrapy.Spider):
    name = 'geotee'
    allowed_domains = ['geotee.gr']
    start_urls = [
        'https://web.geotee.gr/',
    ]
    
    # Custom settings
    custom_settings = {
        'DEPTH_LIMIT': 3,  # Μέγιστο βάθος crawling
        'DOWNLOAD_DELAY': 1,  # Delay μεταξύ requests (ευγενικό crawling)
        'CONCURRENT_REQUESTS': 4,  # Ταυτόχρονα requests
        'ROBOTSTXT_OBEY': True,  # Σεβασμός του robots.txt
        'USER_AGENT': 'GeoteeChatbot/1.0 (+https://ai-geotee.cloud)',
    }
    
    def __init__(self, *args, **kwargs):
        super(GeoteeSpider, self).__init__(*args, **kwargs)
        self.visited_urls = set()
        self.scraped_count = 0
        
        # URLs που θέλουμε να αποφύγουμε
        self.exclude_patterns = [
            r'/login',
            r'/logout',
            r'/admin',
            r'/wp-admin',
            r'/wp-login',
            r'\.pdf$',
            r'\.jpg$',
            r'\.jpeg$',
            r'\.png$',
            r'\.gif$',
            r'\.zip$',
            r'\.doc$',
            r'\.docx$',
            r'/feed/',
            r'/rss/',
            r'/trackback/',
            r'\?replytocom=',
            r'/page/\d+/',  # Pagination
        ]
    
    def parse(self, response):
        """
        Κύρια parsing function - επεξεργάζεται κάθε σελίδα
        """
        # Έλεγχος αν η σελίδα έχει ήδη επισκεφθεί
        if response.url in self.visited_urls:
            return
        
        self.visited_urls.add(response.url)
        self.scraped_count += 1
        
        # Log
        self.logger.info(f"Scraping [{self.scraped_count}]: {response.url}")
        
        # Εξαγωγή περιεχομένου
        item = self.extract_content(response)
        
        if item and item.get('text'):
            yield item
        
        # Εύρεση και ακολούθηση links
        for link in self.extract_links(response):
            if self.should_follow_link(link):
                yield response.follow(link, callback=self.parse)
    
    def extract_content(self, response):
        """
        Εξαγωγή χρήσιμου περιεχομένου από τη σελίδα
        """
        # Τίτλος σελίδας
        title = response.css('title::text').get()
        if not title:
            title = response.css('h1::text').get()
        title = self.clean_text(title) if title else ''
        
        # Meta description
        meta_description = response.css('meta[name="description"]::attr(content)').get()
        meta_description = self.clean_text(meta_description) if meta_description else ''
        
        # Κύριο περιεχόμενο - προσπάθησε διάφορα selectors
        content_selectors = [
            'article ::text',
            '.content ::text',
            '.main-content ::text',
            '#content ::text',
            'main ::text',
            '.entry-content ::text',
            '.post-content ::text',
        ]
        
        text_content = []
        for selector in content_selectors:
            texts = response.css(selector).getall()
            if texts:
                text_content.extend(texts)
                break
        
        # Αν δεν βρέθηκε με τα παραπάνω, πάρε όλο το body
        if not text_content:
            text_content = response.css('body ::text').getall()
        
        # Καθαρισμός κειμένου
        text = ' '.join([self.clean_text(t) for t in text_content if t.strip()])
        text = self.remove_extra_whitespace(text)
        
        # Αποφυγή σελίδων με πολύ λίγο περιεχόμενο
        if len(text) < 100:
            self.logger.debug(f"Skipping (too short): {response.url}")
            return None
        
        # Εξαγωγή headings
        headings = []
        for h_level in range(1, 7):
            headings.extend(response.css(f'h{h_level}::text').getall())
        headings = [self.clean_text(h) for h in headings if h.strip()]
        
        # Εξαγωγή links
        links = response.css('a::attr(href)').getall()
        internal_links = [
            urljoin(response.url, link) 
            for link in links 
            if link and self.is_internal_link(link, response.url)
        ]
        
        # Δημιουργία unique ID
        url_hash = hashlib.md5(response.url.encode()).hexdigest()
        
        # Εξαγωγή category/section από URL
        category = self.extract_category(response.url)
        
        return {
            'id': url_hash,
            'url': response.url,
            'title': title,
            'meta_description': meta_description,
            'text': text,
            'headings': headings,
            'category': category,
            'word_count': len(text.split()),
            'internal_links': internal_links[:10],  # Κράτα μόνο τα πρώτα 10
            'scraped_at': datetime.now().isoformat(),
        }
    
    def extract_links(self, response):
        """
        Εξαγωγή όλων των links από τη σελίδα
        """
        # CSS selectors για links
        links = response.css('a::attr(href)').getall()
        
        # Καθαρισμός και normalization
        cleaned_links = []
        for link in links:
            if not link or link.startswith('#'):
                continue
            
            # Κάνε absolute URL
            absolute_url = urljoin(response.url, link)
            
            # Αφαίρεση URL fragments
            absolute_url = absolute_url.split('#')[0]
            
            # Αφαίρεση trailing slash για consistency
            absolute_url = absolute_url.rstrip('/')
            
            cleaned_links.append(absolute_url)
        
        return set(cleaned_links)  # Unique links
    
    def should_follow_link(self, url):
        """
        Καθορίζει αν θα πρέπει να ακολουθήσει ένα link
        """
        # Έλεγχος domain
        if not self.is_internal_link(url, self.start_urls[0]):
            return False
        
        # Έλεγχος αν έχει ήδη επισκεφθεί
        if url in self.visited_urls:
            return False
        
        # Έλεγχος exclude patterns
        for pattern in self.exclude_patterns:
            if re.search(pattern, url, re.IGNORECASE):
                return False
        
        return True
    
    def is_internal_link(self, link, base_url):
        """
        Ελέγχει αν ένα link είναι internal (ίδιο domain)
        """
        if not link:
            return False
        
        # Κάνε absolute
        absolute_link = urljoin(base_url, link)
        
        # Parse domains
        link_domain = urlparse(absolute_link).netloc
        base_domain = urlparse(base_url).netloc
        
        # Αφαίρεση www για σύγκριση
        link_domain = link_domain.replace('www.', '')
        base_domain = base_domain.replace('www.', '')
        
        return link_domain == base_domain
    
    def extract_category(self, url):
        """
        Εξαγωγή category από URL path
        """
        try:
            path = urlparse(url).path
            parts = [p for p in path.split('/') if p]
            
            if len(parts) >= 1:
                return parts[0]
            
            return 'homepage'
        except:
            return 'unknown'
    
    def clean_text(self, text):
        """
        Καθαρισμός κειμένου
        """
        if not text:
            return ''
        
        # Αφαίρεση HTML entities
        text = text.strip()
        
        # Αφαίρεση extra whitespace
        text = re.sub(r'\s+', ' ', text)
        
        # Αφαίρεση special characters που δεν χρειάζονται
        text = re.sub(r'[\r\n\t]+', ' ', text)
        
        return text.strip()
    
    def remove_extra_whitespace(self, text):
        """
        Αφαίρεση περιττών whitespaces
        """
        # Replace multiple spaces με ένα
        text = re.sub(r' +', ' ', text)
        
        # Replace multiple newlines με ένα
        text = re.sub(r'\n+', '\n', text)
        
        return text.strip()
    
    def closed(self, reason):
        """
        Called όταν το spider τελειώνει
        """
        self.logger.info(f"Spider closed: {reason}")
        self.logger.info(f"Total pages scraped: {self.scraped_count}")
        self.logger.info(f"Total unique URLs: {len(self.visited_urls)}")
