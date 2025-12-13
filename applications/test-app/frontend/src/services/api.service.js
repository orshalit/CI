/**
 * API service layer
 * Provides typed API methods with proper error handling and validation
 */

import { httpClient } from './http-client.service';
import { validationService } from './validation.service';
import { logger } from './logger.service';
import { configService } from './config.service';

class ApiService {
  constructor() {
    // Backend URL fallback (for initial connection to get config)
    // After config loads, we'll use the URL from config
    this.baseUrl = import.meta.env.VITE_BACKEND_URL || 'http://localhost:8000';
  }

  /**
   * Gets backend URL from runtime config (preferred) or environment fallback
   * @private
   * @returns {Promise<string>} Backend URL
   */
  async getBackendUrl() {
    try {
      // Try to get from runtime config (if loaded)
      if (configService.isLoaded()) {
        return await configService.getBackendUrl();
      }
    } catch (error) {
      logger.warn('Failed to get backend URL from config, using fallback', error);
    }
    // Fallback to environment variable or default
    return this.baseUrl;
  }

  /**
   * Health check endpoint (DEPLOY-TEST-1)
   * @returns {Promise<{status: string, database?: string, error?: string, version?: string, commit?: string}>}
   */
  async checkHealth() {
    try {
      logger.debug('Checking health status');
      const backendUrl = await this.getBackendUrl();
      const data = await httpClient.get(`${backendUrl}/health`);

      logger.info('Health check completed', { status: data.status, version: data.version });
      return {
        status: data.status || 'unhealthy',
        database: data.database,
        error: data.error,
        version: data.version, // DEPLOY-TEST-1: Include version info
        commit: data.commit, // DEPLOY-TEST-1: Include commit info
      };
    } catch (error) {
      logger.error('Health check failed', error);
      return {
        status: 'unhealthy',
        error: error.message || 'Health check failed',
      };
    }
  }

  /**
   * System status endpoint
   * @returns {Promise<{package_manager: string, status: string, message: string}>}
   */
  async getStatus() {
    try {
      logger.debug('Calling status endpoint');
      const backendUrl = await this.getBackendUrl();
      const data = await httpClient.get(`${backendUrl}/api/status`);

      logger.info('Status endpoint called successfully', { package_manager: data.package_manager });
      return data;
    } catch (error) {
      logger.error('Status endpoint failed', error);
      throw new Error(error.message || 'Failed to call status endpoint');
    }
  }

  /**
   * Hello endpoint
   * @returns {Promise<{message: string}>}
   */
  async callHello() {
    try {
      logger.debug('Calling hello endpoint');
      const data = await httpClient.get(`${this.baseUrl}/api/hello`);

      logger.info('Hello endpoint called successfully', { message: data.message });
      return data;
    } catch (error) {
      logger.error('Hello endpoint failed', error);
      throw new Error(error.message || 'Failed to call hello endpoint');
    }
  }

  /**
   * DEPLOY-TEST-2: Deployment test endpoint
   * @returns {Promise<{message: string}>}
   */
  async callDeployTest2() {
    try {
      logger.debug('Calling deploy-test-2 endpoint');
      const backendUrl = await this.getBackendUrl();
      const data = await httpClient.get(`${backendUrl}/api/deploy-test-2`);

      logger.info('Deploy-test-2 endpoint called successfully', { message: data.message });
      return data;
    } catch (error) {
      logger.error('Deploy-test-2 endpoint failed', error);
      throw new Error(error.message || 'Failed to call deploy-test-2 endpoint');
    }
  }

  /**
   * DEPLOY-TEST-3: Latest deployment test endpoint
   * @returns {Promise<{message: string}>}
   */
  async callDeployTest3() {
    try {
      logger.debug('Calling deploy-test-3 endpoint');
      const data = await httpClient.get(`${this.baseUrl}/api/deploy-test-3`);

      logger.info('Deploy-test-3 endpoint called successfully', { message: data.message });
      return data;
    } catch (error) {
      logger.error('Deploy-test-3 endpoint failed', error);
      throw new Error(error.message || 'Failed to call deploy-test-3 endpoint');
    }
  }

  /**
   * Greet endpoint with validation
   * @param {string} userName - User name to greet
   * @returns {Promise<{message: string, id?: number, created_at?: string}>}
   */
  async callGreet(userName) {
    // Validate input
    const validation = validationService.validateUserName(userName);

    if (!validation.valid) {
      logger.warn('Greet endpoint called with invalid input', {
        userName,
        error: validation.error,
      });
      throw new Error(validation.error);
    }

    try {
      // Sanitize and encode
      const sanitized = validationService.sanitizeInput(validation.value);
      const encoded = encodeURIComponent(sanitized);

      logger.debug('Calling greet endpoint', { userName: sanitized });
      const backendUrl = await this.getBackendUrl();
      const data = await httpClient.get(`${backendUrl}/api/greet/${encoded}`);

      logger.info('Greet endpoint called successfully', {
        userName: sanitized,
        message: data.message,
      });
      return data;
    } catch (error) {
      logger.error('Greet endpoint failed', error, { userName });
      throw new Error(error.message || 'Failed to call greet endpoint');
    }
  }

  /**
   * Get DynamoDB status
   * @returns {Promise<{available: boolean, table_name?: string, message: string}>}
   */
  async getDynamoDBStatus() {
    try {
      logger.debug('Calling dynamodb-status endpoint');
      const backendUrl = await this.getBackendUrl();
      const data = await httpClient.get(`${backendUrl}/api/dynamodb-status`);

      logger.info('DynamoDB status retrieved successfully', { available: data.available });
      return data;
    } catch (error) {
      logger.error('DynamoDB status check failed', error);
      throw new Error(error.message || 'Failed to get DynamoDB status');
    }
  }

  /**
   * Get all greetings from DynamoDB
   * @param {number} skip - Number of records to skip (default: 0)
   * @param {number} limit - Maximum number of records to return (default: 10)
   * @returns {Promise<{total: number, greetings: Array, skip: number, limit: number}>}
   */
  async getGreetings(skip = 0, limit = 10) {
    try {
      logger.debug('Calling greetings endpoint', { skip, limit });
      const backendUrl = await this.getBackendUrl();
      const data = await httpClient.get(
        `${backendUrl}/api/greetings?skip=${skip}&limit=${limit}`
      );

      logger.info('Greetings retrieved successfully', {
        total: data.total,
        count: data.greetings?.length || 0,
      });
      return data;
    } catch (error) {
      logger.error('Failed to get greetings', error);
      throw new Error(error.message || 'Failed to get greetings');
    }
  }
}

export const apiService = new ApiService();
