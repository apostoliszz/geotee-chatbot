"""
GEOTEE Knowledge Base Pipeline
Scrapy pipeline που στέλνει τα scraped δεδομένα στο Qdrant vector database
"""

import os
import json
from typing import List, Dict, Any
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams, PointStruct
from sentence_transformers import SentenceTransformer
import logging


class KnowledgePipeline:
    """
    Pipeline για indexing scraped content στο Qdrant
    """
    
    def __init__(self):
        self.logger = logging.getLogger(__name__)
        
        # Qdrant configuration
        self.qdrant_host = os.getenv('QDRANT_HOST', 'localhost')
        self.qdrant_port = int(os.getenv('QDRANT_PORT', 6333))
        self.collection_name = 'geotee_kb'
        
        # Embedding model
        self.model_name = 'paraphrase-multilingual-MiniLM-L12-v2'  # Υποστηρίζει Ελληνικά
        
        # Initialize στο open_spider
        self.client = None
        self.model = None
        self.items_processed = 0
        self.items_indexed = 0
    
    def open_spider(self, spider):
        """
        Called όταν ξεκινάει το spider
        """
        self.logger.info("Initializing Knowledge Base Pipeline...")
        
        try:
            # Connect to Qdrant
            self.client = QdrantClient(
                host=self.qdrant_host,
                port=self.qdrant_port,
                timeout=30
            )
            self.logger.info(f"Connected to Qdrant at {self.qdrant_host}:{self.qdrant_port}")
            
            # Load embedding model
            self.logger.info(f"Loading embedding model: {self.model_name}")
            self.model = SentenceTransformer(self.model_name)
            self.logger.info("Embedding model loaded successfully")
            
            # Create or recreate collection
            self.setup_collection()
            
        except Exception as e:
            self.logger.error(f"Failed to initialize pipeline: {e}")
            raise
    
    def setup_collection(self):
        """
        Δημιουργία ή επαναδημιουργία collection στο Qdrant
        """
        try:
            # Έλεγχος αν υπάρχει ήδη το collection
            collections = self.client.get_collections().collections
            collection_exists = any(c.name == self.collection_name for c in collections)
            
            if collection_exists:
                self.logger.info(f"Collection '{self.collection_name}' already exists")
                # Uncomment αν θέλεις να κάνει recreate κάθε φορά
                # self.logger.info(f"Deleting existing collection '{self.collection_name}'")
                # self.client.delete_collection(self.collection_name)
            
            if not collection_exists:
                # Πάρε το vector size από το model
                vector_size = self.model.get_sentence_embedding_dimension()
                
                self.logger.info(f"Creating collection '{self.collection_name}' with vector size {vector_size}")
                
                self.client.create_collection(
                    collection_name=self.collection_name,
                    vectors_config=VectorParams(
                        size=vector_size,
                        distance=Distance.COSINE
                    )
                )
                
                self.logger.info(f"Collection '{self.collection_name}' created successfully")
        
        except Exception as e:
            self.logger.error(f"Failed to setup collection: {e}")
            raise
    
    def process_item(self, item, spider):
        """
        Process κάθε item που έρχεται από το spider
        """
        self.items_processed += 1
        
        try:
            # Δημιουργία text για embedding
            text_to_embed = self.prepare_text_for_embedding(item)
            
            # Skip αν το text είναι πολύ μικρό
            if len(text_to_embed) < 50:
                self.logger.debug(f"Skipping item (too short): {item['url']}")
                return item
            
            # Δημιουργία embedding
            embedding = self.create_embedding(text_to_embed)
            
            # Προετοιμασία payload
            payload = {
                'url': item['url'],
                'title': item['title'],
                'meta_description': item.get('meta_description', ''),
                'text': item['text'][:1000],  # Κράτα τα πρώτα 1000 chars για preview
                'full_text': item['text'],  # Ολόκληρο το text
                'category': item.get('category', 'unknown'),
                'word_count': item.get('word_count', 0),
                'headings': item.get('headings', [])[:5],  # Κράτα τα πρώτα 5 headings
                'scraped_at': item.get('scraped_at', ''),
            }
            
            # Upload στο Qdrant
            point = PointStruct(
                id=item['id'],
                vector=embedding.tolist(),
                payload=payload
            )
            
            self.client.upsert(
                collection_name=self.collection_name,
                points=[point]
            )
            
            self.items_indexed += 1
            
            if self.items_indexed % 10 == 0:
                self.logger.info(f"Indexed {self.items_indexed} items...")
            
            return item
        
        except Exception as e:
            self.logger.error(f"Failed to process item {item.get('url', 'unknown')}: {e}")
            return item
    
    def prepare_text_for_embedding(self, item: Dict[str, Any]) -> str:
        """
        Προετοιμασία κειμένου για embedding
        Συνδυάζει τίτλο, meta description και κύριο κείμενο
        """
        parts = []
        
        # Τίτλος (με βάρος)
        if item.get('title'):
            parts.append(f"{item['title']}. {item['title']}.")  # Επανάληψη για έμφαση
        
        # Meta description
        if item.get('meta_description'):
            parts.append(item['meta_description'])
        
        # Headings
        if item.get('headings'):
            parts.extend(item['headings'][:3])  # Πρώτα 3 headings
        
        # Κύριο κείμενο (περιορισμένο)
        if item.get('text'):
            # Πάρε τα πρώτα 500 words
            words = item['text'].split()[:500]
            parts.append(' '.join(words))
        
        # Συνδυασμός
        combined_text = ' '.join(parts)
        
        # Καθαρισμός
        combined_text = ' '.join(combined_text.split())  # Remove extra whitespace
        
        return combined_text
    
    def create_embedding(self, text: str) -> Any:
        """
        Δημιουργία embedding vector από κείμενο
        """
        try:
            # Truncate αν είναι πολύ μεγάλο (το model έχει όριο)
            max_length = 512  # tokens
            
            # Encode
            embedding = self.model.encode(
                text,
                convert_to_tensor=False,
                show_progress_bar=False
            )
            
            return embedding
        
        except Exception as e:
            self.logger.error(f"Failed to create embedding: {e}")
            raise
    
    def close_spider(self, spider):
        """
        Called όταν κλείνει το spider
        """
        self.logger.info("Closing Knowledge Base Pipeline...")
        self.logger.info(f"Total items processed: {self.items_processed}")
        self.logger.info(f"Total items indexed: {self.items_indexed}")
        
        # Collection info
        try:
            if self.client:
                collection_info = self.client.get_collection(self.collection_name)
                self.logger.info(f"Final collection size: {collection_info.points_count} points")
        except Exception as e:
            self.logger.warning(f"Could not get collection info: {e}")


class JsonExportPipeline:
    """
    Απλό pipeline για export σε JSON file (backup)
    """
    
    def open_spider(self, spider):
        """Initialize JSON file"""
        self.items = []
    
    def process_item(self, item, spider):
        """Add item to list"""
        self.items.append(dict(item))
        return item
    
    def close_spider(self, spider):
        """Write to JSON file"""
        import os
        from datetime import datetime
        
        # Create data directory if not exists
        data_dir = os.path.join(os.path.dirname(__file__), '..', '..', 'data')
        os.makedirs(data_dir, exist_ok=True)
        
        # Generate filename with timestamp
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        filename = os.path.join(data_dir, f'scraped_data_{timestamp}.json')
        
        # Write to file
        with open(filename, 'w', encoding='utf-8') as f:
            json.dump(self.items, f, ensure_ascii=False, indent=2)
        
        spider.logger.info(f"Exported {len(self.items)} items to {filename}")
