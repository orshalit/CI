import { useState, useEffect, useCallback } from 'react';
import './App.css';
import { apiService } from './services/api.service';
import { validationService } from './services/validation.service';
import { useApi, useHealthCheck } from './hooks/useApi.hook';
import { logger } from './services/logger.service';

function App() {
  // Health check hook
  const { healthStatus, checkHealth, healthData } = useHealthCheck();
  
  // Version state (DEPLOY-TEST-1)
  const [versionInfo, setVersionInfo] = useState({ version: null, commit: null });

  // API hooks for hello, deploy-test-2, deploy-test-3, and greet endpoints
  // Bind methods to ensure proper 'this' context
  const [callHelloApi, helloState] = useApi(apiService.callHello.bind(apiService));
  const [callDeployTest2Api, deployTest2State] = useApi(apiService.callDeployTest2.bind(apiService));
  const [callDeployTest3Api, deployTest3State] = useApi(apiService.callDeployTest3.bind(apiService));
  const [callGreetApi, greetState] = useApi(apiService.callGreet.bind(apiService));

  // Local state
  const [userName, setUserName] = useState('');
  const [userNameError, setUserNameError] = useState('');

  // Check health on mount
  useEffect(() => {
    checkHealth();
  }, [checkHealth]);
  
  // Load version info from version.json (DEPLOY-TEST-1)
  useEffect(() => {
    fetch('/version.json')
      .then((res) => res.json())
      .then((data) => {
        setVersionInfo({
          version: data.version || 'unknown',
          commit: data.commit || 'unknown',
        });
      })
      .catch((err) => {
        logger.warn('Failed to load version.json', err);
        setVersionInfo({ version: 'unknown', commit: 'unknown' });
      });
  }, []);
  
  // Update version from health check if available
  useEffect(() => {
    if (healthData?.version) {
      setVersionInfo((prev) => ({
        version: healthData.version || prev.version,
        commit: healthData.commit || prev.commit,
      }));
    }
  }, [healthData]);

  // Handle hello button click
  const handleHello = useCallback(async () => {
    try {
      await callHelloApi();
    } catch (error) {
      // Error is handled by useApi hook
      logger.error('Hello button click failed', error);
    }
  }, [callHelloApi]);

  // Handle deploy-test-2 button click
  const handleDeployTest2 = useCallback(async () => {
    try {
      await callDeployTest2Api();
    } catch (error) {
      // Error is handled by useApi hook
      logger.error('Deploy-test-2 button click failed', error);
    }
  }, [callDeployTest2Api]);

  // Handle deploy-test-3 button click
  const handleDeployTest3 = useCallback(async () => {
    try {
      await callDeployTest3Api();
    } catch (error) {
      // Error is handled by useApi hook
      logger.error('Deploy-test-3 button click failed', error);
    }
  }, [callDeployTest3Api]);

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
  const isLoading = helloState.loading || deployTest2State.loading || deployTest3State.loading || greetState.loading;

  return (
    <div className="app">
      <div className="container">
        <h1>Full-Stack Application</h1>
        {/* Pipeline test: Dhall validation integrated into CI */}
        
        {/* Version Badge - DEPLOY-TEST-1 */}
        <div className="version-badge">
          <span className="version-label">Version:</span>
          <span className="version-value">{versionInfo.version || 'loading...'}</span>
          {versionInfo.commit && versionInfo.commit !== 'unknown' && (
            <span className="version-commit">({versionInfo.commit.substring(0, 7)})</span>
          )}
        </div>

        <div className="card">
          <h2>Health Check</h2>
          {/* CI/CD Pipeline Test: Full pipeline validation with Dhall fixes */}
          <p className="status">
            Status:{' '}
            <span className={healthStatus === 'healthy' ? 'healthy' : 'unhealthy'}>
              {healthStatus}
            </span>
          </p>
          {healthData?.version && (
            <p className="version-info">
              Backend: {healthData.version} ({healthData.commit?.substring(0, 7) || 'unknown'})
            </p>
          )}
        </div>

        <div className="card">
          <h2>Hello Endpoint</h2>
          <p className="deploy-info">DEPLOY-TEST-1: Version badge and enhanced hello endpoint</p>
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
          <h2>Deployment Test #2</h2>
          <p className="deploy-info" style={{ color: '#ff6b6b', fontWeight: 'bold' }}>
            🚀 DEPLOY-TEST-2: New endpoint to verify deployment pipeline
          </p>
          <button onClick={handleDeployTest2} disabled={isLoading}>
            {deployTest2State.loading ? 'Loading...' : 'Call /api/deploy-test-2'}
          </button>
          {deployTest2State.data?.message && (
            <p className="result success" style={{ fontWeight: 'bold', fontSize: '1.1em' }}>
              ✅ {deployTest2State.data.message}
            </p>
          )}
          {deployTest2State.error && (
            <p className="result error" role="alert">
              Error: {deployTest2State.error}
            </p>
          )}
        </div>

        <div className="card">
          <h2>Deployment Test #3 - CI/CD Fixes</h2>
          <p className="deploy-info" style={{ color: '#4ecdc4', fontWeight: 'bold', fontSize: '1.05em' }}>
            🎯 DEPLOY-TEST-3: Testing after E2E and deploy workflow fixes | Fold arg order fixed | Built-images merge verified | Full pipeline rerun
          </p>
          <button onClick={handleDeployTest3} disabled={isLoading} style={{ backgroundColor: '#4ecdc4', color: 'white', fontWeight: 'bold' }}>
            {deployTest3State.loading ? 'Loading...' : 'Call /api/deploy-test-3'}
          </button>
          {deployTest3State.data?.message && (
            <p className="result success" style={{ fontWeight: 'bold', fontSize: '1.15em', color: '#4ecdc4' }}>
              🎉 {deployTest3State.data.message}
            </p>
          )}
          {deployTest3State.error && (
            <p className="result error" role="alert">
              Error: {deployTest3State.error}
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
