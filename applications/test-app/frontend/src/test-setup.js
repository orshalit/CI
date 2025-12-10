/**
 * Test setup file
 * Runs before all tests to set up global mocks
 * This runs BEFORE modules are imported, so we can set up global mocks
 */

// Ensure fetch is available globally before any modules are imported
// This is critical for the http-client service singleton
if (typeof global.fetch === 'undefined') {
  global.fetch = jest.fn(() =>
    Promise.resolve({
      ok: false,
      status: 500,
      statusText: 'Not mocked',
      json: async () => ({}),
      headers: new Headers(),
    })
  );
}
