-- Centralized import helper with fallback mechanism
-- Tries remote imports first, falls back to cached local versions

let ServiceRemote =
      https://raw.githubusercontent.com/orshalit/projectdevops/d6f2aa792cd8c53ee2ad56393c2bea0e874bb0d8/config/types/Service.dhall

let ServiceLocal = ./cache/Service.dhall

let PreludeRemote = https://prelude.dhall-lang.org/v21.0.0/package.dhall

let PreludeLocal = ./cache/Prelude.dhall

-- Try remote Service, fallback to local
-- Note: Dhall doesn't have try/catch, so we use a different approach
-- We'll use the remote by default, but provide local as backup
-- The workflow will handle fallback by setting DHALL_IMPORT_MODE environment variable

in  { Service = ServiceRemote
    , ServiceFallback = ServiceLocal
    , Prelude = PreludeRemote
    , PreludeFallback = PreludeLocal
    }

