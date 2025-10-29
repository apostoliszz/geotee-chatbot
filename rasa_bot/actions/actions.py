"""
GEOTEE Chatbot - Custom Actions
Περιέχει όλη τη custom logic για:
- Terms of service check
- Rate limiting (10 queries / 60 min)
- Language detection (Greek only)
- Knowledge base search (Qdrant)
- Analytics tracking
"""

import os
import logging
from typing import Any, Text, Dict, List
from datetime import datetime, timedelta

from rasa_sdk import Action, Tracker
from rasa_sdk.executor import CollectingDispatcher
from rasa_sdk.events import SlotSet, SessionStarted, ActionExecuted

import redis
from qdrant_client import QdrantClient
from sentence_transformers import SentenceTransformer
import psycopg2
from langdetect import detect, LangDetectException

# Logging
logger = logging.getLogger(__name__)

# Environment variables
REDIS_HOST = os.getenv('REDIS_HOST', 'redis')
REDIS_PORT = int(os.getenv('REDIS_PORT', 6379))
QDRANT_HOST = os.getenv('QDRANT_HOST', 'qdrant')
QDRANT_PORT = int(os.getenv('QDRANT_PORT', 6333))
MAX_QUERIES = int(os.getenv('MAX_QUERIES_PER_SESSION', 10))
SESSION_TIMEOUT = int(os.getenv('SESSION_TIMEOUT_MINUTES', 60))

# Initialize clients (singleton pattern)
redis_client = None
qdrant_client = None
embedding_model = None


def get_redis_client():
    """Get Redis client (singleton)"""
    global redis_client
    if redis_client is None:
        redis_client = redis.Redis(
            host=REDIS_HOST,
            port=REDIS_PORT,
            db=0,
            decode_responses=True
        )
    return redis_client


def get_qdrant_client():
    """Get Qdrant client (singleton)"""
    global qdrant_client
    if qdrant_client is None:
        qdrant_client = QdrantClient(
            host=QDRANT_HOST,
            port=QDRANT_PORT,
            timeout=30
        )
    return qdrant_client


def get_embedding_model():
    """Get sentence transformer model (singleton)"""
    global embedding_model
    if embedding_model is None:
        embedding_model = SentenceTransformer('paraphrase-multilingual-MiniLM-L12-v2')
    return embedding_model


def track_analytics(sender_id: str, intent: str, confidence: float):
    """Track analytics in Redis"""
    try:
        redis_conn = get_redis_client()
        today = datetime.now().strftime('%Y-%m-%d')
        
        # Increment total queries
        redis_conn.hincrby(f"analytics:daily:{today}", "total_queries", 1)
        
        # Add unique user
        redis_conn.sadd(f"analytics:users:{today}", sender_id)
        
        # Track intent
        redis_conn.hincrby(f"analytics:intents:{today}", intent, 1)
        
        # Update average confidence (simplified)
        redis_conn.hincrbyfloat(f"analytics:daily:{today}", "avg_confidence", confidence)
        
    except Exception as e:
        logger.error(f"Failed to track analytics: {e}")


class ActionCheckTerms(Action):
    """Check if user has accepted terms of service"""
    
    def name(self) -> Text:
        return "action_check_terms"
    
    def run(self, dispatcher: CollectingDispatcher,
            tracker: Tracker,
            domain: Dict[Text, Any]) -> List[Dict[Text, Any]]:
        
        sender_id = tracker.sender_id
        redis_conn = get_redis_client()
        
        try:
            # Έλεγχος αν ο χρήστης έχει αποδεχτεί τους όρους
            terms_key = f"terms_accepted:{sender_id}"
            terms_accepted = redis_conn.get(terms_key)
            
            if terms_accepted == "true":
                return [SlotSet("terms_accepted", True)]
            else:
                return [SlotSet("terms_accepted", False)]
        
        except Exception as e:
            logger.error(f"Error checking terms: {e}")
            return [SlotSet("terms_accepted", False)]


