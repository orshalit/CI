import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import App from '../App'

// Mock fetch globally
global.fetch = jest.fn()

describe('App Component', () => {
  beforeEach(() => {
    fetch.mockClear()
  })

  test('renders the application title', () => {
    fetch.mockResolvedValueOnce({
      json: async () => ({ status: 'healthy' }),
    })
    render(<App />)
    expect(screen.getByText('Full-Stack Application')).toBeInTheDocument()
  })

  test('displays health status', async () => {
    fetch.mockResolvedValueOnce({
      json: async () => ({ status: 'healthy' }),
    })
    render(<App />)
    await waitFor(() => {
      expect(screen.getByText(/Status:/)).toBeInTheDocument()
    })
  })

  test('calls hello endpoint when button is clicked', async () => {
    const user = userEvent.setup()
    fetch
      .mockResolvedValueOnce({
        json: async () => ({ status: 'healthy' }),
      })
      .mockResolvedValueOnce({
        json: async () => ({ message: 'hello from backend' }),
      })

    render(<App />)
    const helloButton = await screen.findByText('Call /api/hello')
    await user.click(helloButton)

    await waitFor(() => {
      expect(screen.getByText('hello from backend')).toBeInTheDocument()
    })
  })

  test('calls greet endpoint with user input', async () => {
    const user = userEvent.setup()
    fetch
      .mockResolvedValueOnce({
        json: async () => ({ status: 'healthy' }),
      })
      .mockResolvedValueOnce({
        json: async () => ({ message: 'Hello, Alice!' }),
      })

    render(<App />)
    const input = await screen.findByPlaceholderText('Enter your name')
    const greetButton = await screen.findByText('Greet')

    await user.type(input, 'Alice')
    await user.click(greetButton)

    await waitFor(() => {
      expect(screen.getByText('Hello, Alice!')).toBeInTheDocument()
    })
  })
})

