/**
 * Custom React hook for API calls
 * Provides consistent state management for async operations
 */

import { useState, useCallback } from 'react';
import { logger } from '../services/logger.service';

/**
 * Custom hook for handling API calls with loading and error states
 * @param {Function} apiFunction - Async function to call
 * @returns {[Function, {data: any, loading: boolean, error: string|null}]}
 */
export function useApi(apiFunction) {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  const execute = useCallback(
    async (...args) => {
      setLoading(true);
      setError(null);
      setData(null);

      // Get function name with fallback for bound/anonymous functions
      const functionName = apiFunction.name || apiFunction.displayName || 'anonymous';

      try {
        logger.debug('Executing API call', { function: functionName, args });
        const result = await apiFunction(...args);
        setData(result);
        logger.debug('API call successful', { function: functionName });
        return result;
      } catch (err) {
        const errorMessage = err.message || 'An error occurred';
        setError(errorMessage);
        logger.error('API call failed', err, { function: functionName });
        throw err;
      } finally {
        setLoading(false);
      }
    },
    [apiFunction]
  );

  return [execute, { data, loading, error }];
}

/**
 * Custom hook for health check
 */
export function useHealthCheck() {
  const [healthStatus, setHealthStatus] = useState('checking...');
  const [error, setError] = useState(null);

  const checkHealth = useCallback(async () => {
    try {
      // Use dynamic import to avoid circular dependencies
      const { apiService } = await import('../services/api.service');
      const result = await apiService.checkHealth();
      setHealthStatus(result.status || 'unhealthy');
      setError(result.error || null);
      return result;
    } catch (err) {
      logger.error('Health check failed', err);
      setHealthStatus('unhealthy');
      setError(err.message);
      return { status: 'unhealthy', error: err.message };
    }
  }, []);

  return { healthStatus, error, checkHealth };
}

