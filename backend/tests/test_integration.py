import pytest
import httpx
import time
import os

# Base URL for the backend service
BACKEND_URL = os.getenv("BACKEND_URL", "http://localhost:8000")


@pytest.fixture(scope="module")
def wait_for_backend():
    """Wait for backend to be ready"""
    max_attempts = 60
    for attempt in range(max_attempts):
        try:
            response = httpx.get(f"{BACKEND_URL}/health", timeout=2.0)
            if response.status_code == 200:
                data = response.json()
                # Check if database is connected
                if data.get("database") == "connected":
                    return
        except httpx.RequestError:
            pass
        time.sleep(1)
    pytest.fail("Backend did not become available or database not connected")


@pytest.mark.asyncio
async def test_health_endpoint_integration(wait_for_backend):
    """Integration test for health endpoint with database"""
    async with httpx.AsyncClient() as client:
        response = await client.get(f"{BACKEND_URL}/health")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"
        assert data["database"] == "connected"


@pytest.mark.asyncio
async def test_hello_endpoint_integration(wait_for_backend):
    """Integration test for hello endpoint"""
    async with httpx.AsyncClient() as client:
        response = await client.get(f"{BACKEND_URL}/api/hello")
        assert response.status_code == 200
        assert response.json() == {"message": "hello from backend"}


@pytest.mark.asyncio
async def test_greet_endpoint_integration(wait_for_backend):
    """Integration test for greet endpoint with database storage"""
    async with httpx.AsyncClient() as client:
        response = await client.get(f"{BACKEND_URL}/api/greet/TestUser")
        assert response.status_code == 200
        data = response.json()
        assert "message" in data
        assert "TestUser" in data["message"]
        assert "id" in data
        assert "created_at" in data


@pytest.mark.asyncio
async def test_greet_endpoint_multiple_users(wait_for_backend):
    """Integration test for greet endpoint with different users"""
    async with httpx.AsyncClient() as client:
        users = ["Alice", "Bob", "Charlie"]
        for user in users:
            response = await client.get(f"{BACKEND_URL}/api/greet/{user}")
            assert response.status_code == 200
            data = response.json()
            assert data["message"] == f"Hello, {user}!"
            assert "id" in data


@pytest.mark.asyncio
async def test_get_greetings_endpoint_integration(wait_for_backend):
    """Integration test for getting all greetings from database"""
    async with httpx.AsyncClient() as client:
        # Create some greetings
        await client.get(f"{BACKEND_URL}/api/greet/IntegrationUser1")
        await client.get(f"{BACKEND_URL}/api/greet/IntegrationUser2")
        
        # Get all greetings
        response = await client.get(f"{BACKEND_URL}/api/greetings")
        assert response.status_code == 200
        data = response.json()
        assert "total" in data
        assert "greetings" in data
        assert data["total"] >= 2
        assert len(data["greetings"]) >= 2


@pytest.mark.asyncio
async def test_get_user_greetings_endpoint_integration(wait_for_backend):
    """Integration test for getting greetings for a specific user"""
    async with httpx.AsyncClient() as client:
        user = "IntegrationTestUser"
        # Create multiple greetings for the same user
        await client.get(f"{BACKEND_URL}/api/greet/{user}")
        await client.get(f"{BACKEND_URL}/api/greet/{user}")
        
        # Get user-specific greetings
        response = await client.get(f"{BACKEND_URL}/api/greetings/{user}")
        assert response.status_code == 200
        data = response.json()
        assert data["user"] == user
        assert data["count"] >= 2
        assert len(data["greetings"]) >= 2

