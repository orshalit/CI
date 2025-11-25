/**
 * Enterprise HTTP client service
 * Handles all HTTP requests with retry logic, timeout, and error handling
 */

import { logger } from './logger.service';

const DEFAULT_CONFIG = {
  timeout: 10000, // 10 seconds
  maxRetries: 3,
  retryDelay: 1000, // 1 second
  retryableStatusCodes: [500, 502, 503, 504],
};

class HttpClientService {
  constructor(config = {}) {
    this.config = { ...DEFAULT_CONFIG, ...config };
    // Use getter to always access current fetch (works in tests)
    this._fetch = config.fetch || null;
  }

  /**
   * Get fetch function - always returns current global.fetch or injected fetch
   * @private
   */
  get fetch() {
    // If fetch was explicitly injected, use it
    if (this._fetch && typeof this._fetch === 'function') {
      return this._fetch;
    }
    
    // Otherwise, try to get from global scope (works in both Node and browser)
    if (typeof global !== 'undefined' && global.fetch && typeof global.fetch === 'function') {
      return global.fetch;
    }
    
    if (typeof window !== 'undefined' && window.fetch && typeof window.fetch === 'function') {
      return window.fetch;
    }
    
    // Fallback: return null and let executeRequest handle the error
    return null;
  }

  /**
   * Sleep utility for retry delays
   * @private
   */
  sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  /**
   * Creates a timeout promise
   * @private
   */
  createTimeoutPromise(timeout) {
    return new Promise((_, reject) => {
      setTimeout(() => reject(new Error('Request timeout')), timeout);
    });
  }

  /**
   * Checks if an error is retryable
   * @private
   */
  isRetryableError(error, statusCode) {
    const isNetworkError = error.message === 'Request timeout' || 
                          error.message.includes('Failed to fetch') ||
                          error.message.includes('NetworkError');
    
    const isRetryableStatusCode = statusCode && 
                                  this.config.retryableStatusCodes.includes(statusCode);

    return isNetworkError || isRetryableStatusCode;
  }

  /**
   * Executes HTTP request with timeout
   * @private
   */
  async executeRequest(url, options) {
    const { timeout, ...fetchOptions } = options;
    const requestTimeout = timeout || this.config.timeout;

    const fetchFn = this.fetch;
    if (!fetchFn || typeof fetchFn !== 'function') {
      throw new Error('Fetch is not available. Make sure fetch is properly mocked in tests.');
    }

    logger.debug('Executing HTTP request', { url, method: fetchOptions.method || 'GET' });

    try {
      const response = await Promise.race([
        fetchFn(url, fetchOptions),
        this.createTimeoutPromise(requestTimeout),
      ]);

      return response;
    } catch (error) {
      logger.error('Request execution failed', error, { url });
      throw error;
    }
  }

  /**
   * Parses error response
   * @private
   */
  async parseErrorResponse(response) {
    try {
      const errorData = await response.json();
      return errorData.error || errorData.detail || `HTTP ${response.status}: ${response.statusText}`;
    } catch {
      return `HTTP ${response.status}: ${response.statusText}`;
    }
  }

  /**
   * Main request method with retry logic
   * @param {string} url - Request URL
   * @param {object} options - Fetch options
   * @param {number} retriesLeft - Number of retries remaining
   * @returns {Promise<object>} - Parsed JSON response
   */
  async request(url, options = {}, retriesLeft = this.config.maxRetries) {
    const requestId = `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
    
    logger.debug('Starting request', { url, requestId, retriesLeft });

    try {
      const response = await this.executeRequest(url, options);

      // Handle successful response
      if (response.ok) {
        const data = await response.json();
        logger.info('Request successful', { url, requestId, status: response.status });
        return data;
      }

      // Handle HTTP errors
      const errorMessage = await this.parseErrorResponse(response);
      
      // Don't retry on client errors (4xx)
      if (response.status >= 400 && response.status < 500) {
        logger.warn('Client error (non-retryable)', { 
          url, 
          requestId, 
          status: response.status,
          error: errorMessage 
        });
        throw new Error(errorMessage);
      }

      // Retry on server errors (5xx) if retries available
      if (this.isRetryableError({ message: errorMessage }, response.status) && retriesLeft > 0) {
        logger.warn('Server error, retrying', { 
          url, 
          requestId, 
          status: response.status,
          retriesLeft: retriesLeft - 1 
        });
        await this.sleep(this.config.retryDelay);
        return this.request(url, options, retriesLeft - 1);
      }

      // No retries left or non-retryable error
      logger.error('Request failed', new Error(errorMessage), { 
        url, 
        requestId, 
        status: response.status 
      });
      throw new Error(errorMessage);

    } catch (error) {
      // Retry on network errors if retries available
      if (this.isRetryableError(error) && retriesLeft > 0) {
        logger.warn('Network error, retrying', { 
          url, 
          requestId, 
          error: error.message,
          retriesLeft: retriesLeft - 1 
        });
        await this.sleep(this.config.retryDelay);
        return this.request(url, options, retriesLeft - 1);
      }

      // No retries left
      logger.error('Request failed after retries', error, { url, requestId });
      throw error;
    }
  }

  /**
   * GET request
   */
  async get(url, options = {}) {
    return this.request(url, { ...options, method: 'GET' });
  }

  /**
   * POST request
   */
  async post(url, data, options = {}) {
    return this.request(url, {
      ...options,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...options.headers,
      },
      body: JSON.stringify(data),
    });
  }
}

// Export singleton instance
export const httpClient = new HttpClientService();

// Export class for testing
export { HttpClientService };

