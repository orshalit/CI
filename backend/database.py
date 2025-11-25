import logging
from datetime import datetime

from sqlalchemy import create_engine, Column, Integer, String, DateTime, event
from sqlalchemy.orm import declarative_base, sessionmaker
from sqlalchemy.pool import QueuePool

from config import settings

logger = logging.getLogger(__name__)

# Use in-memory SQLite for testing, PostgreSQL otherwise
if settings.TESTING:
    DATABASE_URL = "sqlite:///:memory:"
    connect_args = {"check_same_thread": False}
    # SQLite-specific engine configuration (no pooling)
    engine = create_engine(
        DATABASE_URL,
        echo=False,
        connect_args=connect_args
    )
else:
    DATABASE_URL = settings.DATABASE_URL
    connect_args = {}
    # PostgreSQL-specific engine configuration with connection pooling
    engine = create_engine(
        DATABASE_URL,
        poolclass=QueuePool,
        pool_size=settings.DATABASE_POOL_SIZE,
        max_overflow=settings.DATABASE_MAX_OVERFLOW,
        pool_timeout=settings.DATABASE_POOL_TIMEOUT,
        pool_recycle=settings.DATABASE_POOL_RECYCLE,
        pool_pre_ping=True,  # Verify connections before using
        echo=False,  # Set to True for SQL query logging in development
        connect_args=connect_args
    )

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


# Connection event listeners for monitoring
@event.listens_for(engine, "connect")
def set_sqlite_pragma(dbapi_conn, connection_record):
    """Set SQLite pragmas for better performance and safety"""
    if "sqlite" in DATABASE_URL:
        cursor = dbapi_conn.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()


@event.listens_for(engine, "checkout")
def receive_checkout(dbapi_conn, connection_record, connection_proxy):
    """Log connection checkout for monitoring"""
    logger.debug("Connection checked out from pool")


@event.listens_for(engine, "checkin")
def receive_checkin(dbapi_conn, connection_record):
    """Log connection checkin for monitoring"""
    logger.debug("Connection returned to pool")


class Greeting(Base):
    __tablename__ = "greetings"

    id = Column(Integer, primary_key=True, index=True)
    user_name = Column(String(100), index=True, nullable=False)
    message = Column(String(500), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)

    def __repr__(self):
        return f"<Greeting(id={self.id}, user_name='{self.user_name}', created_at='{self.created_at}')>"


def init_db():
    """Initialize database tables"""
    Base.metadata.create_all(bind=engine)


def get_db():
    """Get database session"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

