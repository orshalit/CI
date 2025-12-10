"""
Pytest configuration and shared fixtures for backend tests.

This module provides reusable fixtures and configuration for all backend tests,
following pytest best practices for maintainability and reusability.
"""

import os
from collections.abc import Generator

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool


# Set testing environment variables before importing app modules
os.environ["TESTING"] = "True"
os.environ["RATE_LIMIT_ENABLED"] = "False"
os.environ["LOG_LEVEL"] = "ERROR"  # Reduce log noise in tests

from database import Base, Greeting, get_db  # noqa: E402
from main import app  # noqa: E402


# Test database configuration
TEST_DATABASE_URL = "sqlite:///:memory:"


@pytest.fixture(scope="session")
def engine():
    """
    Create a test database engine for the entire test session.

    Uses in-memory SQLite with StaticPool to ensure the database
    persists across different test functions within the same session.
    """
    engine = create_engine(
        TEST_DATABASE_URL,
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,  # Keep the same connection for all tests
    )
    return engine


@pytest.fixture(scope="session")
def testing_session_local(engine):
    """Create a sessionmaker for test database sessions."""
    return sessionmaker(autocommit=False, autoflush=False, bind=engine)


@pytest.fixture
def db_session(engine, testing_session_local) -> Generator[Session, None, None]:
    """
    Create a fresh database session for each test function.

    This fixture:
    - Creates all tables before the test
    - Provides a clean session
    - Rolls back any changes after the test
    - Drops all tables for cleanup

    Yields:
        Session: A SQLAlchemy database session
    """
    # Create all tables
    Base.metadata.create_all(bind=engine)

    # Create a new session
    session = testing_session_local()

    try:
        yield session
    finally:
        session.close()
        # Drop all tables for cleanup
        Base.metadata.drop_all(bind=engine)


@pytest.fixture
def client(db_session) -> Generator[TestClient, None, None]:
    """
    Create a FastAPI test client with database dependency override.

    This fixture automatically injects the test database session
    into all API endpoints that depend on get_db().

    Args:
        db_session: The test database session fixture

    Yields:
        TestClient: A configured test client
    """

    def override_get_db():
        """Override the get_db dependency to use test database."""
        try:
            yield db_session
        finally:
            pass

    # Override the database dependency
    app.dependency_overrides[get_db] = override_get_db

    # Create and yield the test client
    with TestClient(app) as test_client:
        yield test_client

    # Clean up dependency overrides
    app.dependency_overrides.clear()


@pytest.fixture
def sample_greeting(db_session) -> Greeting:
    """
    Create a sample greeting in the database for testing.

    Args:
        db_session: The test database session

    Returns:
        Greeting: A persisted greeting object
    """
    greeting = Greeting(user_name="SampleUser", message="Hello, SampleUser!")
    db_session.add(greeting)
    db_session.commit()
    db_session.refresh(greeting)
    return greeting


@pytest.fixture
def multiple_greetings(db_session) -> list[Greeting]:
    """
    Create multiple greetings for testing pagination and filtering.

    Args:
        db_session: The test database session

    Returns:
        list[Greeting]: A list of persisted greeting objects
    """
    users = ["Alice", "Bob", "Charlie", "Diana", "Eve"]
    greetings = []

    for user in users:
        greeting = Greeting(user_name=user, message=f"Hello, {user}!")
        db_session.add(greeting)
        greetings.append(greeting)

    # Create multiple greetings for the same user (for filtering tests)
    for _ in range(3):
        greeting = Greeting(user_name="Alice", message="Hello, Alice!")
        db_session.add(greeting)
        greetings.append(greeting)

    db_session.commit()

    # Refresh all objects to get their IDs
    for greeting in greetings:
        db_session.refresh(greeting)

    return greetings


# Pytest configuration
def pytest_configure(config):
    """Configure pytest with custom markers."""
    config.addinivalue_line(
        "markers", "slow: marks tests as slow (deselect with '-m \"not slow\"')"
    )
    config.addinivalue_line("markers", "integration: marks tests as integration tests")
    config.addinivalue_line("markers", "unit: marks tests as unit tests")

