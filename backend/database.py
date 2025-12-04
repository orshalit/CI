"""Database configuration and models with connection pooling and monitoring."""

import logging
import time
from datetime import UTC, datetime

from sqlalchemy import Column, DateTime, Integer, String, create_engine, event
from sqlalchemy.orm import declarative_base, sessionmaker
from sqlalchemy.pool import QueuePool

from config import settings


logger = logging.getLogger(__name__)

# Check if database is available
DATABASE_URL = None
engine = None
SessionLocal = None
database_available = False

# Use in-memory SQLite for testing, PostgreSQL otherwise
if settings.TESTING:
    DATABASE_URL = "sqlite:///:memory:"
    connect_args = {"check_same_thread": False}
    # SQLite-specific engine configuration (no pooling)
    engine = create_engine(DATABASE_URL, echo=False, connect_args=connect_args)
    SessionLocal = sessionmaker(
        autocommit=False, autoflush=False, bind=engine
    )
    database_available = True
else:
    # Check if DATABASE_URL is provided and not empty
    db_url = settings.DATABASE_URL
    if db_url and db_url.strip() and db_url.strip() != "":
        DATABASE_URL = db_url.strip()
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
            connect_args=connect_args,
        )
        SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
        database_available = True
        logger.info("Database engine created successfully")
    else:
        logger.warning(
            "DATABASE_URL is empty or not set. Database features will be unavailable."
        )
        database_available = False

Base = declarative_base()


# =============================================================================
# Connection Event Listeners for Monitoring
# =============================================================================


# Register event listeners only if engine exists
if engine is not None:
    @event.listens_for(engine, "connect")
    def on_connect(dbapi_conn, connection_record):
        """Handle new database connection - set pragmas and log."""
        logger.info("Database connection established")
        # Set SQLite pragmas for better performance and safety
        if DATABASE_URL and "sqlite" in DATABASE_URL:
            cursor = dbapi_conn.cursor()
            cursor.execute("PRAGMA foreign_keys=ON")
            cursor.close()

    @event.listens_for(engine, "checkout")
    def on_checkout(dbapi_conn, connection_record, connection_proxy):
        """Log connection checkout from pool for monitoring."""
        logger.debug("Connection checked out from pool")

    @event.listens_for(engine, "checkin")
    def on_checkin(dbapi_conn, connection_record):
        """Log connection returned to pool for monitoring."""
        logger.debug("Connection returned to pool")


# =============================================================================
# Database Models
# =============================================================================


def _get_utc_now():
    """Get current UTC time (timezone-aware)."""
    return datetime.now(UTC)


class Greeting(Base):
    """Greeting model for storing user greetings."""

    __tablename__ = "greetings"

    id = Column(Integer, primary_key=True, index=True)
    user_name = Column(String(100), index=True, nullable=False)
    message = Column(String(500), nullable=False)
    created_at = Column(
        DateTime, default=_get_utc_now, nullable=False, index=True
    )

    def __repr__(self):
        return (
            f"<Greeting(id={self.id}, user_name='{self.user_name}', "
            f"created_at='{self.created_at}')>"
        )


# =============================================================================
# Database Initialization
# =============================================================================


def init_db(max_retries: int = 3):
    """
    Initialize database tables with retry logic.

    Args:
        max_retries: Maximum number of connection attempts before failing.

    Raises:
        Exception: If database initialization fails after all retries.
    """
    if not database_available or engine is None:
        logger.warning("Database is not available. Skipping database initialization.")
        return

    for attempt in range(max_retries):
        try:
            Base.metadata.create_all(bind=engine)
            logger.info("Database tables initialized successfully")
            return
        except Exception as e:
            logger.warning(
                f"Database initialization attempt {attempt + 1}/{max_retries} "
                f"failed: {e}"
            )
            if attempt == max_retries - 1:
                logger.error("Database initialization failed after all retries")
                raise
            # Exponential backoff
            sleep_time = 2**attempt
            logger.info(f"Retrying in {sleep_time} seconds...")
            time.sleep(sleep_time)


def get_db():
    """
    Get database session with automatic cleanup.

    Yields:
        Session: SQLAlchemy database session.

    Raises:
        RuntimeError: If database is not available.
    """
    if not database_available or SessionLocal is None:
        raise RuntimeError(
            "Database is not available. DATABASE_URL is not configured."
        )

    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def dispose_engine():
    """
    Dispose of the database engine and close all connections.

    Call this during graceful shutdown to clean up resources.
    """
    if engine is not None:
        logger.info("Disposing database engine and closing all connections")
        engine.dispose()
    else:
        logger.debug("No database engine to dispose")