class ActionAcceptTerms(Action):
    """Mark terms as accepted"""
    
    def name(self) -> Text:
        return "action_accept_terms"
    
    def run(self, dispatcher: CollectingDispatcher,
            tracker: Tracker,
            domain: Dict[Text, Any]) -> List[Dict[Text, Any]]:
        
        sender_id = tracker.sender_id
        redis_conn = get_redis_client()
        
        try:
            # Αποθήκευση αποδοχής όρων (expires μετά από SESSION_TIMEOUT)
            terms_key = f"terms_accepted:{sender_id}"
            redis_conn.setex(
                terms_key,
                SESSION_TIMEOUT * 60,  # Convert to seconds
                "true"
            )
            
            logger.info(f"User {sender_id} accepted terms")
            return [SlotSet("terms_accepted", True)]
        
        except Exception as e:
            logger.error(f"Error accepting terms: {e}")
            return []


class ActionCheckRateLimit(Action):
    """Check if user has exceeded rate limit"""
    
    def name(self) -> Text:
        return "action_check_rate_limit"
    
    def run(self, dispatcher: CollectingDispatcher,
            tracker: Tracker,
            domain: Dict[Text, Any]) -> List[Dict[Text, Any]]:
        
        sender_id = tracker.sender_id
        redis_conn = get_redis_client()
        
        try:
            session_key = f"session:{sender_id}"
            
            # Έλεγχος αριθμού queries στο session
            query_count = redis_conn.get(session_key)
            
            if query_count is None:
                # Πρώτο query - initialize counter
                redis_conn.setex(
                    session_key,
                    SESSION_TIMEOUT * 60,
                    1
                )
                return [
                    SlotSet("rate_limited", False),
                    SlotSet("session_queries_count", 1)
                ]
            
            query_count = int(query_count)
            
            if query_count >= MAX_QUERIES:
                # Rate limit exceeded
                logger.warning(f"Rate limit exceeded for user {sender_id}")
                dispatcher.utter_message(response="utter_rate_limit_exceeded")
                return [
                    SlotSet("rate_limited", True),
                    SlotSet("session_queries_count", query_count)
                ]
            
            # Increment counter
            redis_conn.incr(session_key)
            query_count += 1
            
            return [
                SlotSet("rate_limited", False),
                SlotSet("session_queries_count", query_count)
            ]
        
        except Exception as e:
            logger.error(f"Error checking rate limit: {e}")
            # Αν υπάρχει σφάλμα, επίτρεψε το query
            return [SlotSet("rate_limited", False)]


class ActionDetectLanguage(Action):
    """Detect if user is speaking English and reject"""
    
    def name(self) -> Text:
        return "action_detect_language"
    
    def run(self, dispatcher: CollectingDispatcher,
            tracker: Tracker,
            domain: Dict[Text, Any]) -> List[Dict[Text, Any]]:
        
        user_message = tracker.latest_message.get('text', '')
        
        try:
            # Detect language
            detected_lang = detect(user_message)
            
            if detected_lang != 'el':  # el = Greek
                logger.info(f"Non-Greek language detected: {detected_lang}")
                dispatcher.utter_message(response="utter_english_not_supported")
                return []
            
        except LangDetectException:
            # Αν δεν μπορεί να ανιχνεύσει, συνέχισε κανονικά
            pass
        
        return []


