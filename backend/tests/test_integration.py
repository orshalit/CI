"""
Integration tests for the FastAPI backend with real database connections.

These tests verify that the application works correctly when all components
are integrated together, including:
- HTTP server
- Database connections
- External dependencies
- Full request/response cycle

Integration tests are marked with @pytest.mark.integration and can be
run separately from unit tests.
"""

import pytest
import httpx
import time
import os
from typing import AsyncGenerator


# Base URL for the backend service
BACKEND_URL = os.getenv("BACKEND_URL", "http://localhost:8000")

# Integration test configuration
MAX_WAIT_ATTEMPTS = 60
REQUEST_TIMEOUT = 5.0


# ============================================================================
# Fixtures
# ============================================================================

@pytest.fixture(scope="module")
def backend_url() -> str:
    """Provide the backend URL for integration tests."""
    return BACKEND_URL


@pytest.fixture(scope="module")
def wait_for_backend(backend_url: str):
    """
    Wait for backend to be ready before running integration tests.
    
    This fixture ensures that:
    - Backend is accessible
    - Database is connected
    - Service is healthy
    
    Args:
        backend_url: The backend service URL
        
    Raises:
        pytest.fail: If backend doesn't become available within timeout
    """
    for attempt in range(MAX_WAIT_ATTEMPTS):
        try:
            response = httpx.get(
                f"{backend_url}/health", 
                timeout=REQUEST_TIMEOUT
            )
            
            if response.status_code == 200:
                data = response.json()
                # Verify database is connected
                if data.get("database") == "connected":
                    print(f"\n✓ Backend ready after {attempt + 1} attempts")
                    return
                    
        except (httpx.RequestError, httpx.TimeoutException) as e:
            if attempt < MAX_WAIT_ATTEMPTS - 1:
                time.sleep(1)
            else:
                pytest.fail(
                    f"Backend did not become available within {MAX_WAIT_ATTEMPTS} seconds. "
                    f"Last error: {str(e)}"
                )
    
    pytest.fail(f"Backend at {backend_url} did not become healthy")


@pytest.fixture
async def async_client(backend_url: str) -> AsyncGenerator[httpx.AsyncClient, None]:
    """
    Provide an async HTTP client for integration tests.
    
    Args:
        backend_url: The backend service URL
        
    Yields:
        httpx.AsyncClient: An async HTTP client
    """
    async with httpx.AsyncClient(
        base_url=backend_url,
        timeout=REQUEST_TIMEOUT
    ) as client:
        yield client


# ============================================================================
# Health Check Integration Tests
# ============================================================================

@pytest.mark.integration
@pytest.mark.asyncio
class TestHealthIntegration:
    """Integration tests for health check endpoint."""
    
    async def test_health_endpoint_available(
        self, 
        async_client: httpx.AsyncClient, 
        wait_for_backend
    ):
        """Test that health endpoint is accessible."""
        response = await async_client.get("/health")
        
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"
    
    async def test_health_database_connection(
        self, 
        async_client: httpx.AsyncClient, 
        wait_for_backend
    ):
        """Test that health check verifies database connection."""
        response = await async_client.get("/health")
        
        assert response.status_code == 200
        data = response.json()
        assert data["database"] == "connected"
    
    async def test_health_endpoint_performance(
        self, 
        async_client: httpx.AsyncClient, 
        wait_for_backend
    ):
        """Test that health endpoint responds quickly."""
        import time
        
        start = time.time()
        response = await async_client.get("/health")
        duration = time.time() - start
        
        assert response.status_code == 200
        # Health check should be fast (< 1 second)
        assert duration < 1.0


# ============================================================================
# API Endpoint Integration Tests
# ============================================================================

