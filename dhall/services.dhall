-- Aggregates all service definitions into a map
-- Used by services.tfvarsJSON.dhall to generate Terraform configuration
let Prelude = https://prelude.dhall-lang.org/v21.0.0/package.dhall

let Service =
      https://raw.githubusercontent.com/orshalit/projectdevops/main/config/types/Service.dhall

let servicesList =
      [ ./applications/test-app/api.dhall
      , ./applications/test-app/frontend.dhall
      ]

-- Convert list to map using Map.fromList (List.toMap doesn't exist)
let servicesEntries =
      Prelude.List.map
        Service
        { mapKey : Text, mapValue : Service }
        (\(service : Service) -> { mapKey = service.name, mapValue = service })
        servicesList

in  Prelude.Map.fromList Service servicesEntries

