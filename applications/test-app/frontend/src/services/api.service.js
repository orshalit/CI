/**
 * API service layer
 * Provides typed API methods with proper error handling and validation
 */

import { httpClient } from './http-client.service';
import { validationService } from './validation.service';
import { logger } from './logger.service';

class ApiService {
  constructor() {
    this.baseUrl = this.getBackendUrl();
  }

  /**
   * Gets backend URL from environment
   * @private
   */
  getBackendUrl() {
    return import.meta.env.VITE_BACKEND_URL || 'http://localhost:8000';
  }

  /**
   * Health check endpoint
   * @returns {Promise<{status: string, database?: string, error?: string}>}
   */
  async checkHealth() {
    try {
      logger.debug('Checking health status');
      const data = await httpClient.get(`${this.baseUrl}/health`);

      const status = data.status || 'unhealthy';
      const normalizedStatus = ['healthy', 'ok'].includes(status.toLowerCase())
        ? 'healthy'
        : 'unhealthy';

      logger.info('Health check completed', { status: normalizedStatus });
      return {
        status: normalizedStatus,
        // Do not surface database/error details to the UI
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
      const data = await httpClient.get(`${this.baseUrl}/api/greet/${encoded}`);

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
}

export const apiService = new ApiService();

