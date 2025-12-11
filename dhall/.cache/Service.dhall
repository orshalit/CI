-- Cached stable version of Service.dhall type definition
-- This is a fallback when remote imports fail
-- Source: DEVOPS/config/types/Service.dhall
-- Last synced: 2024-01-XX (update when Service.dhall changes)

let Prelude = ./Prelude.dhall

let ALBConfig =
      { alb_id : Text
      , listener_protocol : Text
      , listener_port : Natural
      , path_patterns : List Text
      , host_patterns : List Text
      , health_check_path : Prelude.Optional.Type Text
      , health_check_port : Prelude.Optional.Type Text
      , health_check_matcher : Prelude.Optional.Type Text
      , health_check_interval : Prelude.Optional.Type Natural
      , health_check_timeout : Prelude.Optional.Type Natural
      , health_check_healthy_threshold : Prelude.Optional.Type Natural
      , health_check_unhealthy_threshold : Prelude.Optional.Type Natural
      , priority : Prelude.Optional.Type Natural
      }

in  { name : Text
    , application : Text
    , image_repo : Text
    , image_tag : Prelude.Optional.Type Text
    , container_port : Natural
    , cpu : Natural
    , memory : Natural
    , desired_count : Natural
    , env : Prelude.Map.Type Text Text
    , secrets : Prelude.Map.Type Text Text
    , service_discovery_name : Prelude.Optional.Type Text
    , alb : ALBConfig
    }

