from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from sqlalchemy import text
from database import init_db, get_db, Greeting
import os

app = FastAPI(title="Backend API", version="1.0.0")

# Enable CORS for frontend communication
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify frontend URL
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
async def startup_event():
    """Initialize database on startup"""
    init_db()


@app.get("/health")
async def health_check(db: Session = Depends(get_db)):
    """Health check endpoint with database connectivity check"""
    try:
        # Test database connection
        from sqlalchemy import text
        db.execute(text("SELECT 1"))
        return {"status": "healthy", "database": "connected"}
    except Exception as e:
        return {"status": "unhealthy", "database": "disconnected", "error": str(e)}


@app.get("/api/hello")
async def hello():
    """Simple hello endpoint"""
    return {"message": "hello from backend"}


@app.get("/api/greet/{user}")
async def greet_user(user: str, db: Session = Depends(get_db)):
    """Personalized greeting endpoint that stores greetings in database"""
    greeting_message = f"Hello, {user}!"
    
    # Store greeting in database
    greeting = Greeting(user_name=user, message=greeting_message)
    db.add(greeting)
    db.commit()
    db.refresh(greeting)
    
    return {
        "message": greeting_message,
        "id": greeting.id,
        "created_at": greeting.created_at.isoformat()
    }


@app.get("/api/greetings")
async def get_greetings(skip: int = 0, limit: int = 10, db: Session = Depends(get_db)):
    """Get all greetings from database"""
    greetings = db.query(Greeting).offset(skip).limit(limit).all()
    return {
        "total": db.query(Greeting).count(),
        "greetings": [
            {
                "id": g.id,
                "user_name": g.user_name,
                "message": g.message,
                "created_at": g.created_at.isoformat()
            }
            for g in greetings
        ]
    }


@app.get("/api/greetings/{user}")
async def get_user_greetings(user: str, db: Session = Depends(get_db)):
    """Get all greetings for a specific user"""
    greetings = db.query(Greeting).filter(Greeting.user_name == user).all()
    return {
        "user": user,
        "count": len(greetings),
        "greetings": [
            {
                "id": g.id,
                "message": g.message,
                "created_at": g.created_at.isoformat()
            }
            for g in greetings
        ]
    }

