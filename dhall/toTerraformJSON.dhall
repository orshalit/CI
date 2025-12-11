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
      https://raw.githubusercontent.com/orshalit/DEVOPS/b593194afb2c3be99edb55e6cd93c1494e20dc06/config/types/Service.dhall

-- Terraform service type (what Terraform expects)
let TerraformService =
      { container_image : Text
      , image_tag : Text
      , container_port : Natural
      , cpu : Natural
      , memory : Natural
      , desired_count : Natural
      , application : Text
      , environment_variables : List { mapKey : Text, mapValue : Text }
      , alb : { alb_id : Text
              , listener_protocol : Text
              , listener_port : Natural
              , path_patterns : List Text
              , host_patterns : List Text
              , health_check_path : Text
              }
      }

-- Convert ALB config to Terraform format
let toTerraformALB = \(alb : Service.ALBConfig) ->
      let healthCheckPath =
            Prelude.Optional.fold Text "/" (\(path : Text) -> path) alb.health_check_path
      
      in  { alb_id = alb.alb_id
          , listener_protocol = alb.listener_protocol
          , listener_port = alb.listener_port
          , path_patterns = alb.path_patterns
          , host_patterns = alb.host_patterns
          , health_check_path = healthCheckPath
          }

-- Convert Service to Terraform format
let toTerraformService = \(service : Service) ->
      -- Convert ALB config
      let albConfig = toTerraformALB service.alb
      
      in  { container_image = service.image_repo
          , image_tag = "latest"  -- Will be overridden by global_image_tag during deployment
          , container_port = service.container_port
          , cpu = service.cpu
          , memory = service.memory
          , desired_count = service.desired_count
          , application = service.application
          , environment_variables = service.env
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
