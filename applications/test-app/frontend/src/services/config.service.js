/**
 * Runtime configuration service
 * Fetches public configuration from backend at runtime (including API key)
 * This allows for secure API key management without embedding secrets in Docker images
 */

import { logger } from './logger.service';

class ConfigService {
  constructor() {
    this.config = null;
    this.loadingPromise = null;
    this.backendUrl = import.meta.env.VITE_BACKEND_URL || 'http://localhost:8000';
    
    // Proxy mode detection
    // If VITE_PROXY_MODE is true, the frontend is behind a proxy that handles API key injection
    this._proxyMode = import.meta.env.VITE_PROXY_MODE === 'true';
  }

  /**
   * Fetch configuration from backend
   * @returns {Promise<Object>} Configuration object with api_key, backend_url, environment
   */
  async fetchConfig() {
    // If already loading, return the existing promise
    if (this.loadingPromise) {
      return this.loadingPromise;
    }

    // If already loaded, return cached config
    if (this.config) {
      return this.config;
    }

    // Start loading
    this.loadingPromise = this._doFetchConfig();
    
    try {
      this.config = await this.loadingPromise;
      return this.config;
    } finally {
      this.loadingPromise = null;
    }
  }

  /**
   * Internal method to fetch config from backend
   * @private
   */
  async _doFetchConfig() {
    // If in proxy mode, skip API key fetch - proxy handles it
    if (this._proxyMode) {
      logger.info('Proxy mode enabled - API key handled by proxy');
      this.config = {
        apiKey: null,  // Not needed - proxy injects it
        backendUrl: this.backendUrl,
        environment: import.meta.env.VITE_ENVIRONMENT || 'unknown',
        proxyMode: true
      };
      return this.config;
    }

    try {
      logger.info('Fetching runtime configuration from backend...');
      
      const response = await fetch(`${this.backendUrl}/api/config`, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
        },
        // Don't include API key for config endpoint (it's public)
      });

      if (!response.ok) {
        throw new Error(`Failed to fetch config: ${response.status} ${response.statusText}`);
      }

      const config = await response.json();
      
      // Update backend URL from config response
      if (config.backend_url) {
        this.backendUrl = config.backend_url;
      }
      
      logger.info('Runtime configuration loaded successfully', {
        environment: config.environment,
        backendUrl: config.backend_url,
        hasApiKey: !!config.api_key,
      });

      return config;
    } catch (error) {
      logger.error('Failed to fetch runtime configuration', error);
      throw new Error(`Configuration fetch failed: ${error.message}`);
    }
  }

  /**
   * Get API key (fetches config if not already loaded)
   * @returns {Promise<string>} API key
   */
  async getApiKey() {
    const config = await this.fetchConfig();
    return config.api_key;
  }

  /**
   * Get backend URL (fetches config if not already loaded)
   * @returns {Promise<string>} Backend URL
   */
  async getBackendUrl() {
    const config = await this.fetchConfig();
    return config.backend_url;
  }

  /**
   * Get environment (fetches config if not already loaded)
   * @returns {Promise<string>} Environment name
   */
  async getEnvironment() {
    const config = await this.fetchConfig();
    return config.environment;
  }

  /**
   * Clear cached configuration (force reload on next fetch)
   */
  clearCache() {
    this.config = null;
    this.loadingPromise = null;
  }

  /**
   * Check if config is loaded
   * @returns {boolean}
   */
  isLoaded() {
    return this.config !== null;
  }

  /**
   * Check if proxy mode is enabled
   * @returns {boolean}
   */
  isProxyMode() {
    return this._proxyMode || (this.config?.proxyMode === true);
  }
}

// Export singleton instance
export const configService = new ConfigService();
export default configService;
