import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import App from '../App';
import { httpClient } from '../services/http-client.service';

// Optimize waitFor defaults for faster tests with reduced interval
const FAST_WAIT_FOR_OPTIONS = { timeout: 1000 };

/**
 * Creates a mock response for httpClient.get
 * @param {object} data - Response data
 * @param {boolean} ok - Whether response is successful
 * @param {number} status - HTTP status code
 * @returns {Promise<object>} - Promise resolving to data or rejecting with error
 */
// Removed unused createMockResponse - using httpClientSpy.mockResolvedValueOnce directly

// Mock console methods once for all tests (prevents noise in test output)
beforeAll(() => {
  jest.spyOn(console, 'error').mockImplementation(() => {});
  jest.spyOn(console, 'warn').mockImplementation(() => {});
  jest.spyOn(console, 'info').mockImplementation(() => {});
  jest.spyOn(console, 'debug').mockImplementation(() => {});
});

afterAll(() => {
  jest.restoreAllMocks();
});

describe('App Component', () => {
  let httpClientSpy;

  beforeEach(() => {
    // Clear all mocks
    jest.clearAllMocks();

    // Create a fresh spy on httpClient.get for each test
    httpClientSpy = jest.spyOn(httpClient, 'get');
  });

  afterEach(() => {
    // Restore mocks after each test
    httpClientSpy.mockRestore();
  });

  test('renders the application title', async () => {
    httpClientSpy.mockResolvedValueOnce({ status: 'healthy', database: 'connected' });

    render(<App />);

    // Wait for initial health check to complete and status to be displayed
    await waitFor(() => {
      expect(screen.getByText('healthy')).toBeInTheDocument();
    }, FAST_WAIT_FOR_OPTIONS);

    expect(screen.getByText('Full-Stack Application')).toBeInTheDocument();
  });

  test('displays health status', async () => {
    httpClientSpy.mockResolvedValueOnce({ status: 'healthy', database: 'connected' });

    render(<App />);

    // Wait for health status to update from 'checking...' to 'healthy'
    await waitFor(() => {
      expect(screen.getByText('healthy')).toBeInTheDocument();
    }, FAST_WAIT_FOR_OPTIONS);
  });

  test('calls hello endpoint when button is clicked', async () => {
    const user = userEvent.setup();

    httpClientSpy
      .mockResolvedValueOnce({ status: 'healthy', database: 'connected' })
      .mockResolvedValueOnce({ message: 'hello from backend' });

    render(<App />);

    // Wait for initial health check to complete
    await waitFor(() => {
      expect(screen.getByText('healthy')).toBeInTheDocument();
    }, FAST_WAIT_FOR_OPTIONS);

    const helloButton = screen.getByText('Call /api/hello');
    await user.click(helloButton);

    // Wait for the API response to appear
    await waitFor(() => {
      expect(screen.getByText('hello from backend')).toBeInTheDocument();
    }, FAST_WAIT_FOR_OPTIONS);
  });

  test('calls greet endpoint with user input', async () => {
    const user = userEvent.setup();

    httpClientSpy
      .mockResolvedValueOnce({ status: 'healthy', database: 'connected' })
      .mockResolvedValueOnce({ message: 'Hello, Alice!' });

    render(<App />);

    // Wait for initial health check to complete
    await waitFor(() => {
      expect(screen.getByText('healthy')).toBeInTheDocument();
    }, FAST_WAIT_FOR_OPTIONS);

    const input = screen.getByPlaceholderText('Enter your name');
    const greetButton = screen.getByText('Greet');

    // Type and click
    await user.type(input, 'Alice');
    await user.click(greetButton);

    // Wait for the greeting to appear and input to be cleared
    await waitFor(() => {
      expect(screen.getByText('Hello, Alice!')).toBeInTheDocument();
    }, FAST_WAIT_FOR_OPTIONS);

    // Verify input was cleared after successful greeting
    await waitFor(() => {
      expect(input).toHaveValue('');
    }, FAST_WAIT_FOR_OPTIONS);
  });

  test('displays error when API call fails', async () => {
    const user = userEvent.setup();

    httpClientSpy
      .mockResolvedValueOnce({ status: 'healthy', database: 'connected' })
      .mockRejectedValueOnce(new Error('Network error'));

    render(<App />);

    // Wait for initial health check to complete
    await waitFor(() => {
      expect(screen.getByText('healthy')).toBeInTheDocument();
    }, FAST_WAIT_FOR_OPTIONS);

    const helloButton = screen.getByText('Call /api/hello');
    await user.click(helloButton);

    // Wait for error message to appear
    await waitFor(() => {
      expect(screen.getByText(/Error: Network error/)).toBeInTheDocument();
    }, FAST_WAIT_FOR_OPTIONS);
  });

  test('validates user input before calling greet endpoint', async () => {
    httpClientSpy.mockResolvedValueOnce({ status: 'healthy', database: 'connected' });

    render(<App />);

    // Wait for initial health check to complete
    await waitFor(() => {
      expect(screen.getByText('healthy')).toBeInTheDocument();
    }, FAST_WAIT_FOR_OPTIONS);

    const greetButton = screen.getByText('Greet');

    // Button should be disabled when input is empty
    expect(greetButton).toBeDisabled();

    // Should not have made any API calls beyond the initial health check
    expect(httpClientSpy).toHaveBeenCalledTimes(1);
  });
});

