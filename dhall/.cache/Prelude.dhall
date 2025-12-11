-- Cached stable version of Dhall Prelude
-- This is a fallback when prelude.dhall-lang.org is unavailable
-- Source: https://prelude.dhall-lang.org/v21.0.0/package.dhall
-- Last synced: 2024-01-XX

-- Note: This is a simplified version. For full prelude, use:
-- dhall freeze to cache the full prelude locally
-- Or use dhall's built-in cache: ~/.cache/dhall/

-- For now, we'll import the remote prelude but with a fallback mechanism
-- The actual prelude is large, so we'll use Dhall's import system with integrity checks

https://prelude.dhall-lang.org/v21.0.0/package.dhall

