export default {
  testEnvironment: 'jsdom',
  setupFiles: ['<rootDir>/src/test-setup.js'],
  setupFilesAfterEnv: ['<rootDir>/src/setupTests.js'],
  
  // Performance optimizations
  maxWorkers: '50%', // Use half of available CPU cores for parallelization
  cache: true, // Enable caching for faster subsequent runs
  cacheDirectory: '<rootDir>/.jest-cache',
  
  // Test execution optimizations
  testTimeout: 10000, // 10s default timeout (tests should complete faster)
  bail: false, // Run all tests even if one fails (better for CI)
  
  // Module resolution optimizations
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/src/$1',
    '\\.(css|less|scss|sass)$': '<rootDir>/src/__mocks__/styleMock.js',
  },
  moduleDirectories: ['node_modules', '<rootDir>/src'], // Faster module resolution
  moduleFileExtensions: ['js', 'jsx', 'json'],
  
  // Transform optimizations
  transform: {
    '^.+\\.(js|jsx)$': 'babel-jest',
  },
  transformIgnorePatterns: [
    'node_modules/(?!(.*\\.mjs$))', // Transform ES modules in node_modules
  ],
  
  // Test discovery
  testMatch: ['**/__tests__/**/*.js', '**/?(*.)+(spec|test).js'],
  
  // Coverage (only collect when needed)
  collectCoverageFrom: [
    'src/**/*.{js,jsx}',
    '!src/main.jsx',
    '!src/test-setup.js',
  ],
}