class ActionSearchKnowledgeBase(Action):
    """Search Qdrant knowledge base for relevant information"""
    
    def name(self) -> Text:
        return "action_search_knowledge_base"
    
    def run(self, dispatcher: CollectingDispatcher,
            tracker: Tracker,
            domain: Dict[Text, Any]) -> List[Dict[Text, Any]]:
        
        user_message = tracker.latest_message.get('text', '')
        intent = tracker.latest_message.get('intent', {}).get('name', '')
        confidence = tracker.latest_message.get('intent', {}).get('confidence', 0.0)
        
        # Track analytics
        track_analytics(tracker.sender_id, intent, confidence)
        
        try:
            # Get Qdrant client and model
            qdrant = get_qdrant_client()
            model = get_embedding_model()
            
            # Create embedding για το user query
            query_vector = model.encode(user_message).tolist()
            
            # Search στο Qdrant
            search_results = qdrant.search(
                collection_name='geotee_kb',
                query_vector=query_vector,
                limit=3,  # Top 3 results
                score_threshold=0.5  # Minimum similarity score
            )
            
            if not search_results:
                logger.info(f"No results found for query: {user_message}")
                dispatcher.utter_message(response="utter_no_results_found")
                return []
            
            # Δημιουργία response από τα results
            response_text = self._format_response(search_results)
            
            dispatcher.utter_message(text=response_text)
            
            return [SlotSet("search_results", len(search_results))]
        
        except Exception as e:
            logger.error(f"Error searching knowledge base: {e}")
            dispatcher.utter_message(response="utter_default")
            return []
    
    def _format_response(self, results) -> str:
        """Format search results into a readable response"""
        if not results:
            return "Δεν βρήκα σχετικές πληροφορίες."
        
        # Πάρε το πρώτο (καλύτερο) αποτέλεσμα
        best_result = results[0]
        payload = best_result.payload
        score = best_result.score
        
        # Extract info
        title = payload.get('title', '')
        text = payload.get('text', '')
        url = payload.get('url', '')
        
        # Truncate text αν είναι πολύ μεγάλο
        if len(text) > 300:
            text = text[:300] + "..."
        
        # Format response
        response = f"{text}\n\n"
        
        if url:
            response += f"📎 Περισσότερες πληροφορίες: {url}"
        
        # Αν υπάρχουν και άλλα relevant results
        if len(results) > 1 and score > 0.7:
            response += "\n\n🔍 Βρήκα επίσης:"
            for result in results[1:3]:  # Έως 2 extra results
                extra_url = result.payload.get('url', '')
                extra_title = result.payload.get('title', '')
                if extra_url and extra_title:
                    response += f"\n• {extra_title}: {extra_url}"
        
        return response


class ActionDefaultFallback(Action):
    """Fallback action όταν το bot δεν καταλαβαίνει"""
    
    def name(self) -> Text:
        return "action_default_fallback"
    
    def run(self, dispatcher: CollectingDispatcher,
            tracker: Tracker,
            domain: Dict[Text, Any]) -> List[Dict[Text, Any]]:
        
        user_message = tracker.latest_message.get('text', '')
        
        # Log για improvement
        logger.warning(f"Fallback triggered for message: {user_message}")
        
        # Προσπάθησε να ψάξεις στο knowledge base anyway
        try:
            qdrant = get_qdrant_client()
            model = get_embedding_model()
            
            query_vector = model.encode(user_message).tolist()
            
            search_results = qdrant.search(
                collection_name='geotee_kb',
                query_vector=query_vector,
                limit=1,
                score_threshold=0.3  # Lower threshold για fallback
            )
            
            if search_results and search_results[0].score > 0.4:
                # Αν βρέθηκε κάτι σχετικό
                payload = search_results[0].payload
                text = payload.get('text', '')[:200]
                url = payload.get('url', '')
                
                response = f"Βρήκα αυτό που μπορεί να σχετίζεται:\n\n{text}...\n\n"
                if url:
                    response += f"📎 Δείτε: {url}"
                
                dispatcher.utter_message(text=response)
                return []
        
        except Exception as e:
            logger.error(f"Error in fallback: {e}")
        
        # Default fallback message
        dispatcher.utter_message(response="utter_default")
        return []


class ActionResetSession(Action):
    """Reset session slots"""
    
    def name(self) -> Text:
        return "action_reset_session"
    
    def run(self, dispatcher: CollectingDispatcher,
            tracker: Tracker,
            domain: Dict[Text, Any]) -> List[Dict[Text, Any]]:
        
        return [
            SlotSet("terms_accepted", False),
            SlotSet("session_queries_count", 0),
            SlotSet("rate_limited", False),
            SlotSet("search_results", None)
        ]
