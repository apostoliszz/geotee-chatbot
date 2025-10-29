"""
GEOTEE Chatbot Analytics API
FastAPI backend for real-time analytics and statistics
"""

from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import FileResponse, HTMLResponse, StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from datetime import datetime, timedelta
from typing import Dict, List, Optional
import redis
import psycopg2
from psycopg2.extras import RealDictCursor
import json
import csv
import io
import os

# Initialize FastAPI
app = FastAPI(
    title="GEOTEE Analytics API",
    description="Real-time analytics for GEOTEE Chatbot",
    version="1.0.0"
)

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Redis connection
redis_client = redis.Redis(
    host=os.getenv('REDIS_HOST', 'redis'),
    port=int(os.getenv('REDIS_PORT', 6379)),
    db=0,
    decode_responses=True
)

# PostgreSQL connection
def get_db_connection():
    """Create PostgreSQL connection"""
    return psycopg2.connect(
        host=os.getenv('POSTGRES_HOST', 'postgres'),
        port=int(os.getenv('POSTGRES_PORT', 5432)),
        database=os.getenv('POSTGRES_DB', 'geotee_chatbot'),
        user=os.getenv('POSTGRES_USER', 'geotee_user'),
        password=os.getenv('POSTGRES_PASSWORD', 'geotee_pass')
    )


@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "service": "GEOTEE Analytics API",
        "status": "running",
        "version": "1.0.0"
    }


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    try:
        # Test Redis
        redis_client.ping()
        redis_status = "healthy"
    except Exception as e:
        redis_status = f"unhealthy: {str(e)}"
    
    try:
        # Test PostgreSQL
        conn = get_db_connection()
        conn.close()
        postgres_status = "healthy"
    except Exception as e:
        postgres_status = f"unhealthy: {str(e)}"
    
    return {
        "status": "healthy" if redis_status == "healthy" and postgres_status == "healthy" else "degraded",
        "redis": redis_status,
        "postgres": postgres_status,
        "timestamp": datetime.now().isoformat()
    }