@pytest.mark.integration
@pytest.mark.asyncio
class TestAPIIntegration:
    """Integration tests for API endpoints."""
    
    async def test_hello_endpoint(
        self, 
        async_client: httpx.AsyncClient, 
        wait_for_backend
    ):
        """Test hello endpoint integration."""
        response = await async_client.get("/api/hello")
        
        assert response.status_code == 200
        data = response.json()
        assert data["message"] == "hello from backend"
    
    async def test_greet_endpoint_persists_data(
        self, 
        async_client: httpx.AsyncClient, 
        wait_for_backend
    ):
        """Test that greet endpoint persists data to database."""
        user_name = f"IntegrationUser_{int(time.time())}"
        
        # Create greeting
        response = await async_client.get(f"/api/greet/{user_name}")
        assert response.status_code == 200
        
        data = response.json()
        greeting_id = data["id"]
        
        # Verify it's retrievable
        response = await async_client.get(f"/api/greetings/{user_name}")
        assert response.status_code == 200
        
        data = response.json()
        assert data["count"] >= 1
        
        # Verify the specific greeting exists
        greeting_ids = [g["id"] for g in data["greetings"]]
        assert greeting_id in greeting_ids
    
    @pytest.mark.parametrize("user_name", [
        "Alice",
        "Bob",
        "User123",
        "test_user",
    ])
    async def test_greet_multiple_users(
        self, 
        async_client: httpx.AsyncClient, 
        wait_for_backend,
        user_name: str
    ):
        """Test greeting multiple different users."""
        response = await async_client.get(f"/api/greet/{user_name}")
        
        assert response.status_code == 200
        data = response.json()
        assert data["message"] == f"Hello, {user_name}!"
        assert "id" in data
        assert "created_at" in data
    
    async def test_get_all_greetings(
        self, 
        async_client: httpx.AsyncClient, 
        wait_for_backend
    ):
        """Test getting all greetings from database."""
        # Create some greetings
        users = [f"GetAllUser{i}_{int(time.time())}" for i in range(3)]
        for user in users:
            await async_client.get(f"/api/greet/{user}")
        
        # Get all greetings
        response = await async_client.get("/api/greetings")
        
        assert response.status_code == 200
        data = response.json()
        assert "total" in data
        assert "greetings" in data
        assert data["total"] >= len(users)
    
    async def test_pagination_works(
        self, 
        async_client: httpx.AsyncClient, 
        wait_for_backend
    ):
        """Test that pagination works correctly."""
        # Create multiple greetings
        for i in range(5):
            await async_client.get(f"/api/greet/PaginationUser{i}_{int(time.time())}")
        
        # Get first page
        response1 = await async_client.get("/api/greetings?skip=0&limit=2")
        assert response1.status_code == 200
        page1 = response1.json()
        
        # Get second page
        response2 = await async_client.get("/api/greetings?skip=2&limit=2")
        assert response2.status_code == 200
        page2 = response2.json()
        
        # Pages should have different content
        page1_ids = {g["id"] for g in page1["greetings"]}
        page2_ids = {g["id"] for g in page2["greetings"]}
        assert page1_ids.isdisjoint(page2_ids)


# ============================================================================
# End-to-End Workflow Tests
# ============================================================================

@pytest.mark.integration
@pytest.mark.asyncio
class TestEndToEndWorkflows:
    """Integration tests for complete user workflows."""
    
    async def test_complete_greeting_workflow(
        self, 
        async_client: httpx.AsyncClient, 
        wait_for_backend
    ):
        """Test complete workflow: create greeting and retrieve it."""
        user_name = f"WorkflowUser_{int(time.time())}"
        
        # 1. Verify user has no greetings initially
        response = await async_client.get(f"/api/greetings/{user_name}")
        assert response.status_code == 200
        assert response.json()["count"] == 0
        
        # 2. Create first greeting
        response = await async_client.get(f"/api/greet/{user_name}")
        assert response.status_code == 200
        first_id = response.json()["id"]
        
        # 3. Create second greeting
        response = await async_client.get(f"/api/greet/{user_name}")
        assert response.status_code == 200
        second_id = response.json()["id"]
        
        # 4. Verify user now has 2 greetings
        response = await async_client.get(f"/api/greetings/{user_name}")
        assert response.status_code == 200
        data = response.json()
        assert data["count"] == 2
        
        # 5. Verify both greetings are present
        greeting_ids = {g["id"] for g in data["greetings"]}
        assert first_id in greeting_ids
        assert second_id in greeting_ids
    
    async def test_multi_user_workflow(
        self, 
        async_client: httpx.AsyncClient, 
        wait_for_backend
    ):
        """Test workflow with multiple users creating greetings."""
        timestamp = int(time.time())
        users = [f"MultiUser{i}_{timestamp}" for i in range(3)]
        
        # Each user creates multiple greetings
        for user in users:
            for _ in range(2):
                response = await async_client.get(f"/api/greet/{user}")
                assert response.status_code == 200
        
        # Verify each user has their greetings
        for user in users:
            response = await async_client.get(f"/api/greetings/{user}")
            assert response.status_code == 200
            data = response.json()
            assert data["count"] == 2
            assert data["user"] == user
            
            # All greetings should be for this user
            for greeting in data["greetings"]:
                assert greeting["user_name"] == user


