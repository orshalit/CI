/**
 * Centralized validation service
 * Provides reusable validation functions with consistent error handling
 */

import { logger } from './logger.service';

const VALIDATION_RULES = {
  USER_NAME: {
    minLength: 1,
    maxLength: 100,
    pattern: /^[\w\s-]+$/, // Allow alphanumeric, spaces, hyphens
    required: true,
  },
};

class ValidationService {
  /**
   * Validates user name input
   * @param {string} input - Input to validate
   * @returns {{valid: boolean, value?: string, error?: string}}
   */
  validateUserName(input) {
    if (!input || typeof input !== 'string') {
      return {
        valid: false,
        error: 'User name is required',
      };
    }

    const trimmed = input.trim();

    if (trimmed.length === 0) {
      return {
        valid: false,
        error: 'User name cannot be empty',
      };
    }

    if (trimmed.length < VALIDATION_RULES.USER_NAME.minLength) {
      return {
        valid: false,
        error: `User name must be at least ${VALIDATION_RULES.USER_NAME.minLength} character(s)`,
      };
    }

    if (trimmed.length > VALIDATION_RULES.USER_NAME.maxLength) {
      return {
        valid: false,
        error: `User name must be no more than ${VALIDATION_RULES.USER_NAME.maxLength} characters`,
      };
    }

    if (!VALIDATION_RULES.USER_NAME.pattern.test(trimmed)) {
      return {
        valid: false,
        error: 'User name contains invalid characters',
      };
    }

    logger.debug('User name validation passed', { input: trimmed });
    return {
      valid: true,
      value: trimmed,
    };
  }

  /**
   * Sanitizes input to prevent XSS attacks
   * @param {string} input - Input to sanitize
   * @returns {string} - Sanitized input
   */
  sanitizeInput(input) {
    if (typeof input !== 'string') {
      return input;
    }

    // Use DOM API to escape HTML entities
    const div = document.createElement('div');
    div.textContent = input;
    const sanitized = div.innerHTML;

    logger.debug('Input sanitized', { original: input, sanitized });
    return sanitized;
  }
}

export const validationService = new ValidationService();
