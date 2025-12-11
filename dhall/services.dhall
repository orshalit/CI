-- Aggregates all service definitions into a map
-- Used by services.tfvarsJSON.dhall to generate Terraform configuration
let Prelude = https://prelude.dhall-lang.org/v21.0.0/package.dhall

let Service =
      ../DEVOPS/config/types/Service.dhall
        ? ./.cache/Service.dhall

let servicesList =
      [ ./applications/test-app/api.dhall
      , ./applications/test-app/frontend.dhall
      ]

-- Convert list to map by transforming each service to a map entry
-- In Dhall, Map a b = List { mapKey : a, mapValue : b }, so the result IS the map
in  Prelude.List.map
      Service
      { mapKey : Text, mapValue : Service }
      (\(service : Service) -> { mapKey = service.name, mapValue = service })
      servicesList