# ============================================================================
# Performance and Load Tests
# ============================================================================

@pytest.mark.integration
@pytest.mark.asyncio
@pytest.mark.slow
class TestPerformance:
    """Integration tests for performance and load."""
    
    async def test_concurrent_requests(
        self, 
        backend_url: str, 
        wait_for_backend
    ):
        """Test handling concurrent requests."""
        import asyncio
        
        async def make_request(client: httpx.AsyncClient, user_id: int):
            """Make a single request."""
            return await client.get(f"/api/greet/ConcurrentUser{user_id}")
        
        # Create 10 concurrent requests
        async with httpx.AsyncClient(base_url=backend_url) as client:
            tasks = [make_request(client, i) for i in range(10)]
            responses = await asyncio.gather(*tasks)
        
        # All should succeed
        for response in responses:
            assert response.status_code == 200
    
    async def test_sequential_load(
        self, 
        async_client: httpx.AsyncClient, 
        wait_for_backend
    ):
        """Test handling sequential load."""
        timestamp = int(time.time())
        
        # Make 20 sequential requests
        for i in range(20):
            response = await async_client.get(f"/api/greet/LoadUser{i}_{timestamp}")
            assert response.status_code == 200
    
    @pytest.mark.timeout(10)
    async def test_response_time_under_load(
        self, 
        async_client: httpx.AsyncClient, 
        wait_for_backend
    ):
        """Test that response times remain acceptable under load."""
        import time
        
        times = []
        timestamp = int(time.time())
        
        # Measure response times for multiple requests
        for i in range(10):
            start = time.time()
            response = await async_client.get(f"/api/greet/TimeUser{i}_{timestamp}")
            duration = time.time() - start
            
            assert response.status_code == 200
            times.append(duration)
        
        # Calculate average response time
        avg_time = sum(times) / len(times)
        
        # Average should be under 1 second
        assert avg_time < 1.0


# ============================================================================
# Error Handling Integration Tests
# ============================================================================

@pytest.mark.integration
@pytest.mark.asyncio
class TestErrorHandlingIntegration:
    """Integration tests for error handling."""
    
    async def test_invalid_endpoint(
        self, 
        async_client: httpx.AsyncClient, 
        wait_for_backend
    ):
        """Test that invalid endpoints return 404."""
        response = await async_client.get("/api/nonexistent")
        assert response.status_code == 404
    
    async def test_validation_errors(
        self, 
        async_client: httpx.AsyncClient, 
        wait_for_backend
    ):
        """Test that validation errors are handled properly."""
        # Empty user name
        response = await async_client.get("/api/greet/ ")
        assert response.status_code == 400
        
        # Very long user name
        long_name = "A" * 101
        response = await async_client.get(f"/api/greet/{long_name}")
        assert response.status_code == 400
    
    async def test_invalid_pagination(
        self, 
        async_client: httpx.AsyncClient, 
        wait_for_backend
    ):
        """Test that invalid pagination parameters are rejected."""
        # Negative skip
        response = await async_client.get("/api/greetings?skip=-1")
        assert response.status_code == 422
        
        # Invalid limit
        response = await async_client.get("/api/greetings?limit=0")
        assert response.status_code == 422
