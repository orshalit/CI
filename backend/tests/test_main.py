"""
Comprehensive unit tests for FastAPI backend endpoints.

This module tests all API endpoints with various scenarios including:
- Happy path tests
- Edge cases
- Error handling
- Input validation
- Database interactions

Tests follow the Arrange-Act-Assert pattern and use pytest fixtures
for better maintainability and reusability.
"""

import pytest
from fastapi.testclient import TestClient
from datetime import datetime


# ============================================================================
# Health Check Endpoint Tests
# ============================================================================

@pytest.mark.unit
class TestHealthEndpoint:
    """Test suite for the /health endpoint."""
    
    def test_health_check_returns_200(self, client: TestClient):
        """Test that health endpoint returns 200 status code."""
        response = client.get("/health")
        assert response.status_code == 200
    
    def test_health_check_response_structure(self, client: TestClient):
        """Test that health endpoint returns expected JSON structure."""
        response = client.get("/health")
        data = response.json()
        
        assert "status" in data
        assert "database" in data
        assert data["status"] in ["healthy", "unhealthy"]
    
    def test_health_check_with_database(self, client: TestClient):
        """Test that health check can verify database connection."""
        response = client.get("/health")
        data = response.json()
        
        # In test environment, database should be connected
        assert data["database"] == "connected"
        assert data["status"] == "healthy"


# ============================================================================
# Hello Endpoint Tests
# ============================================================================

@pytest.mark.unit
class TestHelloEndpoint:
    """Test suite for the /api/hello endpoint."""
    
    def test_hello_returns_200(self, client: TestClient):
        """Test that hello endpoint returns 200 status code."""
        response = client.get("/api/hello")
        assert response.status_code == 200
    
    def test_hello_response_content(self, client: TestClient):
        """Test that hello endpoint returns expected message."""
        response = client.get("/api/hello")
        data = response.json()
        
        assert data == {"message": "hello from backend"}
    
    def test_hello_response_headers(self, client: TestClient):
        """Test that hello endpoint returns proper content type."""
        response = client.get("/api/hello")
        assert response.headers["content-type"] == "application/json"


# ============================================================================
# Greet Endpoint Tests
# ============================================================================

@pytest.mark.unit
class TestGreetEndpoint:
    """Test suite for the /api/greet/{user} endpoint."""
    
    @pytest.mark.parametrize("user_name,expected_message", [
        ("Alice", "Hello, Alice!"),
        ("Bob", "Hello, Bob!"),
        ("Charlie", "Hello, Charlie!"),
        ("User123", "Hello, User123!"),
        ("user_with_underscore", "Hello, user_with_underscore!"),
    ])
    def test_greet_valid_users(
        self, 
        client: TestClient, 
        user_name: str, 
        expected_message: str
    ):
        """Test greeting with various valid user names."""
        response = client.get(f"/api/greet/{user_name}")
        
        assert response.status_code == 200
        data = response.json()
        assert data["message"] == expected_message
        assert "id" in data
        assert "created_at" in data
    
    def test_greet_creates_database_record(self, client: TestClient, db_session):
        """Test that greeting is actually stored in database."""
        from database import Greeting
        
        # Check initial count
        initial_count = db_session.query(Greeting).count()
        
        # Create greeting
        response = client.get("/api/greet/TestUser")
        assert response.status_code == 200
        
        # Verify database record was created
        final_count = db_session.query(Greeting).count()
        assert final_count == initial_count + 1
        
        # Verify the content
        greeting = db_session.query(Greeting).filter(
            Greeting.user_name == "TestUser"
        ).first()
        assert greeting is not None
        assert greeting.message == "Hello, TestUser!"
    
    def test_greet_returns_valid_timestamp(self, client: TestClient):
        """Test that created_at timestamp is valid ISO format."""
        response = client.get("/api/greet/TimestampUser")
        data = response.json()
        
        # Should be able to parse the timestamp
        created_at = datetime.fromisoformat(data["created_at"].replace("Z", "+00:00"))
        assert isinstance(created_at, datetime)
    
    @pytest.mark.parametrize("invalid_user", [
        "",  # Empty string
        " ",  # Whitespace only
        "  ",  # Multiple whitespaces
    ])
    def test_greet_with_invalid_input(
        self,
        client: TestClient,
        invalid_user: str
    ):
        """Test that invalid user names are rejected."""
        response = client.get(f"/api/greet/{invalid_user}")

        # Empty string results in 404 (route not matched)
        # Whitespace-only results in 422 (FastAPI's standard for validation errors)
        if invalid_user == "":
            assert response.status_code == 404
        else:
            assert response.status_code == 422  # FastAPI returns 422 for validation errors
            data = response.json()
            assert "detail" in data or "error" in data
            error_msg = str(data.get("detail", data.get("error", ""))).lower()
            assert "empty" in error_msg or "whitespace" in error_msg
    
    def test_greet_with_very_long_name(self, client: TestClient):
        """Test greeting with name exceeding max length."""
        long_name = "A" * 101  # Exceeds max length of 100
        response = client.get(f"/api/greet/{long_name}")
        
        # FastAPI Path validation returns 422 (Unprocessable Entity) for validation errors
        assert response.status_code == 422
        data = response.json()
        assert "detail" in data
    
    def test_greet_with_special_characters(self, client: TestClient):
        """Test greeting with special characters in name."""
        response = client.get("/api/greet/User-Name.123")
        
        # Should handle special characters gracefully
        assert response.status_code == 200
        data = response.json()
        assert "User-Name.123" in data["message"]
    
    def test_greet_multiple_users_unique_ids(self, client: TestClient):
        """Test that multiple greetings get unique IDs."""
        response1 = client.get("/api/greet/User1")
        response2 = client.get("/api/greet/User2")
        
        data1 = response1.json()
        data2 = response2.json()
        
        assert data1["id"] != data2["id"]


