-- Aggregates all service definitions into a map
-- Used by services.tfvarsJSON.dhall to generate Terraform configuration
let Prelude = https://prelude.dhall-lang.org/v21.0.0/package.dhall

let Service = ../DEVOPS/config/types/Service.dhall

let servicesList =
      [ ./applications/test-app/api.dhall
      , ./applications/test-app/frontend.dhall
      ]

-- Convert list to map using List.fold with Map.insert
let servicesEntries =
      Prelude.List.map
        Service
        { mapKey : Text, mapValue : Service }
        (\(service : Service) -> { mapKey = service.name, mapValue = service })
        servicesList

let emptyMap = Prelude.Map.empty Text Service

in  Prelude.List.fold
      { mapKey : Text, mapValue : Service }
      servicesEntries
      (Prelude.Map.Type Text Service)
      (\(entry : { mapKey : Text, mapValue : Service }) ->
        \(acc : Prelude.Map.Type Text Service) ->
          Prelude.Map.insert Text Service entry.mapKey entry.mapValue acc
      )
      emptyMap