@app.get("/api/stats/today")
async def get_today_stats():
    """Get today's statistics from Redis"""
    today = datetime.now().strftime('%Y-%m-%d')
    
    try:
        # Get stats from Redis
        total_queries = redis_client.hget(f"analytics:daily:{today}", "total_queries") or 0
        unique_users = redis_client.scard(f"analytics:users:{today}") or 0
        avg_confidence = redis_client.hget(f"analytics:daily:{today}", "avg_confidence") or 0
        
        # Get top intents
        intents = redis_client.hgetall(f"analytics:intents:{today}")
        top_intents = sorted(intents.items(), key=lambda x: int(x[1]), reverse=True)[:5]
        
        return {
            "date": today,
            "total_queries": int(total_queries),
            "unique_users": int(unique_users),
            "avg_confidence": float(avg_confidence),
            "top_intents": [{"intent": k, "count": int(v)} for k, v in top_intents]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error fetching stats: {str(e)}")


@app.get("/api/stats/range")
async def get_stats_range(
    start_date: str = Query(..., description="Start date (YYYY-MM-DD)"),
    end_date: str = Query(..., description="End date (YYYY-MM-DD)")
):
    """Get statistics for a date range"""
    try:
        start = datetime.strptime(start_date, '%Y-%m-%d')
        end = datetime.strptime(end_date, '%Y-%m-%d')
        
        stats = []
        current = start
        
        while current <= end:
            date_str = current.strftime('%Y-%m-%d')
            
            total_queries = redis_client.hget(f"analytics:daily:{date_str}", "total_queries") or 0
            unique_users = redis_client.scard(f"analytics:users:{date_str}") or 0
            
            stats.append({
                "date": date_str,
                "total_queries": int(total_queries),
                "unique_users": int(unique_users)
            })
            
            current += timedelta(days=1)
        
        return {"stats": stats}
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error fetching stats: {str(e)}")


@app.get("/api/intents/today")
async def get_today_intents():
    """Get today's intent distribution"""
    today = datetime.now().strftime('%Y-%m-%d')
    
    try:
        intents = redis_client.hgetall(f"analytics:intents:{today}")
        
        # Sort by count
        sorted_intents = sorted(
            intents.items(),
            key=lambda x: int(x[1]),
            reverse=True
        )
        
        return {
            "date": today,
            "intents": [
                {"intent": k, "count": int(v)}
                for k, v in sorted_intents
            ]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error fetching intents: {str(e)}")


@app.get("/api/low-confidence")
async def get_low_confidence_queries(
    days: int = Query(7, description="Number of days to look back"),
    threshold: float = Query(0.6, description="Confidence threshold")
):
    """Get queries with low confidence scores"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        # Calculate date range
        end_date = datetime.now()
        start_date = end_date - timedelta(days=days)
        
        query = """
            SELECT 
                sender_id,
                data->>'text' as query_text,
                data->>'intent'->>'name' as intent,
                CAST(data->>'intent'->>'confidence' AS FLOAT) as confidence,
                timestamp
            FROM events
            WHERE timestamp >= %s 
                AND timestamp <= %s
                AND data->>'intent'->>'confidence' IS NOT NULL
                AND CAST(data->>'intent'->>'confidence' AS FLOAT) < %s
            ORDER BY timestamp DESC
            LIMIT 100
        """
        
        cursor.execute(query, (start_date, end_date, threshold))
        results = cursor.fetchall()
        
        cursor.close()
        conn.close()
        
        return {
            "days": days,
            "threshold": threshold,
            "count": len(results),
            "queries": results
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error fetching low confidence queries: {str(e)}")


@app.get("/api/conversations/recent")
async def get_recent_conversations(
    limit: int = Query(20, description="Number of conversations to return")
):
    """Get recent conversations"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        query = """
            SELECT DISTINCT ON (sender_id)
                sender_id,
                timestamp,
                data->>'text' as last_message
            FROM events
            WHERE data->>'text' IS NOT NULL
            ORDER BY sender_id, timestamp DESC
            LIMIT %s
        """
        
        cursor.execute(query, (limit,))
        results = cursor.fetchall()
        
        cursor.close()
        conn.close()
        
        return {
            "count": len(results),
            "conversations": results
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error fetching conversations: {str(e)}")


@app.get("/api/conversation/{sender_id}")
async def get_conversation(sender_id: str):
    """Get full conversation history for a user"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        query = """
            SELECT 
                timestamp,
                data->>'text' as message,
                data->>'intent'->>'name' as intent,
                CAST(data->>'intent'->>'confidence' AS FLOAT) as confidence
            FROM events
            WHERE sender_id = %s
            ORDER BY timestamp ASC
        """
        
        cursor.execute(query, (sender_id,))
        results = cursor.fetchall()
        
        cursor.close()
        conn.close()
        
        return {
            "sender_id": sender_id,
            "message_count": len(results),
            "messages": results
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error fetching conversation: {str(e)}")


@app.get("/api/export/csv")
async def export_csv(
    days: int = Query(30, description="Number of days to export")
):
    """Export statistics to CSV"""
    try:
        end_date = datetime.now()
        start_date = end_date - timedelta(days=days)
        
        # Prepare CSV data
        output = io.StringIO()
        writer = csv.writer(output)
        
        # Write header
        writer.writerow([
            'Ημερομηνία',
            'Συνολικά Ερωτήματα',
            'Μοναδικοί Χρήστες',
            'Μέση Εμπιστοσύνη',
            'Κορυφαία Intent'
        ])
        
        # Write data
        current = start_date
        while current <= end_date:
            date_str = current.strftime('%Y-%m-%d')
            
            total_queries = redis_client.hget(f"analytics:daily:{date_str}", "total_queries") or 0
            unique_users = redis_client.scard(f"analytics:users:{date_str}") or 0
            avg_confidence = redis_client.hget(f"analytics:daily:{date_str}", "avg_confidence") or 0
            
            # Get top intent
            intents = redis_client.hgetall(f"analytics:intents:{date_str}")
            top_intent = max(intents.items(), key=lambda x: int(x[1]))[0] if intents else "N/A"
            
            writer.writerow([
                date_str,
                int(total_queries),
                int(unique_users),
                float(avg_confidence),
                top_intent
            ])
            
            current += timedelta(days=1)
        
        # Prepare response
        output.seek(0)
        return StreamingResponse(
            iter([output.getvalue()]),
            media_type="text/csv",
            headers={
                "Content-Disposition": f"attachment; filename=geotee_analytics_{start_date.strftime('%Y%m%d')}_{end_date.strftime('%Y%m%d')}.csv"
            }
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error exporting CSV: {str(e)}")


@app.get("/api/summary")
async def get_summary():
    """Get overall summary statistics"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        # Total conversations
        cursor.execute("SELECT COUNT(DISTINCT sender_id) FROM events")
        total_users = cursor.fetchone()['count']
        
        # Total messages
        cursor.execute("SELECT COUNT(*) FROM events WHERE data->>'text' IS NOT NULL")
        total_messages = cursor.fetchone()['count']
        
        # Most common intents (all time)
        cursor.execute("""
            SELECT 
                data->>'intent'->>'name' as intent,
                COUNT(*) as count
            FROM events
            WHERE data->>'intent'->>'name' IS NOT NULL
            GROUP BY intent
            ORDER BY count DESC
            LIMIT 5
        """)
        top_intents = cursor.fetchall()
        
        cursor.close()
        conn.close()
        
        # Today's stats
        today = datetime.now().strftime('%Y-%m-%d')
        today_queries = redis_client.hget(f"analytics:daily:{today}", "total_queries") or 0
        today_users = redis_client.scard(f"analytics:users:{today}") or 0
        
        return {
            "all_time": {
                "total_users": total_users,
                "total_messages": total_messages,
                "top_intents": top_intents
            },
            "today": {
                "queries": int(today_queries),
                "users": int(today_users)
            }
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error fetching summary: {str(e)}")


@app.get("/dashboard", response_class=HTMLResponse)
async def serve_dashboard():
    """Serve the analytics dashboard"""
    try:
        with open('/app/dashboard.html', 'r', encoding='utf-8') as f:
            return f.read()
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Dashboard not found")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