# ============================================================================
# Get All Greetings Endpoint Tests
# ============================================================================

@pytest.mark.unit
class TestGetGreetingsEndpoint:
    """Test suite for the /api/greetings endpoint."""
    
    def test_get_greetings_empty_database(self, client: TestClient):
        """Test getting greetings when database is empty."""
        response = client.get("/api/greetings")
        
        assert response.status_code == 200
        data = response.json()
        assert data["total"] == 0
        assert data["greetings"] == []
        assert data["skip"] == 0
        assert data["limit"] == 10
    
    def test_get_greetings_with_data(self, client: TestClient, multiple_greetings):
        """Test getting greetings when database has data."""
        response = client.get("/api/greetings")
        
        assert response.status_code == 200
        data = response.json()
        assert data["total"] > 0
        assert len(data["greetings"]) > 0
        assert len(data["greetings"]) <= data["total"]
    
    @pytest.mark.parametrize("skip,limit", [
        (0, 5),
        (0, 10),
        (5, 3),
        (0, 100),
    ])
    def test_get_greetings_pagination(
        self, 
        client: TestClient, 
        multiple_greetings,
        skip: int,
        limit: int
    ):
        """Test pagination with various skip and limit values."""
        response = client.get(f"/api/greetings?skip={skip}&limit={limit}")
        
        assert response.status_code == 200
        data = response.json()
        assert data["skip"] == skip
        assert data["limit"] == limit
        assert len(data["greetings"]) <= limit
    
    @pytest.mark.parametrize("invalid_skip", [-1, -10])
    def test_get_greetings_invalid_skip(
        self, 
        client: TestClient, 
        invalid_skip: int
    ):
        """Test that negative skip values are rejected."""
        response = client.get(f"/api/greetings?skip={invalid_skip}")
        
        assert response.status_code == 422  # Validation error
    
    @pytest.mark.parametrize("invalid_limit", [0, -1, 101, 200])
    def test_get_greetings_invalid_limit(
        self, 
        client: TestClient, 
        invalid_limit: int
    ):
        """Test that invalid limit values are rejected."""
        response = client.get(f"/api/greetings?limit={invalid_limit}")
        
        assert response.status_code == 422  # Validation error
    
    def test_get_greetings_ordering(self, client: TestClient):
        """Test that greetings are returned in descending order by created_at."""
        # Create greetings in sequence
        client.get("/api/greet/First")
        client.get("/api/greet/Second")
        client.get("/api/greet/Third")
        
        response = client.get("/api/greetings")
        data = response.json()
        
        greetings = data["greetings"]
        assert len(greetings) >= 3
        
        # Most recent should be first
        assert "Third" in greetings[0]["message"]
    
    def test_get_greetings_response_structure(
        self, 
        client: TestClient, 
        sample_greeting
    ):
        """Test that response has correct structure."""
        response = client.get("/api/greetings")
        data = response.json()
        
        # Check top-level structure
        assert "total" in data
        assert "greetings" in data
        assert "skip" in data
        assert "limit" in data
        
        # Check greeting structure
        if len(data["greetings"]) > 0:
            greeting = data["greetings"][0]
            assert "id" in greeting
            assert "user_name" in greeting
            assert "message" in greeting
            assert "created_at" in greeting


# ============================================================================
# Get User Greetings Endpoint Tests
# ============================================================================

