-- Convert Service type to Terraform JSON tfvars format
-- Usage: dhall-to-json --file services.tfvarsJSON.dhall > services.generated.json
-- 
-- This returns a JSON-compatible record structure. dhall-to-json handles
-- all JSON encoding automatically - no manual string templates needed!
--
-- The output format matches Terraform's variable structure:
-- {
--   "services": {
--     "application::service-name": {
--       "container_image": "...",
--       "image_tag": "...",
--       ...
--     }
--   }
-- }

let Prelude = https://prelude.dhall-lang.org/v21.0.0/package.dhall

let Service =
      ../DEVOPS/config/types/Service.dhall
        ? ./.cache/Service.dhall

-- ALB config type (matches Service.alb structure)
let ALBConfig =
      { alb_id : Text
      , listener_protocol : Text
      , listener_port : Natural
      , path_patterns : List Text
      , host_patterns : List Text
      , health_check_path : Optional Text
      , health_check_port : Optional Text
      , health_check_matcher : Optional Text
      , health_check_interval : Optional Natural
      , health_check_timeout : Optional Natural
      , health_check_healthy_threshold : Optional Natural
      , health_check_unhealthy_threshold : Optional Natural
      , priority : Optional Natural
      }

-- Terraform service type (what Terraform expects)
let TerraformService =
      { container_image : Text
      , image_tag : Text
      , container_port : Natural
      , cpu : Natural
      , memory : Natural
      , desired_count : Natural
      , application : Text
      , environment_variables : Prelude.Map.Type Text Text
      , secrets : Prelude.Map.Type Text Text
      , service_discovery_name : Optional Text
      , alb : { alb_id : Text
              , listener_protocol : Text
              , listener_port : Natural
              , path_patterns : List Text
              , host_patterns : List Text
              , priority : Optional Natural
              , health_check_path : Text
              , health_check_port : Text
              , health_check_matcher : Text
              , health_check_interval : Natural
              , health_check_timeout : Natural
              , health_check_healthy_thr : Natural
              , health_check_unhealthy_thr : Natural
              }
      }

-- Convert ALB config to Terraform format
let toTerraformALB = \(alb : ALBConfig) ->
      let healthCheckPath =
            Prelude.Optional.fold Text alb.health_check_path Text "/" (\(path : Text) -> path)
      
      let healthCheckPort =
            Prelude.Optional.fold Text alb.health_check_port Text "traffic-port" (\(p : Text) -> p)

      let healthCheckMatcher =
            Prelude.Optional.fold Text alb.health_check_matcher Text "200" (\(m : Text) -> m)

      let healthCheckInterval =
            Prelude.Optional.fold Natural alb.health_check_interval Natural 30 (\(n : Natural) -> n)

      let healthCheckTimeout =
            Prelude.Optional.fold Natural alb.health_check_timeout Natural 5 (\(n : Natural) -> n)

      let healthyThreshold =
            Prelude.Optional.fold Natural alb.health_check_healthy_threshold Natural 2 (\(n : Natural) -> n)

      let unhealthyThreshold =
            Prelude.Optional.fold Natural alb.health_check_unhealthy_threshold Natural 2 (\(n : Natural) -> n)
      
      in  { alb_id = alb.alb_id
          , listener_protocol = alb.listener_protocol
          , listener_port = alb.listener_port
          , path_patterns = alb.path_patterns
          , host_patterns = alb.host_patterns
          , priority = alb.priority
          , health_check_path = healthCheckPath
          , health_check_port = healthCheckPort
          , health_check_matcher = healthCheckMatcher
          , health_check_interval = healthCheckInterval
          , health_check_timeout = healthCheckTimeout
          , health_check_healthy_thr = healthyThreshold
          , health_check_unhealthy_thr = unhealthyThreshold
          }

-- Convert Service to Terraform format
let toTerraformService = \(service : Service) ->
      let imageTag =
            Prelude.Optional.fold Text service.image_tag Text "latest" (\(t : Text) -> t)

      -- Convert ALB config
      let albConfig = toTerraformALB service.alb
      
      in  { container_image = service.image_repo
          , image_tag = imageTag
          , container_port = service.container_port
          , cpu = service.cpu
          , memory = service.memory
          , desired_count = service.desired_count
          , application = service.application
          , environment_variables = service.env
          , secrets = service.secrets
          , service_discovery_name = service.service_discovery_name
          , alb = albConfig
          }

-- Main converter: takes services map and returns Terraform JSON format
let toTerraformJSON = \(servicesMap : List { mapKey : Text, mapValue : Service }) ->
      let terraformServices =
            Prelude.List.map
              { mapKey : Text, mapValue : Service }
              { mapKey : Text, mapValue : TerraformService }
              (\(entry : { mapKey : Text, mapValue : Service }) ->
                { mapKey = "${entry.mapValue.application}::${entry.mapValue.name}"
                , mapValue = toTerraformService entry.mapValue
                }
              )
              servicesMap
      
      -- terraformServices is already a List { mapKey, mapValue } which IS a Dhall Map
      in  { services = terraformServices }

in  toTerraformJSON
