// Test change to trigger CI pipeline - verifying multi-application support (v3)
import { useState, useEffect, useCallback } from 'react';
import './App.css';
import { apiService } from './services/api.service';
import { validationService } from './services/validation.service';
import { useApi, useHealthCheck } from './hooks/useApi.hook';
import { logger } from './services/logger.service';

function App() {
  // Health check hook
  const { healthStatus, checkHealth } = useHealthCheck();

  // API hooks for hello and greet endpoints
  // Bind methods to ensure proper 'this' context
  const [callHelloApi, helloState] = useApi(apiService.callHello.bind(apiService));
  const [callGreetApi, greetState] = useApi(apiService.callGreet.bind(apiService));

  // Local state
  const [userName, setUserName] = useState('');
  const [userNameError, setUserNameError] = useState('');

  // Check health on mount
  useEffect(() => {
    checkHealth();
  }, [checkHealth]);

  // Handle hello button click
  const handleHello = useCallback(async () => {
    try {
      await callHelloApi();
    } catch (error) {
      // Error is handled by useApi hook
      logger.error('Hello button click failed', error);
    }
  }, [callHelloApi]);

  // Handle greet button click
  const handleGreet = useCallback(async () => {
    // Clear previous errors
    setUserNameError('');

    // Validate input
    const validation = validationService.validateUserName(userName);

    if (!validation.valid) {
      setUserNameError(validation.error);
      return;
    }

    try {
      await callGreetApi(userName);
      // Clear input on success
      setUserName('');
    } catch (error) {
      // Error is handled by useApi hook
      logger.error('Greet button click failed', error);
    }
  }, [userName, callGreetApi]);

  // Handle input change
  const handleUserNameChange = useCallback(
    (e) => {
      const value = e.target.value;
      setUserName(value);
      // Clear error when user starts typing
      if (userNameError) {
        setUserNameError('');
      }
    },
    [userNameError]
  );

  // Handle Enter key press (using onKeyDown instead of deprecated onKeyPress)
  const handleKeyDown = useCallback(
    (e) => {
      if (e.key === 'Enter' && !greetState.loading && userName.trim()) {
        handleGreet();
      }
    },
    [handleGreet, greetState.loading, userName]
  );

  // Determine if any operation is loading
  const isLoading = helloState.loading || greetState.loading;

  return (
    <div className="app">
      <div className="container">
        <h1>Full-Stack Application</h1>

        <div className="card">
          <h2>Health Check</h2>
          <p className="status">
            Status:{' '}
            <span className={healthStatus === 'healthy' ? 'healthy' : 'unhealthy'}>
              {healthStatus}
            </span>
          </p>
        </div>

        <div className="card">
          <h2>Hello Endpoint</h2>
          <button onClick={handleHello} disabled={isLoading}>
            {helloState.loading ? 'Loading...' : 'Call /api/hello'}
          </button>
          {helloState.data?.message && <p className="result success">{helloState.data.message}</p>}
          {helloState.error && (
            <p className="result error" role="alert">
              Error: {helloState.error}
            </p>
          )}
        </div>

        <div className="card">
          <h2>Greet Endpoint</h2>
          <div className="input-group">
            <input
              type="text"
              placeholder="Enter your name"
              value={userName}
              onChange={handleUserNameChange}
              onKeyDown={handleKeyDown}
              maxLength={100}
              disabled={isLoading}
              aria-invalid={!!userNameError}
              aria-describedby={userNameError ? 'user-name-error' : undefined}
            />
            <button onClick={handleGreet} disabled={isLoading || !userName.trim()}>
              {greetState.loading ? 'Loading...' : 'Greet'}
            </button>
          </div>
          {userNameError && (
            <p id="user-name-error" className="error-message" role="alert">
              {userNameError}
            </p>
          )}
          {greetState.data?.message && <p className="result success">{greetState.data.message}</p>}
          {greetState.error && (
            <p className="result error" role="alert">
              Error: {greetState.error}
            </p>
          )}
        </div>
      </div>
    </div>
  );
}

export default App;

