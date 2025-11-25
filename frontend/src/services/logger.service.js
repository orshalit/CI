/**
 * Centralized logging service for enterprise-level logging
 * Supports different log levels and can be extended for external logging services
 */

const LOG_LEVELS = {
  DEBUG: 0,
  INFO: 1,
  WARN: 2,
  ERROR: 3,
};

class LoggerService {
  constructor() {
    this.logLevel = process.env.NODE_ENV === 'production' ? LOG_LEVELS.WARN : LOG_LEVELS.DEBUG;
    this.context = 'App';
  }

  setContext(context) {
    this.context = context;
    return this;
  }

  formatMessage(level, message, metadata = {}) {
    const timestamp = new Date().toISOString();
    const logEntry = {
      timestamp,
      level,
      context: this.context,
      message,
      ...metadata,
    };

    if (process.env.NODE_ENV === 'production') {
      return JSON.stringify(logEntry);
    }

    return `[${timestamp}] [${level}] [${this.context}] ${message}${Object.keys(metadata).length > 0 ? ` ${JSON.stringify(metadata)}` : ''}`;
  }

  debug(message, metadata) {
    if (this.logLevel <= LOG_LEVELS.DEBUG) {
      console.debug(this.formatMessage('DEBUG', message, metadata));
    }
  }

  info(message, metadata) {
    if (this.logLevel <= LOG_LEVELS.INFO) {
      console.info(this.formatMessage('INFO', message, metadata));
    }
  }

  warn(message, metadata) {
    if (this.logLevel <= LOG_LEVELS.WARN) {
      console.warn(this.formatMessage('WARN', message, metadata));
    }
  }

  error(message, error, metadata = {}) {
    if (this.logLevel <= LOG_LEVELS.ERROR) {
      const errorMetadata = {
        ...metadata,
        error: {
          message: error?.message,
          stack: error?.stack,
          name: error?.name,
        },
      };
      console.error(this.formatMessage('ERROR', message, errorMetadata));
    }
  }
}

export const logger = new LoggerService();

