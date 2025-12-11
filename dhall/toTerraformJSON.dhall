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
        ? ../DEVOPS/config/types/Service.dhall
        ? ./.cache/Service.dhall

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
let toTerraformALB = \(alb : Service.ALBConfig) ->
      let healthCheckPath =
            Prelude.Optional.fold Text "/" (\(path : Text) -> path) alb.health_check_path
      
      let healthCheckPort =
            Prelude.Optional.fold Text "traffic-port" (\(p : Text) -> p) alb.health_check_port

      let healthCheckMatcher =
            Prelude.Optional.fold Text "200" (\(m : Text) -> m) alb.health_check_matcher

      let healthCheckInterval =
            Prelude.Optional.fold Natural 30 (\(n : Natural) -> n) alb.health_check_interval

      let healthCheckTimeout =
            Prelude.Optional.fold Natural 5 (\(n : Natural) -> n) alb.health_check_timeout

      let healthyThreshold =
            Prelude.Optional.fold Natural 2 (\(n : Natural) -> n) alb.health_check_healthy_threshold

      let unhealthyThreshold =
            Prelude.Optional.fold Natural 2 (\(n : Natural) -> n) alb.health_check_unhealthy_threshold
      
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
            Prelude.Optional.fold Text "latest" (\(t : Text) -> t) service.image_tag

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
      
      in  { services = Prelude.Map.fromList Text TerraformService terraformServices }

in  toTerraformJSON
