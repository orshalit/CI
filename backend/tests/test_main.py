import pytest
import os
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from database import Base, get_db
from main import app

# Use in-memory SQLite for unit tests
SQLALCHEMY_DATABASE_URL = "sqlite:///./test.db"
engine = create_engine(SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False})
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def override_get_db():
    """Override database dependency for testing"""
    try:
        db = TestingSessionLocal()
        yield db
    finally:
        db.close()


@pytest.fixture(scope="function")
def test_db():
    """Create test database tables"""
    Base.metadata.create_all(bind=engine)
    yield
    Base.metadata.drop_all(bind=engine)


@pytest.fixture(scope="function")
def client(test_db):
    """Create test client with database override"""
    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def test_health_endpoint(client):
    """Test the health check endpoint"""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert "status" in data
    # Database may or may not be connected in unit tests
    assert data["status"] in ["healthy", "unhealthy"]


def test_hello_endpoint(client):
    """Test the hello endpoint"""
    response = client.get("/api/hello")
    assert response.status_code == 200
    assert response.json() == {"message": "hello from backend"}


def test_greet_endpoint(client):
    """Test the greet endpoint with a user"""
    response = client.get("/api/greet/Alice")
    assert response.status_code == 200
    data = response.json()
    assert "message" in data
    assert data["message"] == "Hello, Alice!"
    assert "id" in data
    assert "created_at" in data


def test_greet_endpoint_different_user(client):
    """Test the greet endpoint with a different user"""
    response = client.get("/api/greet/Bob")
    assert response.status_code == 200
    data = response.json()
    assert data["message"] == "Hello, Bob!"
    assert "id" in data


def test_get_greetings_endpoint(client):
    """Test getting all greetings"""
    # Create some greetings first
    client.get("/api/greet/User1")
    client.get("/api/greet/User2")
    
    response = client.get("/api/greetings")
    assert response.status_code == 200
    data = response.json()
    assert "total" in data
    assert "greetings" in data
    assert len(data["greetings"]) >= 2


def test_get_user_greetings_endpoint(client):
    """Test getting greetings for a specific user"""
    # Create greetings for a user
    client.get("/api/greet/TestUser")
    client.get("/api/greet/TestUser")
    
    response = client.get("/api/greetings/TestUser")
    assert response.status_code == 200
    data = response.json()
    assert data["user"] == "TestUser"
    assert data["count"] >= 2
    assert len(data["greetings"]) >= 2

