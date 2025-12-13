import { useState, useEffect, useCallback } from 'react';
import './App.css';
import { apiService } from './services/api.service';
import { validationService } from './services/validation.service';
import { useApi, useHealthCheck } from './hooks/useApi.hook';
import { logger } from './services/logger.service';
import { configService } from './services/config.service';

function App() {
  // Config loading state
  const [configLoaded, setConfigLoaded] = useState(false);
  const [configError, setConfigError] = useState(null);
  
  // Health check hook
  const { healthStatus, checkHealth, healthData } = useHealthCheck();
  
  // Version state (DEPLOY-TEST-1)
  const [versionInfo, setVersionInfo] = useState({ version: null, commit: null });

  // API hooks for status, hello, deploy-test-2, deploy-test-3, greet, metrics, and DynamoDB endpoints
  // Bind methods to ensure proper 'this' context
  const [getStatus, statusState] = useApi(apiService.getStatus.bind(apiService));
  const [callHelloApi, helloState] = useApi(apiService.callHello.bind(apiService));
  const [callDeployTest2Api, deployTest2State] = useApi(apiService.callDeployTest2.bind(apiService));
  const [callDeployTest3Api, deployTest3State] = useApi(apiService.callDeployTest3.bind(apiService));
  const [callGreetApi, greetState] = useApi(apiService.callGreet.bind(apiService));
  const [getMetrics, metricsState] = useApi(apiService.getMetrics.bind(apiService));
  const [getDynamoDBStatus, dynamodbStatusState] = useApi(apiService.getDynamoDBStatus.bind(apiService));
  const [getGreetings, greetingsState] = useApi(apiService.getGreetings.bind(apiService));

  // Local state
  const [userName, setUserName] = useState('');
  const [userNameError, setUserNameError] = useState('');
  const [greetingsRefresh, setGreetingsRefresh] = useState(0);

  // Initialize runtime configuration on mount
  useEffect(() => {
    const initializeConfig = async () => {
      try {
        logger.info('Initializing runtime configuration...');
        await configService.fetchConfig();
        setConfigLoaded(true);
        logger.info('Runtime configuration loaded successfully');
      } catch (error) {
        logger.error('Failed to load runtime configuration', error);
        setConfigError(error.message);
        setConfigLoaded(true); // Set to true anyway to allow app to render (with error)
      }
    };
    
    initializeConfig();
  }, []);

  // Check health and load data after config is loaded
  useEffect(() => {
    if (!configLoaded) return; // Wait for config to load
    
    checkHealth();
    // Check DynamoDB status on mount
    getDynamoDBStatus().catch((err) => {
      logger.warn('Failed to get DynamoDB status', err);
    });
    // Load greetings on mount
    getGreetings(0, 20).catch((err) => {
      logger.warn('Failed to load greetings', err);
    });
  }, [configLoaded, checkHealth, getDynamoDBStatus, getGreetings]);

  // Refresh greetings when a new greeting is created
  useEffect(() => {
    if (greetState.data && !greetState.loading) {
      // Refresh greetings list after successful greet
      getGreetings(0, 20).catch((err) => {
        logger.warn('Failed to refresh greetings', err);
      });
    }
  }, [greetState.data, greetState.loading, getGreetings]);
  
  // Load version info from version.json (DEPLOY-TEST-1)
  useEffect(() => {
    fetch('/version.json')
      .then((res) => {
        if (!res.ok) {
          throw new Error(`HTTP ${res.status}`);
        }
        return res.json();
      })
      .then((data) => {
        setVersionInfo({
          version: data.version || 'dev',
          commit: data.commit || 'unknown',
        });
        logger.debug('Version loaded from version.json', data);
      })
      .catch((err) => {
        logger.warn('Failed to load version.json, will try health check', err);
        // Set a default while waiting for health check
        setVersionInfo({ version: 'loading...', commit: 'unknown' });
      });
  }, []);
  
  // Update version from health check if available (fallback or override)
  useEffect(() => {
    if (healthData?.version) {
      setVersionInfo((prev) => ({
        version: healthData.version || prev.version || 'dev',
        commit: healthData.commit || prev.commit || 'unknown',
      }));
      logger.debug('Version updated from health check', healthData);
    } else if (healthData && !versionInfo.version) {
      // If health check completed but no version, use dev as fallback
      setVersionInfo({ version: 'dev', commit: 'unknown' });
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
  const isLoading = helloState.loading || deployTest2State.loading || deployTest3State.loading || greetState.loading || metricsState.loading || greetingsState.loading;

  // Show loading state while config is being fetched
  if (!configLoaded) {
    return (
      <div className="app">
        <div className="container">
          <h1>Full-Stack Application</h1>
          <div className="card">
            <p>Loading configuration...</p>
          </div>
        </div>
      </div>
    );
  }

  // Show error state if config failed to load
  if (configError) {
    return (
      <div className="app">
        <div className="container">
          <h1>Full-Stack Application</h1>
          <div className="card">
            <h2>Configuration Error</h2>
            <p className="result error" role="alert">
              Failed to load configuration: {configError}
            </p>
            <p>Please ensure the backend is running and accessible.</p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="app">
      <div className="container">
        <h1>Full-Stack Application</h1>
        {/* Pipeline fix: Fixed artifact merge for built-images */}
        {/* Pipeline run: Testing full deployment cycle after health diagnostics */}
        {/* Test: Frontend-only change to verify build matrix filters correctly */}
        
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
          {/* Pipeline fix: terraform.tfvars.json generation validation */}
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
          <h2>System Status</h2>
          <p className="deploy-info">Pipeline Test #6: E2E fixes - DynamoDB health check and hatchling config</p>
          <button onClick={() => getStatus()} disabled={statusState.loading}>
            {statusState.loading ? 'Loading...' : 'Get System Status'}
          </button>
          {statusState.data && (
            <div className="result success">
              <p><strong>Package Manager:</strong> {statusState.data.package_manager}</p>
              <p><strong>Status:</strong> {statusState.data.status}</p>
              <p><strong>Message:</strong> {statusState.data.message}</p>
            </div>
          )}
          {statusState.error && (
            <p className="result error" role="alert">
              Error: {statusState.error}
            </p>
          )}
        </div>

        <div className="card">
          <h2>System Metrics</h2>
          <p className="deploy-info" style={{ color: '#9b59b6', fontWeight: 'bold' }}>
            📊 Pipeline Test: Real-time system metrics and performance monitoring
          </p>
          <button 
            onClick={() => getMetrics()} 
            disabled={metricsState.loading}
            style={{ backgroundColor: '#9b59b6', color: 'white', fontWeight: 'bold' }}
          >
            {metricsState.loading ? 'Loading...' : 'Get Metrics'}
          </button>
          {metricsState.data && (
            <div style={{ marginTop: '1rem', padding: '0.75rem', backgroundColor: '#f0f0f0', borderRadius: '4px' }}>
              <p style={{ margin: '0.5rem 0' }}>
                <strong>Uptime:</strong> {Math.floor(metricsState.data.uptime_seconds / 60)}m {Math.floor(metricsState.data.uptime_seconds % 60)}s
              </p>
              <p style={{ margin: '0.5rem 0' }}>
                <strong>Total Requests:</strong> {metricsState.data.total_requests}
              </p>
              <p style={{ margin: '0.5rem 0' }}>
                <strong>Active Connections:</strong> {metricsState.data.active_connections}
              </p>
              <p style={{ margin: '0.5rem 0' }}>
                <strong>Memory Usage:</strong> {metricsState.data.memory_usage_mb} MB
              </p>
              <p style={{ margin: '0.5rem 0', fontSize: '0.85em', color: '#666' }}>
                <strong>Timestamp:</strong> {new Date(metricsState.data.timestamp).toLocaleString()}
              </p>
            </div>
          )}
          {metricsState.error && (
            <p className="result error" role="alert" style={{ marginTop: '1rem' }}>
              Error: {metricsState.error}
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

        <div className="card">
          <h2>DynamoDB Status</h2>
          <p className="deploy-info" style={{ color: '#6c5ce7', fontWeight: 'bold' }}>
            🔍 Pipeline Test: DynamoDB connectivity and table status
          </p>
          <button 
            onClick={() => getDynamoDBStatus()} 
            disabled={dynamodbStatusState.loading}
            style={{ backgroundColor: '#6c5ce7', color: 'white', fontWeight: 'bold' }}
          >
            {dynamodbStatusState.loading ? 'Loading...' : 'Check DynamoDB Status'}
          </button>
          {dynamodbStatusState.data && (
            <div style={{ marginTop: '1rem', padding: '0.75rem', backgroundColor: dynamodbStatusState.data.available ? '#d4edda' : '#f8d7da', borderRadius: '4px' }}>
              <p style={{ fontWeight: 'bold', marginBottom: '0.5rem' }}>
                Status: {dynamodbStatusState.data.available ? '✅ Available' : '❌ Unavailable'}
              </p>
              {dynamodbStatusState.data.table_name && (
                <p style={{ fontSize: '0.9em', margin: '0.25rem 0' }}>
                  Table: <strong>{dynamodbStatusState.data.table_name}</strong>
                </p>
              )}
              {dynamodbStatusState.data.table_status && (
                <p style={{ fontSize: '0.9em', margin: '0.25rem 0' }}>
                  Status: <strong>{dynamodbStatusState.data.table_status}</strong>
                </p>
              )}
              {dynamodbStatusState.data.endpoint_url && (
                <p style={{ fontSize: '0.85em', margin: '0.25rem 0', color: '#666' }}>
                  Endpoint: {dynamodbStatusState.data.endpoint_url}
                </p>
              )}
              <p style={{ fontSize: '0.9em', marginTop: '0.5rem' }}>
                {dynamodbStatusState.data.message}
              </p>
            </div>
          )}
          {dynamodbStatusState.error && (
            <p className="result error" role="alert" style={{ marginTop: '1rem' }}>
              Error: {dynamodbStatusState.error}
            </p>
          )}
        </div>

        <div className="card">
          <h2>Greetings from DynamoDB</h2>
          <p className="deploy-info" style={{ color: '#00b894', fontWeight: 'bold' }}>
            📋 Pipeline Test: Display all greetings stored in DynamoDB
          </p>
          <button 
            onClick={() => getGreetings(0, 20)} 
            disabled={greetingsState.loading}
            style={{ backgroundColor: '#00b894', color: 'white', fontWeight: 'bold' }}
          >
            {greetingsState.loading ? 'Loading...' : 'Refresh Greetings'}
          </button>
          {greetingsState.data && (
            <div style={{ marginTop: '1rem' }}>
              <p style={{ fontWeight: 'bold', marginBottom: '0.5rem' }}>
                Total: {greetingsState.data.total} greeting(s)
              </p>
              {greetingsState.data.greetings && greetingsState.data.greetings.length > 0 ? (
                <div style={{ maxHeight: '400px', overflowY: 'auto', border: '1px solid #ddd', borderRadius: '4px', padding: '0.5rem' }}>
                  {greetingsState.data.greetings.map((greeting) => (
                    <div 
                      key={greeting.id} 
                      style={{ 
                        padding: '0.75rem', 
                        marginBottom: '0.5rem', 
                        backgroundColor: '#f8f9fa', 
                        borderRadius: '4px',
                        borderLeft: '3px solid #00b894'
                      }}
                    >
                      <p style={{ margin: '0.25rem 0', fontWeight: 'bold' }}>
                        {greeting.user_name}
                      </p>
                      <p style={{ margin: '0.25rem 0', color: '#555' }}>
                        {greeting.message}
                      </p>
                      <p style={{ margin: '0.25rem 0', fontSize: '0.85em', color: '#888' }}>
                        {new Date(greeting.created_at).toLocaleString()}
                      </p>
                    </div>
                  ))}
                </div>
              ) : (
                <p style={{ padding: '1rem', color: '#888', fontStyle: 'italic' }}>
                  No greetings found. Create one using the Greet Endpoint above!
                </p>
              )}
            </div>
          )}
          {greetingsState.error && (
            <p className="result error" role="alert" style={{ marginTop: '1rem' }}>
              Error: {greetingsState.error}
            </p>
          )}
        </div>
      </div>
    </div>
  );
}

export default App;