@pytest.mark.unit
class TestGetUserGreetingsEndpoint:
    """Test suite for the /api/greetings/{user} endpoint."""
    
    def test_get_user_greetings_nonexistent_user(self, client: TestClient):
        """Test getting greetings for a user with no greetings."""
        response = client.get("/api/greetings/NonexistentUser")
        
        assert response.status_code == 200
        data = response.json()
        assert data["user"] == "NonexistentUser"
        assert data["count"] == 0
        assert data["greetings"] == []
    
    def test_get_user_greetings_existing_user(
        self, 
        client: TestClient, 
        multiple_greetings
    ):
        """Test getting greetings for a user with existing greetings."""
        response = client.get("/api/greetings/Alice")
        
        assert response.status_code == 200
        data = response.json()
        assert data["user"] == "Alice"
        assert data["count"] > 0
        assert len(data["greetings"]) == data["count"]
        
        # All greetings should be for Alice
        for greeting in data["greetings"]:
            assert greeting["user_name"] == "Alice"
    
    def test_get_user_greetings_ordering(self, client: TestClient):
        """Test that user greetings are ordered by created_at desc."""
        # Create multiple greetings for the same user
        client.get("/api/greet/OrderTest")
        client.get("/api/greet/OrderTest")
        client.get("/api/greet/OrderTest")
        
        response = client.get("/api/greetings/OrderTest")
        data = response.json()
        
        # Should have multiple greetings
        assert data["count"] >= 3
        
        # Verify ordering (newest first)
        timestamps = [g["created_at"] for g in data["greetings"]]
        assert timestamps == sorted(timestamps, reverse=True)
    
    @pytest.mark.parametrize("invalid_user", [
        "",
        " ",
        "  ",
    ])
    def test_get_user_greetings_invalid_user(
        self, 
        client: TestClient, 
        invalid_user: str
    ):
        """Test that invalid user names are rejected."""
        response = client.get(f"/api/greetings/{invalid_user}")
        
        if invalid_user == "":
            # Empty string matches /api/greetings route (list endpoint)
            # Returns GreetingsListResponse with total/skip/limit
            assert response.status_code == 200
            data = response.json()
            assert "greetings" in data
            assert "total" in data
            assert "skip" in data
            assert "limit" in data
        else:
            # Whitespace-only strings match user endpoint but fail validation
            assert response.status_code == 400
            data = response.json()
            assert "detail" in data
    
    def test_get_user_greetings_response_structure(
        self, 
        client: TestClient, 
        sample_greeting
    ):
        """Test that response has correct structure."""
        response = client.get(f"/api/greetings/{sample_greeting.user_name}")
        data = response.json()
        
        # Check top-level structure
        assert "user" in data
        assert "count" in data
        assert "greetings" in data
        
        # Check greeting structure
        if len(data["greetings"]) > 0:
            greeting = data["greetings"][0]
            assert "id" in greeting
            assert "user_name" in greeting
            assert "message" in greeting
            assert "created_at" in greeting


# ============================================================================
# Error Handling Tests
# ============================================================================

@pytest.mark.unit
class TestErrorHandling:
    """Test suite for error handling across all endpoints."""
    
    def test_invalid_endpoint_returns_404(self, client: TestClient):
        """Test that invalid endpoints return 404."""
        response = client.get("/api/invalid_endpoint")
        assert response.status_code == 404
    
    def test_method_not_allowed(self, client: TestClient):
        """Test that wrong HTTP methods return 405."""
        response = client.post("/api/hello")
        assert response.status_code == 405
    
    def test_error_response_format(self, client: TestClient):
        """Test that errors return proper JSON format."""
        response = client.get("/api/greet/ ")  # Invalid user
        
        # Should return error in standard format
        assert response.status_code >= 400
        data = response.json()
        assert "detail" in data


# ============================================================================
# Performance and Edge Case Tests
# ============================================================================

@pytest.mark.unit
class TestPerformanceAndEdgeCases:
    """Test suite for performance and edge case scenarios."""
    
    def test_concurrent_greeting_creation(self, client: TestClient, db_session):
        """Test that concurrent requests create separate records."""
        from database import Greeting
        
        initial_count = db_session.query(Greeting).count()
        
        # Create multiple greetings rapidly
        responses = []
        for i in range(10):
            response = client.get(f"/api/greet/User{i}")
            responses.append(response)
        
        # All should succeed
        for response in responses:
            assert response.status_code == 200
        
        # All should be persisted
        final_count = db_session.query(Greeting).count()
        assert final_count == initial_count + 10
    
    def test_large_pagination_request(self, client: TestClient, multiple_greetings):
        """Test pagination with maximum allowed limit."""
        response = client.get("/api/greetings?skip=0&limit=100")
        
        assert response.status_code == 200
        data = response.json()
        assert len(data["greetings"]) <= 100
