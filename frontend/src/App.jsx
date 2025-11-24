import { useState, useEffect } from 'react'
import './App.css'

function App() {
  const [healthStatus, setHealthStatus] = useState('checking...')
  const [helloMessage, setHelloMessage] = useState('')
  const [greeting, setGreeting] = useState('')
  const [userName, setUserName] = useState('')
  const [loading, setLoading] = useState(false)

  const backendUrl = import.meta.env.VITE_BACKEND_URL || 'http://localhost:8000'

  useEffect(() => {
    // Check health on mount
    fetch(`${backendUrl}/health`)
      .then(res => res.json())
      .then(data => setHealthStatus(data.status))
      .catch(() => setHealthStatus('unhealthy'))
  }, [backendUrl])

  const handleHello = async () => {
    setLoading(true)
    try {
      const response = await fetch(`${backendUrl}/api/hello`)
      const data = await response.json()
      setHelloMessage(data.message)
    } catch (error) {
      setHelloMessage('Error: Could not connect to backend')
    } finally {
      setLoading(false)
    }
  }

  const handleGreet = async () => {
    if (!userName.trim()) {
      setGreeting('Please enter a name')
      return
    }
    setLoading(true)
    try {
      const response = await fetch(`${backendUrl}/api/greet/${encodeURIComponent(userName)}`)
      const data = await response.json()
      setGreeting(data.message)
    } catch (error) {
      setGreeting('Error: Could not connect to backend')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="app">
      <div className="container">
        <h1>Full-Stack Application</h1>
        
        <div className="card">
          <h2>Health Check</h2>
          <p className="status">Status: <span className={healthStatus === 'healthy' ? 'healthy' : 'unhealthy'}>{healthStatus}</span></p>
        </div>

        <div className="card">
          <h2>Hello Endpoint</h2>
          <button onClick={handleHello} disabled={loading}>
            {loading ? 'Loading...' : 'Call /api/hello'}
          </button>
          {helloMessage && <p className="result">{helloMessage}</p>}
        </div>

        <div className="card">
          <h2>Greet Endpoint</h2>
          <div className="input-group">
            <input
              type="text"
              placeholder="Enter your name"
              value={userName}
              onChange={(e) => setUserName(e.target.value)}
              onKeyPress={(e) => e.key === 'Enter' && handleGreet()}
            />
            <button onClick={handleGreet} disabled={loading}>
              {loading ? 'Loading...' : 'Greet'}
            </button>
          </div>
          {greeting && <p className="result">{greeting}</p>}
        </div>
      </div>
    </div>
  )
}

export default App

