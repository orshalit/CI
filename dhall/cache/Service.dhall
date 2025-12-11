-- Cached stable version of Service.dhall type definition
-- This is a fallback when remote imports fail
-- Source: DEVOPS/config/types/Service.dhall
-- Last synced: 2024-01-XX (update when Service.dhall changes)

let Prelude = https://prelude.dhall-lang.org/v21.0.0/package.dhall

let ALBConfig =
      { alb_id : Text
      , listener_protocol : Text
      , listener_port : Natural
      , path_patterns : List Text
      , host_patterns : List Text
      , health_check_path : Prelude.Optional.Type Text
      }

in  { name : Text
    , application : Text
    , image_repo : Text
    , container_port : Natural
    , cpu : Natural
    , memory : Natural
    , desired_count : Natural
    , env : List { mapKey : Text, mapValue : Text }
    , alb : ALBConfig
    }

